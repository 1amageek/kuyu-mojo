import KuyuPhysics
import KuyuMojoCore
import Mojo

public enum MojoProgramExecutionError: Error, Equatable {
    case programDigestMismatch(
        expected: CanonicalProgramDigest,
        actual: CanonicalProgramDigest
    )
    case missingInput(CanonicalValueID)
    case unexpectedInput(CanonicalValueID)
    case inputShapeMismatch(
        valueID: CanonicalValueID,
        expected: CanonicalValueShape,
        actual: CanonicalValueShape
    )
    case nonFiniteInput(CanonicalValueID)
    case inputNotRepresentable(
        valueID: CanonicalValueID,
        numericType: MojoNumericType
    )
    case planNotRepresentable(graphID: String, numericType: MojoNumericType)
    case invalidPlanLayout(graphID: String)
    case numericTypeMismatch(
        expected: MojoNumericType,
        actual: MojoNumericType
    )
    case backendFailure(status: Int32)
    case bridgeFailure(MojoInvocationError)
    case invalidBackendOutput(graphID: String, outputID: String)
    case nonFiniteOutput(graphID: String, outputID: String)
    case unknownForceTerm(QuadrotorForceTermID)
    case compiledForceTermMissing(CanonicalForceTermID)
    case fidelityNotDeclared(activeTermIDs: [String], projection: String)
}
