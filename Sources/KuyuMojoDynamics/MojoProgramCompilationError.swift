import KuyuPhysics

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
    case valueTableOverflow(graphID: String)
}
