public enum ReferenceQuadrotorMojoParityContract {
    public static let generalizedForce = MojoParityTolerance(
        uncheckedAbsolute: 1e-12,
        relative: 1e-12
    )
    public static let derivative = MojoParityTolerance(
        uncheckedAbsolute: 1e-12,
        relative: 1e-12
    )
    public static let observables = MojoParityTolerance(
        uncheckedAbsolute: 1e-12,
        relative: 1e-12
    )
    public static let integratedState = MojoParityTolerance(
        uncheckedAbsolute: 1e-11,
        relative: 1e-11
    )
    public static let zeroBoundary = MojoParityTolerance(
        uncheckedAbsolute: 1e-12,
        relative: 0
    )
}
