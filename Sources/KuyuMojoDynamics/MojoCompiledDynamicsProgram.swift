import KuyuPhysics
import KuyuMojoCore

public struct MojoCompiledDynamicsProgram: Sendable, Equatable {
    public let identity: MojoCompiledProgramIdentity
    public let forceTermIDs: [CanonicalForceTermID]
    public let derivative: MojoCompiledGraph
    public let observables: MojoCompiledGraph

    let forceTerms: [CanonicalForceTermID: MojoCompiledGraph]

    init(
        identity: MojoCompiledProgramIdentity,
        forceTermIDs: [CanonicalForceTermID],
        forceTerms: [CanonicalForceTermID: MojoCompiledGraph],
        derivative: MojoCompiledGraph,
        observables: MojoCompiledGraph
    ) {
        self.identity = identity
        self.forceTermIDs = forceTermIDs
        self.forceTerms = forceTerms
        self.derivative = derivative
        self.observables = observables
    }
}
