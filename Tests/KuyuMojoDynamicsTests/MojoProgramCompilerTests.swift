import KuyuMojoCore
import KuyuPhysics
@testable import KuyuMojoDynamics
import Testing

@Suite("Mojo canonical program compiler")
struct MojoProgramCompilerTests {
    @Test(.timeLimit(.minutes(1)))
    func compilesReferenceProgramIntoStableCPUPlans() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        for (numericType, executorVersion, planMagic) in [
            (
                MojoNumericType.float32,
                KuyuMojoProgramCompiler.float32ExecutorVersion,
                KuyuMojoProgramCompiler.float32PlanMagic
            ),
            (
                MojoNumericType.float64,
                KuyuMojoProgramCompiler.float64ExecutorVersion,
                KuyuMojoProgramCompiler.float64PlanMagic
            ),
        ] {
            let compiler = KuyuMojoProgramCompiler(numericType: numericType)
            let first = try compiler.compile(program)
            let second = try compiler.compile(program)

            #expect(first == second)
            #expect(first.identity.programDigest == program.digest.rawValue)
            #expect(
                first.identity.programSchemaVersion
                    == CanonicalDynamicsProgram.currentSchemaVersion
            )
            #expect(first.identity.executorVersion == executorVersion)
            #expect(first.identity.numericType == numericType)
            #expect(first.identity.deviceClass == .cpu)
            #expect(first.forceTermIDs.count == 9)
            #expect(first.derivative.workspaceElementCount > 0)
            #expect(first.observables.workspaceElementCount > 0)
            #expect(first.derivative.encodedPlan.first == Double(planMagic))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceleratorCompilationPreservesCanonicalGraphStructure() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let cpu = try KuyuMojoProgramCompiler(
            numericType: .float32,
            deviceClass: .cpu
        ).compile(program)
        let accelerator = try KuyuMojoProgramCompiler(
            numericType: .float32,
            deviceClass: .accelerator
        ).compile(program)

        #expect(cpu.identity.deviceClass == .cpu)
        #expect(accelerator.identity.deviceClass == .accelerator)
        #expect(
            accelerator.identity.executorVersion
                == KuyuMojoProgramCompiler.acceleratorFloat32ExecutorVersion
        )
        #expect(
            cpu.identity.programDigest == accelerator.identity.programDigest
        )
        #expect(cpu.forceTermIDs == accelerator.forceTermIDs)
        for termID in cpu.forceTermIDs {
            let cpuGraph = try #require(cpu.forceTerms[termID])
            let acceleratorGraph = try #require(
                accelerator.forceTerms[termID]
            )
            expectSameGraphStructure(cpuGraph, acceleratorGraph)
        }
        expectSameGraphStructure(cpu.derivative, accelerator.derivative)
        expectSameGraphStructure(cpu.observables, accelerator.observables)
    }

    @Test(.timeLimit(.minutes(1)))
    func acceleratorCompilationRejectsUnsupportedFloat64() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        #expect(
            throws: MojoProgramCompilationError.unsupportedNumericType(
                deviceClass: .accelerator,
                numericType: .float64
            )
        ) {
            _ = try KuyuMojoProgramCompiler(
                numericType: .float64,
                deviceClass: .accelerator
            ).compile(program)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func float32InvocationSeparatesPlanFromRuntimeInput() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let graph = try KuyuMojoProgramCompiler(numericType: .float32)
            .compile(program)
            .derivative
        let inputs = Dictionary(
            uniqueKeysWithValues: graph.inputs.map {
                ($0.valueID, finiteZero(shape: $0.shape))
            }
        )
        let invocation = try MojoFloat32GraphInvocation(
            graph: graph,
            inputs: inputs
        )

        #expect(invocation.plan == graph.encodedPlan.map(Float.init))
        #expect(invocation.plan[7] == Float(invocation.plan.count))
        #expect(invocation.plan[4] == Float(invocation.runtimeInput.count))
        #expect(
            invocation.runtimeInput.count
                == graph.inputs.reduce(0) { $0 + $1.shape.elementCount }
        )
        #expect(invocation.workspaceElementCount == graph.workspaceElementCount)

        var invalidStorage = graph.encodedPlan
        invalidStorage[7] += 0.25
        let invalidGraph = MojoCompiledGraph(
            identity: graph.identity,
            graphID: graph.graphID,
            workspaceElementCount: graph.workspaceElementCount,
            encodedPlan: invalidStorage,
            inputs: graph.inputs,
            outputs: graph.outputs
        )
        #expect(
            throws: MojoProgramExecutionError.invalidPlanLayout(
                graphID: graph.graphID
            )
        ) {
            _ = try MojoFloat32GraphInvocation(
                graph: invalidGraph,
                inputs: inputs
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceleratorAcceptanceSourceIsDeterministicAndCanonical() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let accelerator = try MojoAcceleratorCanonicalAcceptanceSource.source(
            for: .accelerator
        )
        let repeated = try MojoAcceleratorCanonicalAcceptanceSource.source(
            for: .accelerator
        )

        #expect(accelerator == repeated)
        #expect(
            accelerator.contains(
                "canonical_program_digest=\(program.digest.rawValue)"
            )
        )
        #expect(accelerator.contains("canonical_graph_count=11"))
        #expect(
            accelerator.contains("canonical_accelerator_device=accelerator")
        )
        #expect(
            accelerator.contains("canonical_accelerator_differential=ok")
        )
        #expect(
            accelerator.components(separatedBy: "canonical_graph=").count - 1
                == 11
        )
        #expect(
            throws: MojoAcceleratorCanonicalAcceptanceSource.GenerationError
                .unsupportedDeviceClass(.cpu)
        ) {
            _ = try MojoAcceleratorCanonicalAcceptanceSource.source(for: .cpu)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func graphExecutorRejectsMissingShapeAndNonFiniteInputs() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let graph = try KuyuMojoProgramCompiler()
            .compile(program)
            .derivative
        let firstInput = try #require(graph.inputs.first)
        let executor = MojoFloat64GraphExecutor()

        #expect(
            throws: MojoProgramExecutionError.missingInput(firstInput.valueID)
        ) {
            _ = try executor.execute(graph, inputs: [:])
        }
        #expect(
            throws: MojoProgramExecutionError.inputShapeMismatch(
                valueID: firstInput.valueID,
                expected: firstInput.shape,
                actual: .scalar
            )
        ) {
            _ = try executor.execute(
                graph,
                inputs: [firstInput.valueID: .scalar(0)]
            )
        }
        #expect(
            throws: MojoProgramExecutionError.nonFiniteInput(firstInput.valueID)
        ) {
            var values: [CanonicalValueID: MojoCanonicalValue] = [:]
            for binding in graph.inputs {
                values[binding.valueID] = finiteZero(shape: binding.shape)
            }
            values[firstInput.valueID] = nonFiniteValue(shape: firstInput.shape)
            _ = try executor.execute(graph, inputs: values)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func graphExecutorClassifiesArithmeticAndPlanFailures() throws {
        let compiler = KuyuMojoProgramCompiler()
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let identity = try compiler.compile(program).identity
        let executor = MojoFloat64GraphExecutor()

        let division = try compiler.compile(
            arithmeticGraph(
                id: "division_by_zero",
                opcode: .divide,
                lhs: 1,
                rhs: 0
            ),
            layouts: [],
            identity: identity
        )
        #expect(throws: MojoProgramExecutionError.backendFailure(status: 4)) {
            _ = try executor.execute(division, inputs: [:])
        }

        let overflow = try compiler.compile(
            arithmeticGraph(
                id: "non_finite_result",
                opcode: .multiply,
                lhs: .greatestFiniteMagnitude,
                rhs: 2
            ),
            layouts: [],
            identity: identity
        )
        #expect(throws: MojoProgramExecutionError.backendFailure(status: 5)) {
            _ = try executor.execute(overflow, inputs: [:])
        }

        var invalidOpcodePlan = overflow.encodedPlan
        invalidOpcodePlan[KuyuMojoProgramCompiler.headerElementCount] = 99
        let invalidOpcode = MojoCompiledGraph(
            identity: overflow.identity,
            graphID: overflow.graphID,
            workspaceElementCount: overflow.workspaceElementCount,
            encodedPlan: invalidOpcodePlan,
            inputs: overflow.inputs,
            outputs: overflow.outputs
        )
        #expect(throws: MojoProgramExecutionError.backendFailure(status: 3)) {
            _ = try executor.execute(invalidOpcode, inputs: [:])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func float32ExecutionRejectsNumericMismatchAndOverflow() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let graph = try KuyuMojoProgramCompiler(numericType: .float32)
            .compile(program)
            .derivative
        #expect(
            throws: MojoProgramExecutionError.numericTypeMismatch(
                expected: .float32,
                actual: .float64
            )
        ) {
            _ = try MojoFloat64GraphExecutor().execute(graph, inputs: [:])
        }

        let firstInput = try #require(graph.inputs.first)
        var overflowInputs: [CanonicalValueID: MojoCanonicalValue] = [:]
        for binding in graph.inputs {
            overflowInputs[binding.valueID] = finiteZero(shape: binding.shape)
        }
        overflowInputs[firstInput.valueID] = finiteOverflowValue(
            shape: firstInput.shape
        )
        #expect(
            throws: MojoProgramExecutionError.inputNotRepresentable(
                valueID: firstInput.valueID,
                numericType: .float32
            )
        ) {
            _ = try MojoFloat32GraphExecutor().execute(
                graph,
                inputs: overflowInputs
            )
        }

        var corruptPlanStorage = graph.encodedPlan
        corruptPlanStorage[0] = .greatestFiniteMagnitude
        let corruptPlan = MojoCompiledGraph(
            identity: graph.identity,
            graphID: graph.graphID,
            workspaceElementCount: graph.workspaceElementCount,
            encodedPlan: corruptPlanStorage,
            inputs: graph.inputs,
            outputs: graph.outputs
        )
        #expect(
            throws: MojoProgramExecutionError.planNotRepresentable(
                graphID: graph.graphID,
                numericType: .float32
            )
        ) {
            _ = try MojoFloat32GraphExecutor().execute(
                corruptPlan,
                inputs: Dictionary(
                    uniqueKeysWithValues: graph.inputs.map {
                        ($0.valueID, finiteZero(shape: $0.shape))
                    }
                )
            )
        }

        let overflowGraph = try arithmeticGraph(
            id: "float32_constant_overflow",
            opcode: .multiply,
            lhs: .greatestFiniteMagnitude,
            rhs: 0
        )
        let lhsID = try CanonicalValueID("lhs")
        #expect(
            throws: MojoProgramCompilationError.constantNotRepresentable(
                graphID: overflowGraph.id,
                valueID: lhsID,
                constantIndex: 0,
                numericType: .float32
            )
        ) {
            _ = try KuyuMojoProgramCompiler(numericType: .float32).compile(
                overflowGraph,
                layouts: [],
                identity: graph.identity
            )
        }
    }

    private func arithmeticGraph(
        id: String,
        opcode: CanonicalOpcode,
        lhs: Double,
        rhs: Double
    ) throws -> CanonicalOperationGraph {
        let lhsID = try CanonicalValueID("lhs")
        let rhsID = try CanonicalValueID("rhs")
        let resultID = try CanonicalValueID("result")
        return try CanonicalOperationGraph(
            id: id,
            inputs: [],
            instructions: [
                CanonicalInstruction(
                    result: lhsID,
                    opcode: .constant,
                    constants: [lhs],
                    constantShape: .scalar,
                    constantUnit: .kilogram
                ),
                CanonicalInstruction(
                    result: rhsID,
                    opcode: .constant,
                    constants: [rhs],
                    constantShape: .scalar,
                    constantUnit: .dimensionless
                ),
                CanonicalInstruction(
                    result: resultID,
                    opcode: opcode,
                    operands: [lhsID, rhsID]
                ),
            ],
            outputs: [
                CanonicalGraphOutput(
                    id: "result",
                    value: resultID,
                    shape: .scalar,
                    unit: .kilogram
                ),
            ]
        )
    }

    private func expectSameGraphStructure(
        _ lhs: MojoCompiledGraph,
        _ rhs: MojoCompiledGraph
    ) {
        #expect(lhs.graphID == rhs.graphID)
        #expect(lhs.workspaceElementCount == rhs.workspaceElementCount)
        #expect(lhs.encodedPlan == rhs.encodedPlan)
        #expect(lhs.inputs == rhs.inputs)
        #expect(lhs.outputs == rhs.outputs)
    }

    private func finiteZero(shape: CanonicalValueShape) -> MojoCanonicalValue {
        if shape == .scalar { return .scalar(0) }
        if shape == .vector3 { return .vector3(.zero) }
        if shape == .quaternion { return .quaternion(SIMD4<Double>(0, 0, 0, 1)) }
        return .vector4(.zero)
    }

    private func nonFiniteValue(shape: CanonicalValueShape) -> MojoCanonicalValue {
        if shape == .scalar { return .scalar(.infinity) }
        if shape == .vector3 { return .vector3(SIMD3<Double>(.infinity, 0, 0)) }
        if shape == .quaternion {
            return .quaternion(SIMD4<Double>(.infinity, 0, 0, 1))
        }
        return .vector4(SIMD4<Double>(.infinity, 0, 0, 0))
    }

    private func finiteOverflowValue(
        shape: CanonicalValueShape
    ) -> MojoCanonicalValue {
        if shape == .scalar { return .scalar(.greatestFiniteMagnitude) }
        if shape == .vector3 {
            return .vector3(SIMD3<Double>(.greatestFiniteMagnitude, 0, 0))
        }
        if shape == .quaternion {
            return .quaternion(
                SIMD4<Double>(.greatestFiniteMagnitude, 0, 0, 0)
            )
        }
        return .vector4(SIMD4<Double>(.greatestFiniteMagnitude, 0, 0, 0))
    }
}
