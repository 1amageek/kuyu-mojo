import KuyuPhysics
import KuyuMojoCore

public enum MojoProgramCompilationError: Error, Equatable {
    case duplicateForceTerm(CanonicalForceTermID)
    case missingValueSignature(graphID: String, valueID: CanonicalValueID)
    case unsupportedShape(
        graphID: String,
        valueID: CanonicalValueID,
        shape: CanonicalValueShape
    )
    case tooManyOperands(graphID: String, valueID: CanonicalValueID, count: Int)
    case tooManyConstants(graphID: String, valueID: CanonicalValueID, count: Int)
    case constantNotRepresentable(
        graphID: String,
        valueID: CanonicalValueID,
        constantIndex: Int,
        numericType: MojoNumericType
    )
    case valueTableOverflow(graphID: String)
}
