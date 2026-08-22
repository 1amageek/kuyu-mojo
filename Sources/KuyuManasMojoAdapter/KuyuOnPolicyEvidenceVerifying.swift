import KuyuTrainingContracts

public protocol KuyuOnPolicyEvidenceVerifying: Sendable {
    func verify(
        _ behavior: KuyuBehaviorPolicyEvidence,
        action: [Double],
        actionSpace: KuyuDatasetDescriptor.Space
    ) throws
}
