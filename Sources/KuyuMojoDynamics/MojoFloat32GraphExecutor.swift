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
        let invocation = try MojoFloat32GraphInvocation(
            graph: graph,
            inputs: inputs
        )
        var payload = invocation.plan
        payload.append(contentsOf: invocation.runtimeInput)

        var workspace = [Float](
            repeating: 0,
            count: invocation.workspaceElementCount
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
