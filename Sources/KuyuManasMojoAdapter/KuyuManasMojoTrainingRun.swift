import Foundation
import ManasLearningContracts
import ManasMojoTraining

/// Owns one exact on-policy generation from dataset validation through an
/// explicit Mojo checkpoint boundary. Kuyu owns artifact conversion and run
/// orchestration; Manas owns all model, differentiation, PPO, and optimizer
/// arithmetic inside the session.
public struct KuyuManasMojoTrainingRun<Encoder: ManasLearningInputEncoding>:
  Sendable
{
  private let trajectoryAdapter: KuyuDatasetManasLearningAdapter<Encoder>
  private let sessionFactory: any KuyuManasPPOTrainingSessionCreating

  public init(
    trajectoryAdapter: KuyuDatasetManasLearningAdapter<Encoder>,
    sessionFactory: any KuyuManasPPOTrainingSessionCreating =
      KuyuManasMojoPPOTrainingSessionFactory()
  ) {
    self.trajectoryAdapter = trajectoryAdapter
    self.sessionFactory = sessionFactory
  }

  public func execute(
    datasetAt directory: URL,
    configuration: ManasMojoTrainingConfiguration,
    initialState: ManasMojoTrainingInitialState
  ) throws -> KuyuManasMojoTrainingResult {
    let trajectory = try trajectoryAdapter.trajectory(from: directory)
    let session = try sessionFactory.session(
      configuration: configuration,
      initialState: initialState,
      policyID: trajectory.identity.policyID,
      checkpointDigest: trajectory.identity.checkpointDigest
    )

    let operation: Result<KuyuManasMojoTrainingResult, any Error>
    do {
      let metrics = try session.update(trajectory)
      let checkpoint = try session.checkpoint()
      operation = .success(
        KuyuManasMojoTrainingResult(
          sourceIdentity: trajectory.identity,
          transitionCount: trajectory.transitions.count,
          metrics: metrics,
          checkpoint: checkpoint
        ))
    } catch {
      operation = .failure(error)
    }

    do {
      try session.shutdown()
    } catch {
      switch operation {
      case .success:
        throw KuyuManasMojoTrainingRunError.shutdownFailure(
          String(describing: error)
        )
      case .failure(let operationError):
        throw KuyuManasMojoTrainingRunError.operationCleanupFailure(
          operation: String(describing: operationError),
          cleanup: String(describing: error)
        )
      }
    }
    return try operation.get()
  }
}
