import KuyuMojoCore
import KuyuPhysics
import Mojo

public struct MojoFloat64GraphExecutor: MojoGraphExecuting, Sendable {
    public let numericType = MojoNumericType.float64

    public init() {}

    public func execute(
        _ graph: MojoCompiledGraph,
        inputs: [CanonicalValueID: MojoCanonicalValue]
    ) throws -> [String: MojoCanonicalValue] {
        try MojoGraphExecutionSupport.validate(
            graph,
            executorNumericType: numericType
        )
        let orderedInputs = try MojoGraphExecutionSupport.inputs(
            for: graph,
            from: inputs
        )
        var payload = graph.encodedPlan
        payload.reserveCapacity(
            graph.encodedPlan.count
                + graph.inputs.reduce(0) { $0 + $1.shape.elementCount }
        )
        for (_, value) in orderedInputs {
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
        return try MojoGraphExecutionSupport.outputs(
            for: graph,
            workspace: workspace
        )
    }
}
