import KuyuPhysics
import KuyuMojoCore

public struct MojoDynamicsExecutionIdentity: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case invalidFidelityID(String)
        case nonFiniteMixer
        case invalidRotorSpinConvention
    }

    public let compiledProgram: MojoCompiledProgramIdentity
    public let fidelityID: String
    public let constraintProjection: CanonicalConstraintProjectionKind
    public let controlSemantics: CanonicalControlSemantics
    public let mixerLayout: ReferenceQuadrotorMixer.Layout
    public let mixerArmLength: Double
    public let mixerYawCoefficient: Double
    public let rotorSpinDirections: [Double]

    public init(
        compiledProgram: MojoCompiledProgramIdentity,
        fidelityID: String,
        constraintProjection: CanonicalConstraintProjectionKind,
        controlSemantics: CanonicalControlSemantics,
        mixerLayout: ReferenceQuadrotorMixer.Layout,
        mixerArmLength: Double,
        mixerYawCoefficient: Double,
        rotorSpinDirections: [Double]
    ) throws {
        guard !fidelityID.isEmpty else {
            throw ValidationError.invalidFidelityID(fidelityID)
        }
        guard mixerArmLength.isFinite, mixerYawCoefficient.isFinite else {
            throw ValidationError.nonFiniteMixer
        }
        guard rotorSpinDirections.count == 4,
              rotorSpinDirections.allSatisfy(\.isFinite) else {
            throw ValidationError.invalidRotorSpinConvention
        }
        self.compiledProgram = compiledProgram
        self.fidelityID = fidelityID
        self.constraintProjection = constraintProjection
        self.controlSemantics = controlSemantics
        self.mixerLayout = mixerLayout
        self.mixerArmLength = mixerArmLength
        self.mixerYawCoefficient = mixerYawCoefficient
        self.rotorSpinDirections = rotorSpinDirections
    }
}
