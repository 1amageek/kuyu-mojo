import KuyuPhysics
import KuyuMojoCore

public struct KuyuMojoProgramCompiler: MojoDynamicsProgramCompiling, Sendable {
    public static let float32ExecutorVersion = "mojo-cpu-float32-ssa-v1"
    public static let float64ExecutorVersion = "mojo-cpu-float64-ssa-v2"

    static let float32PlanMagic = 4_937_049
    static let float64PlanMagic = 1_263_883_861
    static let planSchemaVersion = 1
    static let headerElementCount = 8
    static let instructionElementCount = 16
    static let maximumOperandCount = 3
    static let maximumConstantCount = 4

    public let numericType: MojoNumericType
    private let graphValidator: any CanonicalOperationGraphValidating

    public init(
        numericType: MojoNumericType = .float64,
        graphValidator: any CanonicalOperationGraphValidating = CanonicalOperationGraphValidator()
    ) {
        self.numericType = numericType
        self.graphValidator = graphValidator
    }

    public func compile(
        _ program: CanonicalDynamicsProgram
    ) throws -> MojoCompiledDynamicsProgram {
        let identity = try MojoCompiledProgramIdentity(
            programSchemaVersion: program.content.schemaVersion,
            programDigest: program.digest.rawValue,
            executorVersion: executorVersion,
            numericType: numericType,
            deviceClass: .cpu
        )
        var forceTerms: [CanonicalForceTermID: MojoCompiledGraph] = [:]
        var forceTermIDs: [CanonicalForceTermID] = []
        for term in program.content.forceTerms {
            guard forceTerms[term.id] == nil else {
                throw MojoProgramCompilationError.duplicateForceTerm(term.id)
            }
            forceTerms[term.id] = try compile(
                term.graph,
                layouts: program.content.layouts,
                identity: identity
            )
            forceTermIDs.append(term.id)
        }
        return MojoCompiledDynamicsProgram(
            identity: identity,
            forceTermIDs: forceTermIDs,
            forceTerms: forceTerms,
            derivative: try compile(
                program.content.derivativeGraph,
                layouts: program.content.layouts,
                identity: identity
            ),
            observables: try compile(
                program.content.observableGraph,
                layouts: program.content.layouts,
                identity: identity
            )
        )
    }

    func compile(
        _ graph: CanonicalOperationGraph,
        layouts: [CanonicalBufferLayout],
        identity: MojoCompiledProgramIdentity
    ) throws -> MojoCompiledGraph {
        let signatures = try graphValidator.signatures(
            for: graph,
            layouts: layouts
        )
        var bindings: [CanonicalValueID: MojoValueBinding] = [:]
        var nextOffset = 0
        var inputBindings: [MojoValueBinding] = []

        for input in graph.inputs {
            let binding = try allocate(
                input.id,
                graphID: graph.id,
                signatures: signatures,
                nextOffset: &nextOffset
            )
            bindings[input.id] = binding
            inputBindings.append(binding)
        }
        let inputElementCount = nextOffset

        let (instructionStorageCount, instructionStorageOverflow) =
            graph.instructions.count.multipliedReportingOverflow(
                by: Self.instructionElementCount
            )
        guard !instructionStorageOverflow else {
            throw MojoProgramCompilationError.valueTableOverflow(
                graphID: graph.id
            )
        }
        var records: [Double] = []
        records.reserveCapacity(instructionStorageCount)
        for instruction in graph.instructions {
            let result = try allocate(
                instruction.result,
                graphID: graph.id,
                signatures: signatures,
                nextOffset: &nextOffset
            )
            guard instruction.operands.count <= Self.maximumOperandCount else {
                throw MojoProgramCompilationError.tooManyOperands(
                    graphID: graph.id,
                    valueID: instruction.result,
                    count: instruction.operands.count
                )
            }
            guard instruction.constants.count <= Self.maximumConstantCount else {
                throw MojoProgramCompilationError.tooManyConstants(
                    graphID: graph.id,
                    valueID: instruction.result,
                    count: instruction.constants.count
                )
            }

            var record = [Double](
                repeating: 0,
                count: Self.instructionElementCount
            )
            record[0] = Double(MojoCanonicalOpcode(instruction.opcode).rawValue)
            record[1] = Double(result.offset)
            record[2] = Double(result.shape.elementCount)
            record[3] = Double(instruction.operands.count)
            for (index, operandID) in instruction.operands.enumerated() {
                guard let operand = bindings[operandID] else {
                    throw MojoProgramCompilationError.missingValueSignature(
                        graphID: graph.id,
                        valueID: operandID
                    )
                }
                record[4 + (index * 2)] = Double(operand.offset)
                record[5 + (index * 2)] = Double(operand.shape.elementCount)
            }
            record[10] = Double(instruction.componentIndex ?? -1)
            record[11] = Double(instruction.constants.count)
            for (index, constant) in instruction.constants.enumerated() {
                guard isRepresentable(constant) else {
                    throw MojoProgramCompilationError.constantNotRepresentable(
                        graphID: graph.id,
                        valueID: instruction.result,
                        constantIndex: index,
                        numericType: numericType
                    )
                }
                record[12 + index] = constant
            }
            records.append(contentsOf: record)
            bindings[instruction.result] = result
        }

        let (runtimeStart, runtimeStartOverflow) =
            Self.headerElementCount.addingReportingOverflow(
                instructionStorageCount
            )
        guard !runtimeStartOverflow,
              runtimeStart <= maximumExactInteger else {
            throw MojoProgramCompilationError.valueTableOverflow(
                graphID: graph.id
            )
        }

        let outputBindings = try graph.outputs.map { output in
            guard let binding = bindings[output.value] else {
                throw MojoProgramCompilationError.missingValueSignature(
                    graphID: graph.id,
                    valueID: output.value
                )
            }
            return MojoOutputBinding(
                outputID: output.id,
                offset: binding.offset,
                shape: binding.shape
            )
        }
        var encodedPlan = [
            Double(planMagic),
            Double(Self.planSchemaVersion),
            Double(graph.instructions.count),
            Double(nextOffset),
            Double(inputElementCount),
            Double(Self.instructionElementCount),
            Double(Self.headerElementCount),
            Double(runtimeStart),
        ]
        encodedPlan.append(contentsOf: records)

        return MojoCompiledGraph(
            identity: identity,
            graphID: graph.id,
            workspaceElementCount: nextOffset,
            encodedPlan: encodedPlan,
            inputs: inputBindings,
            outputs: outputBindings
        )
    }

    private func allocate(
        _ valueID: CanonicalValueID,
        graphID: String,
        signatures: [CanonicalValueID: CanonicalValueSignature],
        nextOffset: inout Int
    ) throws -> MojoValueBinding {
        guard let signature = signatures[valueID] else {
            throw MojoProgramCompilationError.missingValueSignature(
                graphID: graphID,
                valueID: valueID
            )
        }
        let shape = signature.shape
        guard shape == .scalar || shape == .vector3
                || shape == .vector4 || shape == .quaternion else {
            throw MojoProgramCompilationError.unsupportedShape(
                graphID: graphID,
                valueID: valueID,
                shape: shape
            )
        }
        let offset = nextOffset
        let (endOffset, overflowed) = nextOffset.addingReportingOverflow(
            shape.elementCount
        )
        guard !overflowed, endOffset <= maximumExactInteger else {
            throw MojoProgramCompilationError.valueTableOverflow(
                graphID: graphID
            )
        }
        nextOffset = endOffset
        return MojoValueBinding(
            valueID: valueID,
            offset: offset,
            shape: shape
        )
    }

    private var executorVersion: String {
        switch numericType {
        case .float32:
            Self.float32ExecutorVersion
        case .float64:
            Self.float64ExecutorVersion
        }
    }

    private var planMagic: Int {
        switch numericType {
        case .float32:
            Self.float32PlanMagic
        case .float64:
            Self.float64PlanMagic
        }
    }

    private var maximumExactInteger: Int {
        switch numericType {
        case .float32:
            16_777_216
        case .float64:
            9_007_199_254_740_991
        }
    }

    private func isRepresentable(_ value: Double) -> Bool {
        guard value.isFinite else {
            return false
        }
        switch numericType {
        case .float32:
            return Float(value).isFinite
        case .float64:
            return true
        }
    }
}
