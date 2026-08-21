import KuyuMojoCore
import KuyuPhysics
import Mojo

public struct MojoFloat32GraphExecutor: MojoGraphExecuting, Sendable {
    public let numericType = MojoNumericType.float32

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
        var payload: [Float] = []
        payload.reserveCapacity(
            graph.encodedPlan.count
                + graph.inputs.reduce(0) { $0 + $1.shape.elementCount }
        )
        for element in graph.encodedPlan {
            let converted = Float(element)
            guard converted.isFinite else {
                throw MojoProgramExecutionError.planNotRepresentable(
                    graphID: graph.graphID,
                    numericType: numericType
                )
            }
            payload.append(converted)
        }
        for (binding, value) in orderedInputs {
            guard value.appendFloat32(to: &payload) else {
                throw MojoProgramExecutionError.inputNotRepresentable(
                    valueID: binding.valueID,
                    numericType: numericType
                )
            }
        }

        var workspace = [Float](
            repeating: 0,
            count: graph.workspaceElementCount
        )
        do {
            try executeCanonicalGraphFloat32(payload, into: &workspace)
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
