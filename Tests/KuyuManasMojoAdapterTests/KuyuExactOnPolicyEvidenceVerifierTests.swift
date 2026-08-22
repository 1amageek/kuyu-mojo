import Foundation
import KuyuManasMojoAdapter
import KuyuTrainingContracts
import Testing

@Suite
struct KuyuExactOnPolicyEvidenceVerifierTests {
    @Test
    func acceptsSquashedGaussianJacobian() throws {
        let fixture = makeEvidenceFixture(sample: 0.2)

        try KuyuExactOnPolicyEvidenceVerifier().verify(
            fixture.behavior,
            action: [fixture.action],
            actionSpace: actionSpace()
        )
    }

    @Test
    func acceptsNumericallyStableSaturatedTanhEvidence() throws {
        let fixture = makeEvidenceFixture(sample: 40, logStandardDeviation: 4)

        try KuyuExactOnPolicyEvidenceVerifier().verify(
            fixture.behavior,
            action: [fixture.action],
            actionSpace: actionSpace()
        )
    }

    @Test
    func acceptsIdentityGaussianEvidence() throws {
        let sample = 0.2
        let behavior = makeBehavior(
            kind: .identityGaussian,
            sample: sample,
            transformedMean: 0,
            transformedAction: sample,
            logJacobian: 0
        )

        try KuyuExactOnPolicyEvidenceVerifier().verify(
            behavior,
            action: [sample],
            actionSpace: identityActionSpace()
        )
    }

    @Test
    func acceptsAffineSigmoidGaussianEvidence() throws {
        let sample = 0.2
        let lower = -2.0
        let upper = 3.0
        let sigmoid = stableSigmoid(sample)
        let action = lower + sigmoid * (upper - lower)
        let transformedMean = lower + 0.5 * (upper - lower)
        let logJacobian = log(upper - lower) - softplus(-sample) - softplus(sample)
        let behavior = makeBehavior(
            kind: .affineSigmoidGaussian,
            sample: sample,
            transformedMean: transformedMean,
            transformedAction: action,
            logJacobian: logJacobian
        )

        try KuyuExactOnPolicyEvidenceVerifier().verify(
            behavior,
            action: [action],
            actionSpace: sigmoidActionSpace(lower: lower, upper: upper)
        )
    }

    @Test
    func rejectsFabricatedLogProbability() throws {
        let fixture = makeEvidenceFixture(sample: 0.2, logProbability: 0)

        #expect(throws: KuyuExactOnPolicyEvidenceVerifier.VerificationError.self) {
            try KuyuExactOnPolicyEvidenceVerifier().verify(
                fixture.behavior,
                action: [fixture.action],
                actionSpace: actionSpace()
            )
        }
    }

    @Test
    func rejectsInvalidToleranceInsteadOfClampingIt() throws {
        #expect(throws: KuyuExactOnPolicyEvidenceVerifier.VerificationError.invalidTolerance(0)) {
            _ = try KuyuExactOnPolicyEvidenceVerifier(tolerance: 0)
        }
    }

    @Test
    func rejectsUnsupportedDistributionVersion() throws {
        let fixture = makeEvidenceFixture(sample: 0.2)
        let behavior = behavior(
            basedOn: fixture.behavior,
            distributionVersion: KuyuBehaviorPolicyEvidence.currentDistributionVersion + 1
        )

        #expect(throws: KuyuExactOnPolicyEvidenceVerifier.VerificationError
            .unsupportedDistributionVersion(KuyuBehaviorPolicyEvidence.currentDistributionVersion + 1)) {
            try KuyuExactOnPolicyEvidenceVerifier().verify(
                behavior,
                action: [fixture.action],
                actionSpace: actionSpace()
            )
        }
    }

    @Test
    func rejectsDistributionSpaceMismatch() throws {
        let fixture = makeEvidenceFixture(sample: 0.2)

        #expect(throws: KuyuExactOnPolicyEvidenceVerifier.VerificationError
            .distributionSpaceMismatch(index: 0)) {
            try KuyuExactOnPolicyEvidenceVerifier().verify(
                fixture.behavior,
                action: [fixture.action],
                actionSpace: identityActionSpace()
            )
        }
    }

    @Test
    func rejectsNonFiniteDistributionEvidence() throws {
        let fixture = makeEvidenceFixture(sample: 0.2)
        let behavior = behavior(
            basedOn: fixture.behavior,
            transformedMean: [.infinity]
        )

        #expect(throws: KuyuExactOnPolicyEvidenceVerifier.VerificationError
            .nonFiniteDistributionValue(index: 0)) {
            try KuyuExactOnPolicyEvidenceVerifier().verify(
                behavior,
                action: [fixture.action],
                actionSpace: actionSpace()
            )
        }
    }
}

private func makeEvidenceFixture(
    sample: Double,
    logStandardDeviation: Double = -0.5,
    logProbability suppliedLogProbability: Double? = nil
) -> (behavior: KuyuBehaviorPolicyEvidence, action: Double) {
    let mean = 0.0
    let action = tanh(sample)
    let standardDeviation = exp(logStandardDeviation)
    let baseLogProbability = -0.5 * pow((sample - mean) / standardDeviation, 2)
        - logStandardDeviation
        - 0.5 * log(2 * Double.pi)
    let logTanhDerivative = 2 * (log(2) - sample - softplus(-2 * sample))
    let behavior = KuyuBehaviorPolicyEvidence(
        policyID: "policy",
        checkpointDigest: String(repeating: "a", count: 64),
        distributionKinds: [.affineTanhGaussian],
        distributionVersion: KuyuBehaviorPolicyEvidence.currentDistributionVersion,
        distributionContractDigest: String(repeating: "b", count: 64),
        baseMean: [mean],
        transformedMean: [tanh(mean)],
        baseLogStandardDeviation: [logStandardDeviation],
        preTransformSample: [sample],
        transformedAction: [action],
        logProbability: suppliedLogProbability ?? baseLogProbability - logTanhDerivative
    )
    return (behavior, action)
}

private func actionSpace() -> KuyuDatasetDescriptor.Space {
    KuyuDatasetDescriptor.Space(
        id: "action",
        version: "1",
        digest: String(repeating: "c", count: 64),
        channels: [KuyuDatasetDescriptor.Channel(
            index: 0,
            id: "action.0",
            unit: "normalized",
            lowerBound: -1,
            upperBound: 1,
            transform: .affineTanh
        )]
    )
}

private func identityActionSpace() -> KuyuDatasetDescriptor.Space {
    KuyuDatasetDescriptor.Space(
        id: "action",
        version: "1",
        digest: String(repeating: "c", count: 64),
        channels: [KuyuDatasetDescriptor.Channel(
            index: 0,
            id: "action.0",
            unit: "normalized"
        )]
    )
}

private func sigmoidActionSpace(lower: Double, upper: Double) -> KuyuDatasetDescriptor.Space {
    KuyuDatasetDescriptor.Space(
        id: "action",
        version: "1",
        digest: String(repeating: "c", count: 64),
        channels: [KuyuDatasetDescriptor.Channel(
            index: 0,
            id: "action.0",
            unit: "normalized",
            lowerBound: lower,
            upperBound: upper,
            transform: .affineSigmoid
        )]
    )
}

private func makeBehavior(
    kind: KuyuBehaviorPolicyEvidence.DistributionKind,
    sample: Double,
    transformedMean: Double,
    transformedAction: Double,
    logJacobian: Double
) -> KuyuBehaviorPolicyEvidence {
    let logStandardDeviation = -0.5
    let baseLogProbability = -0.5 * pow(sample / exp(logStandardDeviation), 2)
        - logStandardDeviation
        - 0.5 * log(2 * Double.pi)
    return KuyuBehaviorPolicyEvidence(
        policyID: "policy",
        checkpointDigest: String(repeating: "a", count: 64),
        distributionKinds: [kind],
        distributionVersion: KuyuBehaviorPolicyEvidence.currentDistributionVersion,
        distributionContractDigest: String(repeating: "b", count: 64),
        baseMean: [0],
        transformedMean: [transformedMean],
        baseLogStandardDeviation: [logStandardDeviation],
        preTransformSample: [sample],
        transformedAction: [transformedAction],
        logProbability: baseLogProbability - logJacobian
    )
}

private func stableSigmoid(_ value: Double) -> Double {
    value >= 0
        ? 1 / (1 + exp(-value))
        : exp(value) / (1 + exp(value))
}

private func behavior(
    basedOn source: KuyuBehaviorPolicyEvidence,
    distributionVersion: Int? = nil,
    transformedMean: [Double]? = nil
) -> KuyuBehaviorPolicyEvidence {
    KuyuBehaviorPolicyEvidence(
        policyID: source.policyID,
        checkpointDigest: source.checkpointDigest,
        distributionKinds: source.distributionKinds,
        distributionVersion: distributionVersion ?? source.distributionVersion,
        distributionContractDigest: source.distributionContractDigest,
        baseMean: source.baseMean,
        transformedMean: transformedMean ?? source.transformedMean,
        baseLogStandardDeviation: source.baseLogStandardDeviation,
        preTransformSample: source.preTransformSample,
        transformedAction: source.transformedAction,
        logProbability: source.logProbability,
        rewardValue: source.rewardValue,
        costValue: source.costValue,
        inputRecurrentStateDigest: source.inputRecurrentStateDigest,
        outputRecurrentStateDigest: source.outputRecurrentStateDigest
    )
}

private func softplus(_ value: Double) -> Double {
    max(value, 0) + log1p(exp(-abs(value)))
}
