import KuyuPhysics
@testable import KuyuMojoDynamics
import Testing

@Suite("Mojo canonical program compiler")
struct MojoProgramCompilerTests {
    @Test(.timeLimit(.minutes(1)))
    func compilesReferenceProgramIntoStableCPUFloat64Plans() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let compiler = KuyuMojoProgramCompiler()

        let first = try compiler.compile(program)
        let second = try compiler.compile(program)

        #expect(first == second)
        #expect(first.identity.programDigest == program.digest.rawValue)
        #expect(
            first.identity.programSchemaVersion
                == CanonicalDynamicsProgram.currentSchemaVersion
        )
        #expect(first.identity.executorVersion == "mojo-cpu-float64-ssa-v1")
        #expect(first.identity.numericType == .float64)
        #expect(first.identity.deviceClass == .cpu)
        #expect(first.forceTermIDs.count == 9)
        #expect(first.derivative.workspaceElementCount > 0)
        #expect(first.observables.workspaceElementCount > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func graphExecutorRejectsMissingShapeAndNonFiniteInputs() throws {
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let graph = try KuyuMojoProgramCompiler()
            .compile(program)
            .derivative
        let firstInput = try #require(graph.inputs.first)
        let executor = MojoScalarGraphExecutor()

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
            var values: [CanonicalValueID: MojoFloat64Value] = [:]
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
        let executor = MojoScalarGraphExecutor()

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

    private func finiteZero(shape: CanonicalValueShape) -> MojoFloat64Value {
        if shape == .scalar { return .scalar(0) }
        if shape == .vector3 { return .vector3(.zero) }
        if shape == .quaternion { return .quaternion(SIMD4<Double>(0, 0, 0, 1)) }
        return .vector4(.zero)
    }

    private func nonFiniteValue(shape: CanonicalValueShape) -> MojoFloat64Value {
        if shape == .scalar { return .scalar(.infinity) }
        if shape == .vector3 { return .vector3(SIMD3<Double>(.infinity, 0, 0)) }
        if shape == .quaternion {
            return .quaternion(SIMD4<Double>(.infinity, 0, 0, 1))
        }
        return .vector4(SIMD4<Double>(.infinity, 0, 0, 0))
    }
}
