import ManasLearningContracts

public struct KuyuManasMojoTrainingResult: Sendable, Equatable {
  public let sourceIdentity: ManasLearningSourceIdentity
  public let transitionCount: Int
  public let metrics: ManasPPOTrainingMetrics
  public let checkpoint: ManasPPOTrainingCheckpoint

  public init(
    sourceIdentity: ManasLearningSourceIdentity,
    transitionCount: Int,
    metrics: ManasPPOTrainingMetrics,
    checkpoint: ManasPPOTrainingCheckpoint
  ) {
    self.sourceIdentity = sourceIdentity
    self.transitionCount = transitionCount
    self.metrics = metrics
    self.checkpoint = checkpoint
  }
}
