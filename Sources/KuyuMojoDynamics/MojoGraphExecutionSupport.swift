import KuyuMojoCore
import KuyuPhysics

enum MojoGraphExecutionSupport {
    static func validate(
        _ graph: MojoCompiledGraph,
        executorNumericType: MojoNumericType
    ) throws {
        guard graph.identity.numericType == executorNumericType else {
            throw MojoProgramExecutionError.numericTypeMismatch(
                expected: graph.identity.numericType,
                actual: executorNumericType
            )
        }
    }

    static func inputs(
        for graph: MojoCompiledGraph,
        from inputs: [CanonicalValueID: MojoCanonicalValue]
    ) throws -> [(MojoValueBinding, MojoCanonicalValue)] {
        let requiredInputIDs = Set(graph.inputs.map(\.valueID))
        if let unexpected = inputs.keys
            .filter({ !requiredInputIDs.contains($0) })
            .sorted(by: { $0.rawValue < $1.rawValue })
            .first {
            throw MojoProgramExecutionError.unexpectedInput(unexpected)
        }

        var ordered: [(MojoValueBinding, MojoCanonicalValue)] = []
        ordered.reserveCapacity(graph.inputs.count)
        for binding in graph.inputs {
            guard let value = inputs[binding.valueID] else {
                throw MojoProgramExecutionError.missingInput(binding.valueID)
            }
            guard value.shape == binding.shape else {
                throw MojoProgramExecutionError.inputShapeMismatch(
                    valueID: binding.valueID,
                    expected: binding.shape,
                    actual: value.shape
                )
            }
            guard value.isFinite else {
                throw MojoProgramExecutionError.nonFiniteInput(binding.valueID)
            }
            ordered.append((binding, value))
        }
        return ordered
    }

    static func outputs<Element: BinaryFloatingPoint>(
        for graph: MojoCompiledGraph,
        workspace: [Element]
    ) throws -> [String: MojoCanonicalValue] {
        var result: [String: MojoCanonicalValue] = [:]
        result.reserveCapacity(graph.outputs.count)
        for output in graph.outputs {
            let (endOffset, overflowed) = output.offset.addingReportingOverflow(
                output.shape.elementCount
            )
            guard !overflowed, output.offset >= 0,
                  endOffset <= workspace.count,
                  let value = MojoCanonicalValue.value(
                      shape: output.shape,
                      elements: workspace[output.offset..<endOffset]
                  ) else {
                throw MojoProgramExecutionError.invalidBackendOutput(
                    graphID: graph.graphID,
                    outputID: output.outputID
                )
            }
            guard value.isFinite else {
                throw MojoProgramExecutionError.nonFiniteOutput(
                    graphID: graph.graphID,
                    outputID: output.outputID
                )
            }
            result[output.outputID] = value
        }
        return result
    }
}
