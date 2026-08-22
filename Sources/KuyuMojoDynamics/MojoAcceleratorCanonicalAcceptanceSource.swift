import Foundation
import KuyuCore
import KuyuMojoCore
import KuyuPhysics
import simd

package enum MojoAcceleratorCanonicalAcceptanceSource {
    package enum GenerationError: Error, Equatable {
        case compiledProgramStructureMismatch
        case missingForceTerm(CanonicalForceTermID)
        case missingOutput(graphID: String, outputID: String)
        case unrepresentableOutput(graphID: String, outputID: String)
        case missingAcceptanceScenario(graphID: String)
        case inconsistentInvocationLayout(graphID: String)
        case unsupportedDeviceClass(MojoDeviceClass)
        case unsafeGraphIdentifier(String)
    }

    private struct Scenario {
        let state: ReferenceQuadrotorState
        let parameters: ReferenceQuadrotorParameters
        let mixer: ReferenceQuadrotorMixer
        let thrusts: MotorThrusts
        let disturbances: DisturbanceState
        let environment: WorldEnvironment
        let force: QuadrotorGeneralizedForce
    }

    private struct OutputExpectation {
        let offset: Int
        let values: [Float]
    }

    private struct GraphExpectation {
        let graphID: String
        let plan: [Float]
        let runtimeInputs: [Float]
        let workspaceElementCount: Int
        let batchCount: Int
        let outputs: [[OutputExpectation]]
        let tolerance: MojoParityTolerance
    }

    package static func source(
        for deviceClass: MojoDeviceClass
    ) throws -> String {
        guard deviceClass == .metal || deviceClass == .cuda else {
            throw GenerationError.unsupportedDeviceClass(deviceClass)
        }
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let cpuProgram = try KuyuMojoProgramCompiler(
            numericType: .float32,
            deviceClass: .cpu
        ).compile(program)
        let acceleratorProgram = try KuyuMojoProgramCompiler(
            numericType: .float32,
            deviceClass: deviceClass
        ).compile(program)
        guard cpuProgram.forceTermIDs == acceleratorProgram.forceTermIDs,
            cpuProgram.identity.programDigest
                == acceleratorProgram.identity.programDigest
        else {
            throw GenerationError.compiledProgramStructureMismatch
        }

        let scenarios = try acceptanceScenarios(program: program)
        let parity = ReferenceQuadrotorMojoParityContract.tolerances(
            for: .float32
        )
        let executor = MojoFloat32GraphExecutor()
        var expectations: [GraphExpectation] = []

        for termID in cpuProgram.forceTermIDs {
            guard let cpuGraph = cpuProgram.forceTerms[termID],
                let acceleratorGraph = acceleratorProgram.forceTerms[termID]
            else {
                throw GenerationError.missingForceTerm(termID)
            }
            let inputs = try scenarios.map { scenario in
                try requiredInputs(
                    graph: cpuGraph,
                    program: program,
                    scenario: scenario,
                    includeMixerAndControl: true,
                    includeEnvironment: true,
                    includeForce: false
                )
            }
            expectations.append(
                try expectation(
                    cpuGraph: cpuGraph,
                    acceleratorGraph: acceleratorGraph,
                    inputs: inputs,
                    tolerance: parity.generalizedForce,
                    executor: executor
                )
            )
        }

        let derivativeInputs = try scenarios.map { scenario in
            try requiredInputs(
                graph: cpuProgram.derivative,
                program: program,
                scenario: scenario,
                includeMixerAndControl: false,
                includeEnvironment: false,
                includeForce: true
            )
        }
        expectations.append(
            try expectation(
                cpuGraph: cpuProgram.derivative,
                acceleratorGraph: acceleratorProgram.derivative,
                inputs: derivativeInputs,
                tolerance: parity.derivative,
                executor: executor
            )
        )

        let observableInputs = try scenarios.map { scenario in
            try requiredInputs(
                graph: cpuProgram.observables,
                program: program,
                scenario: scenario,
                includeMixerAndControl: false,
                includeEnvironment: true,
                includeForce: true
            )
        }
        expectations.append(
            try expectation(
                cpuGraph: cpuProgram.observables,
                acceleratorGraph: acceleratorProgram.observables,
                inputs: observableInputs,
                tolerance: parity.observables,
                executor: executor
            )
        )

        return try render(
            programDigest: program.digest.rawValue,
            deviceClass: deviceClass,
            expectations: expectations
        )
    }

    private static func acceptanceScenarios(
        program: CanonicalDynamicsProgram
    ) throws -> [Scenario] {
        let parameters = ReferenceQuadrotorParameters.baseline
        let mixer = ReferenceQuadrotorMixer(
            armLength: parameters.armLength,
            yawCoefficient: parameters.yawCoefficient
        )
        let specifications:
            [(
                ReferenceQuadrotorState,
                MotorThrusts,
                DisturbanceState,
                WorldEnvironment
            )] = [
                (
                    try ReferenceQuadrotorState(
                        position: SIMD3<Double>(0.1, -0.2, 1.3),
                        velocity: SIMD3<Double>(1.1, -0.4, 0.3),
                        orientation: simd_quatd(
                            angle: 0.22,
                            axis: simd_normalize(SIMD3<Double>(0.5, -1, 2))
                        ),
                        angularVelocity: SIMD3<Double>(0.3, -0.5, 0.2)
                    ),
                    try MotorThrusts(f1: 1.3, f2: 1.4, f3: 1.5, f4: 1.6),
                    DisturbanceState(
                        torqueBody: SIMD3<Double>(0.01, 0.02, -0.03),
                        forceWorld: SIMD3<Double>(-0.1, 0.2, 0.05)
                    ),
                    try WorldEnvironment(
                        gravity: 9.73,
                        windVelocityWorld: Axis3(x: 0.8, y: -0.2, z: 0.15),
                        airPressure: 94_500,
                        airTemperature: 281,
                        usage: .full
                    )
                ),
                (
                    try ReferenceQuadrotorState(
                        position: .zero,
                        velocity: .zero,
                        orientation: simd_quatd(
                            angle: 0,
                            axis: SIMD3<Double>(0, 0, 1)
                        ),
                        angularVelocity: .zero
                    ),
                    try MotorThrusts(f1: 0.4, f2: 0.7, f3: 0.2, f4: 0.9),
                    .zero,
                    try WorldEnvironment(
                        gravity: 9.80665,
                        windVelocityWorld: Axis3(x: 0, y: 0, z: 0),
                        airPressure: 101_325,
                        airTemperature: 288.15,
                        usage: .full
                    )
                ),
            ]
        let reference = ReferenceQuadrotorScalarDynamicsExecutor()
        return try specifications.map { specification in
            let (state, thrusts, disturbances, environment) = specification
            return Scenario(
                state: state,
                parameters: parameters,
                mixer: mixer,
                thrusts: thrusts,
                disturbances: disturbances,
                environment: environment,
                force: try reference.generalizedForce(
                    program: program,
                    state: state,
                    parameters: parameters,
                    mixer: mixer,
                    motorThrusts: thrusts,
                    disturbances: disturbances,
                    environment: environment,
                    activeTerms: ReferenceQuadrotorFidelity.full.active
                )
            )
        }
    }

    private static func requiredInputs(
        graph: MojoCompiledGraph,
        program: CanonicalDynamicsProgram,
        scenario: Scenario,
        includeMixerAndControl: Bool,
        includeEnvironment: Bool,
        includeForce: Bool
    ) throws -> [CanonicalValueID: MojoCanonicalValue] {
        let available = try ReferenceQuadrotorMojoInputs.availableValues(
            program: program,
            state: scenario.state,
            parameters: scenario.parameters,
            mixer: includeMixerAndControl ? scenario.mixer : nil,
            motorThrusts: includeMixerAndControl ? scenario.thrusts : nil,
            disturbances: includeMixerAndControl ? scenario.disturbances : nil,
            environment: includeEnvironment ? scenario.environment : nil,
            force: includeForce ? scenario.force : nil
        )
        return try ReferenceQuadrotorMojoInputs.requiredValues(
            for: graph,
            available: available
        )
    }

    private static func expectation(
        cpuGraph: MojoCompiledGraph,
        acceleratorGraph: MojoCompiledGraph,
        inputs: [[CanonicalValueID: MojoCanonicalValue]],
        tolerance: MojoParityTolerance,
        executor: MojoFloat32GraphExecutor
    ) throws -> GraphExpectation {
        guard cpuGraph.graphID == acceleratorGraph.graphID,
            cpuGraph.workspaceElementCount
                == acceleratorGraph.workspaceElementCount,
            cpuGraph.encodedPlan == acceleratorGraph.encodedPlan,
            cpuGraph.inputs == acceleratorGraph.inputs,
            cpuGraph.outputs == acceleratorGraph.outputs
        else {
            throw GenerationError.compiledProgramStructureMismatch
        }
        guard let firstInputs = inputs.first else {
            throw GenerationError.missingAcceptanceScenario(
                graphID: acceleratorGraph.graphID
            )
        }
        let firstInvocation = try MojoFloat32GraphInvocation(
            graph: acceleratorGraph,
            inputs: firstInputs
        )
        var runtimeInputs: [Float] = []
        var outputBatches: [[OutputExpectation]] = []
        for batchInputs in inputs {
            let invocation = try MojoFloat32GraphInvocation(
                graph: acceleratorGraph,
                inputs: batchInputs
            )
            guard invocation.plan == firstInvocation.plan,
                invocation.workspaceElementCount
                    == firstInvocation.workspaceElementCount,
                invocation.runtimeInput.count
                    == firstInvocation.runtimeInput.count
            else {
                throw GenerationError.inconsistentInvocationLayout(
                    graphID: acceleratorGraph.graphID
                )
            }
            runtimeInputs.append(contentsOf: invocation.runtimeInput)
            let actual = try executor.execute(cpuGraph, inputs: batchInputs)
            var expectations: [OutputExpectation] = []
            for output in cpuGraph.outputs {
                guard let value = actual[output.outputID] else {
                    throw GenerationError.missingOutput(
                        graphID: cpuGraph.graphID,
                        outputID: output.outputID
                    )
                }
                var values: [Float] = []
                guard value.appendFloat32(to: &values) else {
                    throw GenerationError.unrepresentableOutput(
                        graphID: cpuGraph.graphID,
                        outputID: output.outputID
                    )
                }
                expectations.append(
                    OutputExpectation(offset: output.offset, values: values)
                )
            }
            outputBatches.append(expectations)
        }
        return GraphExpectation(
            graphID: acceleratorGraph.graphID,
            plan: firstInvocation.plan,
            runtimeInputs: runtimeInputs,
            workspaceElementCount: firstInvocation.workspaceElementCount,
            batchCount: inputs.count,
            outputs: outputBatches,
            tolerance: tolerance
        )
    }

    private static func render(
        programDigest: String,
        deviceClass: MojoDeviceClass,
        expectations: [GraphExpectation]
    ) throws -> String {
        var source = """
            from std.collections import List
            from std.math import abs
            from std.memory import bitcast
            from std.utils.numerics import isfinite

            from KuyuCanonicalDynamics.accelerator import (
                execute_graph_float32_accelerator,
            )


            def _float32(bits: UInt32) -> Float32:
                return bitcast[DType.float32, 1](bits)


            def _close(actual: Float32, expected: Float32, absolute: Float32, relative: Float32) -> Bool:
                if not isfinite(actual) or not isfinite(expected):
                    return False
                return abs(actual - expected) <= absolute + relative * abs(expected)

            """
        for (index, expectation) in expectations.enumerated() {
            source += try render(expectation: expectation, index: index)
        }
        source += "\n\ndef main() raises:\n"
        for index in expectations.indices {
            source += "    _verify_\(index)()\n"
        }
        source += "    print(\"canonical_program_digest=\(programDigest)\")\n"
        source += "    print(\"canonical_graph_count=\(expectations.count)\")\n"
        source += "    print(\"canonical_accelerator_device=\(deviceClass.rawValue)\")\n"
        source += "    print(\"canonical_accelerator_differential=ok\")\n"
        return source
    }

    private static func render(
        expectation: GraphExpectation,
        index: Int
    ) throws -> String {
        guard
            expectation.graphID.utf8.allSatisfy({ byte in
                byte >= 32 && byte < 127 && byte != 34 && byte != 92
            })
        else {
            throw GenerationError.unsafeGraphIdentifier(expectation.graphID)
        }
        var source = "\n\ndef _verify_\(index)() raises:\n"
        source += renderList(name: "plan", values: expectation.plan)
        source += renderList(
            name: "runtime_inputs",
            values: expectation.runtimeInputs
        )
        source += "    var result = execute_graph_float32_accelerator(\n"
        source += "        plan^,\n"
        source += "        runtime_inputs^,\n"
        source += "        workspace_count=\(expectation.workspaceElementCount),\n"
        source += "        batch_count=\(expectation.batchCount),\n"
        source += "    )\n"
        for batchIndex in 0..<expectation.batchCount {
            source += "    if result[1][\(batchIndex)] != 0:\n"
            source +=
                "        raise Error(\"canonical graph backend failure: \(expectation.graphID)\")\n"
            for output in expectation.outputs[batchIndex] {
                for (component, expected) in output.values.enumerated() {
                    let workspaceIndex =
                        batchIndex
                        * expectation.workspaceElementCount
                        + output.offset + component
                    source +=
                        "    if not _close(result[0][\(workspaceIndex)], _float32(\(expected.bitPattern)), Float32(\(expectation.tolerance.absolute)), Float32(\(expectation.tolerance.relative))):\n"
                    source +=
                        "        raise Error(\"canonical graph differential mismatch: \(expectation.graphID)\")\n"
                }
            }
        }
        source +=
            "    print(\"canonical_graph=\(expectation.graphID) batches=\(expectation.batchCount) ok\")\n"
        return source
    }

    private static func renderList(
        name: String,
        values: [Float]
    ) -> String {
        var source = "    var \(name): List[Float32] = [\n"
        for chunkStart in stride(from: 0, to: values.count, by: 8) {
            let chunkEnd = min(chunkStart + 8, values.count)
            source += "        "
            source += values[chunkStart..<chunkEnd]
                .map { "_float32(\($0.bitPattern))" }
                .joined(separator: ", ")
            source += ",\n"
        }
        source += "    ]\n"
        return source
    }
}
