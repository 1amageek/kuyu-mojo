import KuyuTrainingContracts
import KuyuTrainingRuntime
import ManasLearningContracts

public struct KuyuMojoLearningUpdateExecutor:
  LearningUpdateExecuting, Sendable
{
  private let service: any KuyuMojoTrainingExecuting

  public init(
    service: any KuyuMojoTrainingExecuting = KuyuMojoTrainingService()
  ) {
    self.service = service
  }

  public func execute(
    _ request: LearningUpdateRequest
  ) async throws -> LearningUpdateResult {
    try Task.checkCancellation()
    let plan = request.plan
    let ppo = try ManasPPOConfiguration(
      rewardDiscount: plan.rewardDiscount,
      rewardGAELambda: plan.rewardGAELambda,
      costDiscount: plan.costDiscount,
      costGAELambda: plan.costGAELambda,
      policyClip: plan.policyClip,
      valueClip: plan.valueClip,
      valueLossCoefficient: plan.valueLossCoefficient,
      costValueLossCoefficient: plan.costValueLossCoefficient,
      entropyCoefficient: plan.entropyCoefficient,
      maximumGradientNorm: plan.maximumGradientNorm,
      epochCount: plan.epochCount,
      minibatchSize: plan.minibatchSize,
      costLimit: plan.costLimit,
      initialLagrangeMultiplier: plan.initialLagrangeMultiplier,
      lagrangeLearningRate: plan.lagrangeLearningRate
    )
    let optimizer = try ManasAdamConfiguration(
      learningRate: plan.optimizerLearningRate,
      beta1: plan.optimizerBeta1,
      beta2: plan.optimizerBeta2,
      epsilon: plan.optimizerEpsilon
    )
    let backendRequest = KuyuMojoTrainingRequest(
      runID: request.runID,
      datasetURL: request.datasetURL,
      sourceBundle: request.sourceBundle,
      candidateBundleID: request.candidateBundleID,
      candidateBundleURL: request.candidateBundleURL,
      criticHiddenSize: plan.criticHiddenSize,
      initialPolicyLogStandardDeviation:
        plan.initialPolicyLogStandardDeviation,
      ppo: ppo,
      optimizer: optimizer,
      maximumTransitions: plan.maximumTransitions,
      maximumScalars: plan.maximumScalars
    )
    let operation = Task.detached { [service] in
      try Task.checkCancellation()
      return try service.train(backendRequest)
    }
    let backendResult = try await withTaskCancellationHandler {
      try await operation.value
    } onCancel: {
      operation.cancel()
    }
    return LearningUpdateResult(
      runID: backendResult.runID,
      source: sourceIdentity(backendResult.sourceIdentity),
      transitionCount: backendResult.transitionCount,
      metrics: metrics(backendResult.metrics),
      candidate: backendResult.candidate
    )
  }

  private func sourceIdentity(
    _ source: ManasLearningSourceIdentity
  ) -> LearningUpdateSourceIdentity {
    LearningUpdateSourceIdentity(
      datasetID: source.datasetID,
      recordsDigest: source.recordsDigest,
      policyID: source.policyID,
      checkpointDigest: source.checkpointDigest,
      actorInputContractDigest: source.actorInputContractDigest,
      criticInputContractDigest: source.criticInputContractDigest
    )
  }

  private func metrics(
    _ value: ManasPPOTrainingMetrics
  ) -> LearningUpdateMetrics {
    LearningUpdateMetrics(
      updateCount: value.updateCount,
      policyLoss: value.policyLoss,
      rewardValueLoss: value.rewardValueLoss,
      costValueLoss: value.costValueLoss,
      entropy: value.entropy,
      approximateKL: value.approximateKL,
      clipFraction: value.clipFraction,
      rewardAdvantageMean: value.rewardAdvantageMean,
      costAdvantageMean: value.costAdvantageMean,
      gradientNorm: value.gradientNorm,
      lagrangeMultiplier: value.lagrangeMultiplier
    )
  }
}
