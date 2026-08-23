import KuyuTrainingContracts
import ManasLearningContracts

public struct KuyuMojoTrainingResult: Sendable, Equatable {
  public let runID: TrainingRunID
  public let sourceIdentity: ManasLearningSourceIdentity
  public let transitionCount: Int
  public let metrics: ManasPPOTrainingMetrics
  public let candidate: ModelBundleReference

  public init(
    runID: TrainingRunID,
    sourceIdentity: ManasLearningSourceIdentity,
    transitionCount: Int,
    metrics: ManasPPOTrainingMetrics,
    candidate: ModelBundleReference
  ) {
    self.runID = runID
    self.sourceIdentity = sourceIdentity
    self.transitionCount = transitionCount
    self.metrics = metrics
    self.candidate = candidate
  }
}
