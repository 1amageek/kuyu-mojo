import ManasLearningContracts
import ManasMojoTraining

/// Creates the Mac training session whose complete PPO update is owned by Mojo.
public struct KuyuManasMojoPPOTrainingSessionFactory:
  KuyuManasPPOTrainingSessionCreating, Sendable
{
  public init() {}

  public func session(
    configuration: ManasMojoTrainingConfiguration,
    initialState: ManasMojoTrainingInitialState,
    policyID: String,
    checkpointDigest: String
  ) throws -> any ManasPPOTrainingSession {
    try ManasMojoPPOTrainingSession(
      configuration: configuration,
      initialState: initialState,
      expectedPolicyID: policyID,
      expectedCheckpointDigest: checkpointDigest
    )
  }
}
