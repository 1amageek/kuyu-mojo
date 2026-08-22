import KuyuManasMojoAdapter
import Testing

@Suite
struct KuyuDirectLearningInputEncoderTests {
    @Test
    func preservesDeclaredDirectCoordinates() throws {
        let encoder = try KuyuDirectLearningInputEncoder(
            actorInputContractDigest: String(repeating: "a", count: 64),
            criticInputContractDigest: String(repeating: "b", count: 64)
        )

        #expect(try encoder.actorInput(observation: [1, 2], stateFacts: [3]) == [1, 2])
        #expect(try encoder.criticInput(observation: [1, 2], stateFacts: [3]) == [1, 2, 3])
    }

    @Test
    func rejectsPlaceholderContractDigests() throws {
        #expect(throws: KuyuDirectLearningInputEncoder.ConfigurationError
            .invalidDigest(field: "actorInputContractDigest", value: "placeholder")) {
            _ = try KuyuDirectLearningInputEncoder(
                actorInputContractDigest: "placeholder",
                criticInputContractDigest: String(repeating: "b", count: 64)
            )
        }
    }

    @Test
    func rejectsLossyFloatConversion() throws {
        let encoder = try KuyuDirectLearningInputEncoder(
            actorInputContractDigest: String(repeating: "a", count: 64),
            criticInputContractDigest: String(repeating: "b", count: 64)
        )

        #expect(throws: KuyuDirectLearningInputEncoder.EncodingError
            .nonFiniteFloatConversion(field: "observation", index: 0)) {
            _ = try encoder.actorInput(
                observation: [Double.greatestFiniteMagnitude],
                stateFacts: []
            )
        }
    }
}
