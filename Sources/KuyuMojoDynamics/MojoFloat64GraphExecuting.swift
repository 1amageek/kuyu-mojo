import KuyuPhysics

public protocol MojoFloat64GraphExecuting: Sendable {
    func execute(
        _ graph: MojoCompiledGraph,
        inputs: [CanonicalValueID: MojoFloat64Value]
    ) throws -> [String: MojoFloat64Value]
}
