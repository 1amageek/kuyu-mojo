import KuyuPhysics

public protocol MojoDynamicsProgramCompiling: Sendable {
    func compile(
        _ program: CanonicalDynamicsProgram
    ) throws -> MojoCompiledDynamicsProgram
}
