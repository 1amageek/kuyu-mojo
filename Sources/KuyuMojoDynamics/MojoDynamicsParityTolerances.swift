public struct MojoDynamicsParityTolerances: Sendable, Equatable {
    public let generalizedForce: MojoParityTolerance
    public let derivative: MojoParityTolerance
    public let observables: MojoParityTolerance
    public let integratedState: MojoParityTolerance
    public let zeroBoundary: MojoParityTolerance

    public init(
        generalizedForce: MojoParityTolerance,
        derivative: MojoParityTolerance,
        observables: MojoParityTolerance,
        integratedState: MojoParityTolerance,
        zeroBoundary: MojoParityTolerance
    ) {
        self.generalizedForce = generalizedForce
        self.derivative = derivative
        self.observables = observables
        self.integratedState = integratedState
        self.zeroBoundary = zeroBoundary
    }
}
