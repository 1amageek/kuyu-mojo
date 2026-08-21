public struct MojoParityTolerance: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case invalidAbsolute(Double)
        case invalidRelative(Double)
    }

    public let absolute: Double
    public let relative: Double

    public init(absolute: Double, relative: Double) throws {
        guard absolute.isFinite, absolute >= 0 else {
            throw ValidationError.invalidAbsolute(absolute)
        }
        guard relative.isFinite, relative >= 0 else {
            throw ValidationError.invalidRelative(relative)
        }
        self.absolute = absolute
        self.relative = relative
    }

    public func accepts(candidate: Double, reference: Double) -> Bool {
        guard candidate.isFinite, reference.isFinite else {
            return false
        }
        return abs(candidate - reference)
            <= absolute + relative * abs(reference)
    }

    init(uncheckedAbsolute absolute: Double, relative: Double) {
        self.absolute = absolute
        self.relative = relative
    }
}
