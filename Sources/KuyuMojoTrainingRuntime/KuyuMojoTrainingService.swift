import CryptoKit
import Foundation
import KuyuManasMojoAdapter
import KuyuTrainingContracts
import KuyuTrainingRuntime
import KuyuTrainingValidation
import ManasCore
import ManasLearningContracts
import ManasMojoModels
import ManasMojoTraining

public struct KuyuMojoTrainingService:
  KuyuMojoTrainingExecuting, Sendable
{
  private let datasetReader: KuyuDatasetReader
  private let sourceLoader: any ManasMojoModelBundleLoading
  private let checkpointReader: any ManasMojoTrainingCheckpointReading
  private let initialStateResolver: ManasMojoTrainingInitialStateResolver
  private let candidateWriter: ManasMojoTrainingCandidateWriter

  public init(
    datasetReader: KuyuDatasetReader = KuyuDatasetReader(),
    sourceLoader: any ManasMojoModelBundleLoading =
      FileSystemManasMojoModelBundleLoader(),
    checkpointReader: any ManasMojoTrainingCheckpointReading =
      FileSystemManasMojoTrainingCheckpointReader(),
    initialStateResolver: ManasMojoTrainingInitialStateResolver =
      ManasMojoTrainingInitialStateResolver(),
    candidateWriter: ManasMojoTrainingCandidateWriter =
      ManasMojoTrainingCandidateWriter()
  ) {
    self.datasetReader = datasetReader
    self.sourceLoader = sourceLoader
    self.checkpointReader = checkpointReader
    self.initialStateResolver = initialStateResolver
    self.candidateWriter = candidateWriter
  }

  public func train(
    _ request: KuyuMojoTrainingRequest
  ) throws -> KuyuMojoTrainingResult {
    try Task.checkCancellation()
    try validate(request)
    let sourceReference = try verifiedSourceReference(request.sourceBundle)
    let source = try autoreleasepool {
      try sourceLoader.validatedBundle(at: sourceReference.url)
    }
    try Task.checkCancellation()
    guard source.manifest.bundleID == sourceReference.bundleID else {
      throw KuyuMojoTrainingServiceError.sourceBundleIDMismatch(
        expected: source.manifest.bundleID,
        actual: sourceReference.bundleID
      )
    }
    let manifest = try datasetReader.manifest(in: request.datasetURL)
    let descriptor = manifest.descriptor
    guard let policy = descriptor.policy else {
      throw KuyuMojoTrainingServiceError.missingDatasetPolicy
    }
    guard let sourceDigest = sourceReference.contentHash else {
      throw KuyuMojoTrainingServiceError.missingVerifiedSourceDigest
    }
    guard policy.checkpointDigest.lowercased() == sourceDigest else {
      throw KuyuMojoTrainingServiceError.datasetCheckpointMismatch(
        expected: sourceDigest,
        actual: policy.checkpointDigest.lowercased()
      )
    }
    guard manifest.recordCount <= UInt64(request.ppo.minibatchSize) else {
      throw KuyuMojoTrainingServiceError.trajectoryExceedsMinibatch(
        actual: manifest.recordCount,
        maximum: request.ppo.minibatchSize
      )
    }
    try validate(descriptor: descriptor, source: source)

    let actorEncoder = try KuyuDirectLearningInputEncoder(
      actorInputContractDigest: inputContractDigest(
        kind: "actor",
        spaces: [descriptor.spaces.observation.digest]
      ),
      criticInputContractDigest: inputContractDigest(
        kind: "critic",
        spaces: [
          descriptor.spaces.observation.digest,
          descriptor.spaces.criticState?.digest ?? "none",
        ]
      )
    )
    let adapter = try KuyuDatasetManasLearningAdapter(
      encoder: actorEncoder,
      reader: datasetReader,
      maximumTransitions: request.maximumTransitions,
      maximumScalars: request.maximumScalars
    )
    let criticInputDimension = try criticInputDimension(
      descriptor.spaces
    )
    let configuration = try ManasMojoTrainingConfiguration(
      model: source.configuration,
      criticInputDimension: criticInputDimension,
      criticHiddenSize: request.criticHiddenSize,
      ppo: request.ppo,
      optimizer: request.optimizer,
      modelConfigurationDigest: try modelConfigurationDigest(
        source.configuration
      ),
      actionSpaceDigest: descriptor.spaces.policyAction.digest,
      distributionContractDigest: policy.distributionContractDigest
    )
    let checkpoint = try checkpointReader.checkpointIfPresent(
      in: source
    )
    let initialState = try initialStateResolver.initialState(
      sourceBundle: source,
      configuration: configuration,
      checkpoint: checkpoint,
      initialPolicyLogStandardDeviation:
        request.initialPolicyLogStandardDeviation
    )
    let update = try KuyuManasMojoTrainingRun(
      trajectoryAdapter: adapter
    ).execute(
      datasetAt: request.datasetURL,
      configuration: configuration,
      initialState: initialState
    )
    // Candidate publication is the atomic commit point. Cancellation observed
    // before it leaves no candidate; once publication begins, the completed
    // candidate is returned as success instead of reporting a false rollback.
    try Task.checkCancellation()
    let candidate = try candidateWriter.write(
      ManasMojoTrainingCandidateRequest(
        bundleID: request.candidateBundleID,
        sourceBundle: source,
        configuration: configuration,
        checkpoint: update.checkpoint,
        metrics: update.metrics,
        destinationURL: request.candidateBundleURL
      )
    )
    let candidateReference = try pinnedCandidateReference(
      candidate,
      source: sourceReference
    )
    return KuyuMojoTrainingResult(
      runID: request.runID,
      sourceIdentity: update.sourceIdentity,
      transitionCount: update.transitionCount,
      metrics: update.metrics,
      candidate: candidateReference
    )
  }

  private func validate(_ request: KuyuMojoTrainingRequest) throws {
    guard
      !request.candidateBundleID
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw KuyuMojoTrainingServiceError.emptyCandidateBundleID
    }
    guard request.criticHiddenSize > 0 else {
      throw KuyuMojoTrainingServiceError.invalidCriticHiddenSize(
        request.criticHiddenSize
      )
    }
    guard request.initialPolicyLogStandardDeviation.isFinite else {
      throw
        KuyuMojoTrainingServiceError
        .invalidInitialPolicyLogStandardDeviation(
          request.initialPolicyLogStandardDeviation
        )
    }
    guard request.maximumTransitions > 0 else {
      throw KuyuMojoTrainingServiceError.invalidMaximumTransitions(
        request.maximumTransitions
      )
    }
    guard request.maximumScalars > 0 else {
      throw KuyuMojoTrainingServiceError.invalidMaximumScalars(
        request.maximumScalars
      )
    }
  }

  private func validate(
    descriptor: KuyuDatasetDescriptor,
    source: ManasMojoModelBundle
  ) throws {
    let observation = descriptor.spaces.observation
    let expectedObservationSchemaID =
      source.manifest.runtimeContract.observationSchemaID
    guard observation.id == expectedObservationSchemaID else {
      throw KuyuMojoTrainingServiceError.observationSchemaMismatch(
        expected: expectedObservationSchemaID,
        actual: observation.id
      )
    }
    let expectedActorDimension =
      source.configuration.core.channels
      .ascendingTypeIndices.count
      + source.configuration.core.channels.descendingTypeIndices.count
      + source.configuration.core.morphologyDimension
    guard observation.channels.count == expectedActorDimension else {
      throw KuyuMojoTrainingServiceError.actorInputDimensionMismatch(
        expected: expectedActorDimension,
        actual: observation.channels.count
      )
    }
    let expectedActionDimension = source.configuration.core.channels
      .actuatorTypeIndices.count
    let actualActionDimension = descriptor.spaces.policyAction.channels.count
    guard actualActionDimension == expectedActionDimension else {
      throw KuyuMojoTrainingServiceError.actionDimensionMismatch(
        expected: expectedActionDimension,
        actual: actualActionDimension
      )
    }
  }

  private func criticInputDimension(
    _ spaces: KuyuDatasetDescriptor.Spaces
  ) throws -> Int {
    let stateCount = spaces.criticState?.channels.count ?? 0
    let result = spaces.observation.channels.count.addingReportingOverflow(
      stateCount
    )
    guard !result.overflow else {
      throw KuyuMojoTrainingServiceError.criticInputDimensionOverflow
    }
    return result.partialValue
  }

  private func modelConfigurationDigest(
    _ configuration: ManasMojoModelConfiguration
  ) throws -> String {
    let data = try JSONManasMojoModelConfigurationCodec()
      .encode(configuration)
    return SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private func inputContractDigest(
    kind: String,
    spaces: [String]
  ) -> String {
    var payload = Data("kuyu-direct-input-v1\0\(kind)".utf8)
    for space in spaces {
      payload.append(0)
      payload.append(contentsOf: space.utf8)
    }
    return SHA256.hash(data: payload).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private func verifiedSourceReference(
    _ reference: ModelBundleReference
  ) throws -> ModelBundleReference {
    try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [reference.url.deletingLastPathComponent()]
    ).verifiedReference(reference)
  }

  private func pinnedCandidateReference(
    _ candidate: ManasMojoTrainingCandidate,
    source: ModelBundleReference
  ) throws -> ModelBundleReference {
    try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [candidate.bundleRoot.deletingLastPathComponent()]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: candidate.manifest.bundleID,
        kind: .candidate,
        url: candidate.bundleRoot,
        provenanceURL: source.url,
        robotManifestID: source.robotManifestID,
        observationSchemaID: source.observationSchemaID,
        actionSchemaID: source.actionSchemaID
      )
    )
  }
}
