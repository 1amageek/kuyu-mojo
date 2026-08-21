import KuyuPhysics
import Mojo

public struct MojoScalarGraphExecutor: MojoFloat64GraphExecuting, Sendable {
    public init() {}

    public func execute(
        _ graph: MojoCompiledGraph,
        inputs: [CanonicalValueID: MojoFloat64Value]
    ) throws -> [String: MojoFloat64Value] {
        let requiredInputIDs = Set(graph.inputs.map(\.valueID))
        if let unexpected = inputs.keys
            .filter({ !requiredInputIDs.contains($0) })
            .sorted(by: { $0.rawValue < $1.rawValue })
            .first {
            throw MojoProgramExecutionError.unexpectedInput(unexpected)
        }

        var payload = graph.encodedPlan
        payload.reserveCapacity(
            graph.encodedPlan.count
                + graph.inputs.reduce(0) { $0 + $1.shape.elementCount }
        )
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
            value.append(to: &payload)
        }

        var workspace = [Double](
            repeating: 0,
            count: graph.workspaceElementCount
        )
        do {
            try executeCanonicalGraph(payload, into: &workspace)
        } catch MojoInvocationError.invocationFailed(_, let status) {
            throw MojoProgramExecutionError.backendFailure(status: status)
        } catch let error as MojoInvocationError {
            throw MojoProgramExecutionError.bridgeFailure(error)
        }

        var result: [String: MojoFloat64Value] = [:]
        for output in graph.outputs {
            let (endOffset, overflowed) = output.offset.addingReportingOverflow(
                output.shape.elementCount
            )
            guard !overflowed, output.offset >= 0,
                  endOffset <= workspace.count,
                  let value = MojoFloat64Value.value(
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
