import KuyuMojoCore

public enum ReferenceQuadrotorMojoParityContract {
    public static func tolerances(
        for numericType: MojoNumericType
    ) -> MojoDynamicsParityTolerances {
        switch numericType {
        case .float32:
            MojoDynamicsParityTolerances(
                generalizedForce: MojoParityTolerance(
                    uncheckedAbsolute: 5e-6,
                    relative: 5e-6
                ),
                derivative: MojoParityTolerance(
                    uncheckedAbsolute: 1e-5,
                    relative: 5e-6
                ),
                observables: MojoParityTolerance(
                    uncheckedAbsolute: 5e-6,
                    relative: 5e-6
                ),
                integratedState: MojoParityTolerance(
                    uncheckedAbsolute: 1e-6,
                    relative: 1e-5
                ),
                zeroBoundary: MojoParityTolerance(
                    uncheckedAbsolute: 2e-6,
                    relative: 0
                )
            )
        case .float64:
            MojoDynamicsParityTolerances(
                generalizedForce: MojoParityTolerance(
                    uncheckedAbsolute: 1e-12,
                    relative: 1e-12
                ),
                derivative: MojoParityTolerance(
                    uncheckedAbsolute: 1e-12,
                    relative: 1e-12
                ),
                observables: MojoParityTolerance(
                    uncheckedAbsolute: 1e-12,
                    relative: 1e-12
                ),
                integratedState: MojoParityTolerance(
                    uncheckedAbsolute: 1e-11,
                    relative: 1e-11
                ),
                zeroBoundary: MojoParityTolerance(
                    uncheckedAbsolute: 1e-12,
                    relative: 0
                )
            )
        }
    }
}
