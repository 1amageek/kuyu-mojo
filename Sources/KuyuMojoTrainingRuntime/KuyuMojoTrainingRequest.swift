import Foundation
import KuyuTrainingContracts
import ManasLearningContracts

public struct KuyuMojoTrainingRequest: Sendable {
  public let runID: TrainingRunID
  public let datasetURL: URL
  public let sourceBundle: ModelBundleReference
  public let candidateBundleID: String
  public let candidateBundleURL: URL
  public let criticHiddenSize: Int
  public let initialPolicyLogStandardDeviation: Float
  public let ppo: ManasPPOConfiguration
  public let optimizer: ManasAdamConfiguration
  public let maximumTransitions: UInt64
  public let maximumScalars: Int

  public init(
    runID: TrainingRunID,
    datasetURL: URL,
    sourceBundle: ModelBundleReference,
    candidateBundleID: String,
    candidateBundleURL: URL,
    criticHiddenSize: Int = 128,
    initialPolicyLogStandardDeviation: Float = -0.5,
    ppo: ManasPPOConfiguration,
    optimizer: ManasAdamConfiguration,
    maximumTransitions: UInt64 = 256,
    maximumScalars: Int = 8_000_000
  ) {
    self.runID = runID
    self.datasetURL = datasetURL
    self.sourceBundle = sourceBundle
    self.candidateBundleID = candidateBundleID
    self.candidateBundleURL = candidateBundleURL
    self.criticHiddenSize = criticHiddenSize
    self.initialPolicyLogStandardDeviation =
      initialPolicyLogStandardDeviation
    self.ppo = ppo
    self.optimizer = optimizer
    self.maximumTransitions = maximumTransitions
    self.maximumScalars = maximumScalars
  }
}
