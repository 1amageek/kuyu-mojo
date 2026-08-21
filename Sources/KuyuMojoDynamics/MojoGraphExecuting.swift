import KuyuMojoCore
import KuyuPhysics

public protocol MojoGraphExecuting: Sendable {
    var numericType: MojoNumericType { get }

    func execute(
        _ graph: MojoCompiledGraph,
        inputs: [CanonicalValueID: MojoCanonicalValue]
    ) throws -> [String: MojoCanonicalValue]
}
