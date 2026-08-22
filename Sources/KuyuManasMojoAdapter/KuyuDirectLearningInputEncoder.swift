import ManasLearningContracts

/// Encodes a dataset whose observation and critic-state spaces already use the
/// policy feature coordinates identified by the supplied contract digests.
public struct KuyuDirectLearningInputEncoder: ManasLearningInputEncoding {
    public enum ConfigurationError: Error, Sendable, Equatable {
        case invalidDigest(field: String, value: String)
    }

    public enum EncodingError: Error, Sendable, Equatable {
        case inputSizeOverflow
        case nonFiniteFloatConversion(field: String, index: Int)
    }

    public let actorInputContractDigest: String
    public let criticInputContractDigest: String

    public init(
        actorInputContractDigest: String,
        criticInputContractDigest: String
    ) throws {
        try Self.validateDigest(actorInputContractDigest, field: "actorInputContractDigest")
        try Self.validateDigest(criticInputContractDigest, field: "criticInputContractDigest")
        self.actorInputContractDigest = actorInputContractDigest
        self.criticInputContractDigest = criticInputContractDigest
    }

    public func actorInput(observation: [Double], stateFacts: [Double]) throws -> [Float] {
        try floats(observation, field: "observation")
    }

    public func criticInput(observation: [Double], stateFacts: [Double]) throws -> [Float] {
        guard observation.count <= Int.max - stateFacts.count else {
            throw EncodingError.inputSizeOverflow
        }
        var result: [Float] = []
        result.reserveCapacity(observation.count + stateFacts.count)
        try append(observation, field: "observation", to: &result)
        try append(stateFacts, field: "stateFacts", to: &result)
        return result
    }

    private func floats(_ values: [Double], field: String) throws -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(values.count)
        try append(values, field: field, to: &result)
        return result
    }

    private func append(
        _ values: [Double],
        field: String,
        to result: inout [Float]
    ) throws {
        for (index, value) in values.enumerated() {
            let converted = Float(value)
            guard value.isFinite, converted.isFinite else {
                throw EncodingError.nonFiniteFloatConversion(field: field, index: index)
            }
            result.append(converted)
        }
    }

    private static func validateDigest(_ value: String, field: String) throws {
        let isDigest = value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
        guard isDigest else {
            throw ConfigurationError.invalidDigest(field: field, value: value)
        }
    }
}
