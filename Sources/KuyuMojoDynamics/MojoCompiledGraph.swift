import KuyuPhysics
import KuyuMojoCore

struct MojoValueBinding: Sendable, Equatable {
    let valueID: CanonicalValueID
    let offset: Int
    let shape: CanonicalValueShape
}

struct MojoOutputBinding: Sendable, Equatable {
    let outputID: String
    let offset: Int
    let shape: CanonicalValueShape
}

public struct MojoCompiledGraph: Sendable, Equatable {
    public let identity: MojoCompiledProgramIdentity
    public let graphID: String
    public let workspaceElementCount: Int

    let encodedPlan: [Double]
    let inputs: [MojoValueBinding]
    let outputs: [MojoOutputBinding]

    init(
        identity: MojoCompiledProgramIdentity,
        graphID: String,
        workspaceElementCount: Int,
        encodedPlan: [Double],
        inputs: [MojoValueBinding],
        outputs: [MojoOutputBinding]
    ) {
        self.identity = identity
        self.graphID = graphID
        self.workspaceElementCount = workspaceElementCount
        self.encodedPlan = encodedPlan
        self.inputs = inputs
        self.outputs = outputs
    }
}
