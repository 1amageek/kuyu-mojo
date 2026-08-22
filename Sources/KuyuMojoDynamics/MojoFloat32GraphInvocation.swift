import KuyuMojoCore
import KuyuPhysics

struct MojoFloat32GraphInvocation: Sendable, Equatable {
    let plan: [Float]
    let runtimeInput: [Float]
    let workspaceElementCount: Int

    init(
        graph: MojoCompiledGraph,
        inputs: [CanonicalValueID: MojoCanonicalValue]
    ) throws {
        try MojoGraphExecutionSupport.validate(
            graph,
            executorNumericType: .float32
        )
        let orderedInputs = try MojoGraphExecutionSupport.inputs(
            for: graph,
            from: inputs
        )

        var plan: [Float] = []
        plan.reserveCapacity(graph.encodedPlan.count)
        for element in graph.encodedPlan {
            let converted = Float(element)
            guard converted.isFinite else {
                throw MojoProgramExecutionError.planNotRepresentable(
                    graphID: graph.graphID,
                    numericType: .float32
                )
            }
            plan.append(converted)
        }

        var runtimeInput: [Float] = []
        runtimeInput.reserveCapacity(
            graph.inputs.reduce(0) { $0 + $1.shape.elementCount }
        )
        for (binding, value) in orderedInputs {
            guard value.appendFloat32(to: &runtimeInput) else {
                throw MojoProgramExecutionError.inputNotRepresentable(
                    valueID: binding.valueID,
                    numericType: .float32
                )
            }
        }
        guard let encodedPlanCount = Float(exactly: plan.count),
            let encodedRuntimeInputCount = Float(
                exactly: runtimeInput.count
            ),
            plan.count >= KuyuMojoProgramCompiler.headerElementCount,
            plan[7] == encodedPlanCount,
            plan[4] == encodedRuntimeInputCount
        else {
            throw MojoProgramExecutionError.invalidPlanLayout(
                graphID: graph.graphID
            )
        }
        self.plan = plan
        self.runtimeInput = runtimeInput
        self.workspaceElementCount = graph.workspaceElementCount
    }
}
