import ManasLearningContracts
import ManasMojoTraining

public protocol KuyuManasPPOTrainingSessionCreating: Sendable {
  func session(
    configuration: ManasMojoTrainingConfiguration,
    initialState: ManasMojoTrainingInitialState,
    policyID: String,
    checkpointDigest: String
  ) throws -> any ManasPPOTrainingSession
}
