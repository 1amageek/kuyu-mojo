import Foundation
import KuyuMojoTrainingRuntime
import KuyuTraining
import ManasCore
import ManasLearningContracts
import ManasMojoModels
import ManasMojoRuntime
import ManasMojoTraining
import Testing

@Suite("Kuyu Mojo training service")
struct KuyuMojoTrainingServiceTests {
  @Test(.timeLimit(.minutes(1)))
  func trainsFromValidatedDatasetAndPublishesReloadableCandidate()
    async throws
  {
    try await withTemporaryDirectoryForAsyncOperation { root in
      let source = try sourceBundle(
        at: root.appendingPathComponent("source", isDirectory: true),
        observationSchemaID: "observation"
      )
      let checkpointDigest = try #require(source.reference.contentHash)
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: datasetDescriptor(checkpointDigest: checkpointDigest),
        records: [datasetRecord(checkpointDigest: checkpointDigest)],
        to: dataset
      )
      let candidate = root.appendingPathComponent(
        "candidate",
        isDirectory: true
      )

      let result = try await KuyuMojoLearningUpdateExecutor().execute(
        LearningUpdateRequest(
          runID: "run-1",
          datasetURL: dataset,
          sourceBundle: source.reference,
          candidateBundleID: "candidate-1",
          candidateBundleURL: candidate,
          plan: LearningUpdatePlan(
            criticHiddenSize: 2,
            epochCount: 1,
            minibatchSize: 1,
            optimizerLearningRate: 0.001,
            maximumTransitions: 8,
            maximumScalars: 1_000_000
          )
        )
      )

      #expect(result.runID == "run-1")
      #expect(result.transitionCount == 1)
      #expect(result.metrics.updateCount == 1)
      #expect(result.metrics.gradientNorm > 0)
      #expect(result.candidate.kind == .candidate)
      #expect(result.candidate.contentHash?.count == 64)
      let reloaded = try FileSystemManasMojoModelBundleLoader()
        .validatedBundle(at: candidate)
      #expect(reloaded.manifest.bundleID == "candidate-1")
      #expect(reloaded.manifest.parentBundleID == "source-1")
      #expect(
        try ManasMojoCoreParameterMaterializer()
          .values(from: reloaded).count == source.coreValues.count
      )
      let checkpointData = try Data(
        contentsOf: candidate.appendingPathComponent(
          "training-checkpoint.json"
        )
      )
      let checkpoint = try JSONDecoder().decode(
        ManasMojoTrainingCheckpointArtifact.self,
        from: checkpointData
      ).checkpoint()
      #expect(checkpoint.optimizer.state.updateCount == 1)
      #expect(checkpoint.optimizer.state.parameters.contains { $0 != 0 })
      #expect(
        FileManager.default.fileExists(
          atPath: candidate.appendingPathComponent(
            "training-checkpoint.json"
          ).path
        )
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsObservationContractMismatchBeforeTraining() throws {
    try withTemporaryDirectory { root in
      let source = try sourceBundle(
        at: root.appendingPathComponent("source", isDirectory: true),
        observationSchemaID: "different-observation"
      )
      let checkpointDigest = try #require(source.reference.contentHash)
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: datasetDescriptor(checkpointDigest: checkpointDigest),
        records: [datasetRecord(checkpointDigest: checkpointDigest)],
        to: dataset
      )
      let candidate = root.appendingPathComponent(
        "candidate",
        isDirectory: true
      )

      #expect(
        throws: KuyuMojoTrainingServiceError.observationSchemaMismatch(
          expected: "different-observation",
          actual: "observation"
        )
      ) {
        _ = try KuyuMojoTrainingService().train(
          try trainingRequest(
            dataset: dataset,
            source: source,
            candidate: candidate
          )
        )
      }
      #expect(!FileManager.default.fileExists(atPath: candidate.path))
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsASourceReferenceWithTheWrongBundleIdentity() throws {
    try withTemporaryDirectory { root in
      let source = try sourceBundle(
        at: root.appendingPathComponent("source", isDirectory: true),
        observationSchemaID: "observation"
      )
      let mismatchedSource = SourceFixture(
        reference: ModelBundleReference(
          bundleID: "different-source",
          kind: source.reference.kind,
          url: source.reference.url,
          provenanceURL: source.reference.provenanceURL,
          contentHash: source.reference.contentHash,
          robotManifestID: source.reference.robotManifestID,
          observationSchemaID: source.reference.observationSchemaID,
          actionSchemaID: source.reference.actionSchemaID
        ),
        coreValues: source.coreValues
      )
      let checkpointDigest = try #require(source.reference.contentHash)
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: datasetDescriptor(checkpointDigest: checkpointDigest),
        records: [datasetRecord(checkpointDigest: checkpointDigest)],
        to: dataset
      )
      let candidate = root.appendingPathComponent(
        "candidate",
        isDirectory: true
      )

      #expect(
        throws: KuyuMojoTrainingServiceError.sourceBundleIDMismatch(
          expected: "source-1",
          actual: "different-source"
        )
      ) {
        _ = try KuyuMojoTrainingService().train(
          try trainingRequest(
            dataset: dataset,
            source: mismatchedSource,
            candidate: candidate
          )
        )
      }
      #expect(!FileManager.default.fileExists(atPath: candidate.path))
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsATrajectoryThatExceedsTheExactRecurrentMinibatch() throws {
    try withTemporaryDirectory { root in
      let source = try sourceBundle(
        at: root.appendingPathComponent("source", isDirectory: true),
        observationSchemaID: "observation"
      )
      let checkpointDigest = try #require(source.reference.contentHash)
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: datasetDescriptor(checkpointDigest: checkpointDigest),
        records: [
          datasetRecord(
            index: 0,
            source: [0, 0],
            outcome: [0.1, 0.1],
            inputStateDigest: digest("2"),
            outputStateDigest: digest("3"),
            boundary: .continues,
            checkpointDigest: checkpointDigest
          ),
          datasetRecord(
            index: 1,
            source: [0.1, 0.1],
            outcome: [0.2, 0.2],
            inputStateDigest: digest("3"),
            outputStateDigest: digest("4"),
            boundary: .segmentEnd(.init(bootstrapAllowed: false)),
            checkpointDigest: checkpointDigest
          ),
        ],
        to: dataset
      )
      let candidate = root.appendingPathComponent(
        "candidate",
        isDirectory: true
      )

      #expect(
        throws: KuyuMojoTrainingServiceError.trajectoryExceedsMinibatch(
          actual: 2,
          maximum: 1
        )
      ) {
        _ = try KuyuMojoTrainingService().train(
          try trainingRequest(
            dataset: dataset,
            source: source,
            candidate: candidate
          )
        )
      }
      #expect(!FileManager.default.fileExists(atPath: candidate.path))
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func resumesTheCompleteOptimizerStateFromACandidate() async throws {
    try await withTemporaryDirectoryForAsyncOperation { root in
      let source = try sourceBundle(
        at: root.appendingPathComponent("source", isDirectory: true),
        observationSchemaID: "observation"
      )
      let firstDigest = try #require(source.reference.contentHash)
      let firstDataset = root.appendingPathComponent(
        "dataset-1",
        isDirectory: true
      )
      try KuyuDatasetWriter().write(
        descriptor: datasetDescriptor(checkpointDigest: firstDigest),
        records: [datasetRecord(checkpointDigest: firstDigest)],
        to: firstDataset
      )
      let firstCandidate = root.appendingPathComponent(
        "candidate-1",
        isDirectory: true
      )
      let first = try KuyuMojoTrainingService().train(
        try trainingRequest(
          dataset: firstDataset,
          source: source,
          candidate: firstCandidate,
          optimizerLearningRate: 1.0e-12
        )
      )
      #expect(first.metrics.updateCount == 1)

      let secondDigest = try #require(first.candidate.contentHash)
      let secondDataset = root.appendingPathComponent(
        "dataset-2",
        isDirectory: true
      )
      try KuyuDatasetWriter().write(
        descriptor: datasetDescriptor(checkpointDigest: secondDigest),
        records: [datasetRecord(checkpointDigest: secondDigest)],
        to: secondDataset
      )
      let secondCandidate = root.appendingPathComponent(
        "candidate-2",
        isDirectory: true
      )
      let resumedSource = SourceFixture(
        reference: first.candidate,
        coreValues: try ManasMojoCoreParameterMaterializer().values(
          from: FileSystemManasMojoModelBundleLoader().validatedBundle(
            at: firstCandidate
          )
        )
      )
      let second = try KuyuMojoTrainingService().train(
        KuyuMojoTrainingRequest(
          runID: "run-2",
          datasetURL: secondDataset,
          sourceBundle: resumedSource.reference,
          candidateBundleID: "candidate-2",
          candidateBundleURL: secondCandidate,
          criticHiddenSize: 2,
          ppo: try ManasPPOConfiguration(
            epochCount: 1,
            minibatchSize: 1
          ),
          optimizer: try ManasAdamConfiguration(learningRate: 1.0e-12),
          maximumTransitions: 8,
          maximumScalars: 1_000_000
        )
      )

      #expect(second.metrics.updateCount == 2)
      let reloaded = try FileSystemManasMojoModelBundleLoader()
        .validatedBundle(at: secondCandidate)
      let decodedCheckpoint = try FileSystemManasMojoTrainingCheckpointReader()
        .checkpointIfPresent(
          in: reloaded
        )
      let checkpoint = try #require(
        decodedCheckpoint
      )
      #expect(checkpoint.optimizer.state.updateCount == 2)
      #expect(
        checkpoint.optimizer.state.firstMoments.contains { $0 != 0 }
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsDatasetCollectedByADifferentCheckpoint() throws {
    try withTemporaryDirectory { root in
      let source = try sourceBundle(
        at: root.appendingPathComponent("source", isDirectory: true),
        observationSchemaID: "observation"
      )
      let dataset = root.appendingPathComponent("dataset", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: datasetDescriptor(checkpointDigest: digest("e")),
        records: [datasetRecord(checkpointDigest: digest("e"))],
        to: dataset
      )
      let candidate = root.appendingPathComponent(
        "candidate",
        isDirectory: true
      )
      let expected = try #require(source.reference.contentHash)

      #expect(
        throws: KuyuMojoTrainingServiceError.datasetCheckpointMismatch(
          expected: expected,
          actual: digest("e")
        )
      ) {
        _ = try KuyuMojoTrainingService().train(
          try trainingRequest(
            dataset: dataset,
            source: source,
            candidate: candidate
          )
        )
      }
      #expect(!FileManager.default.fileExists(atPath: candidate.path))
    }
  }
}

private struct SourceFixture {
  let reference: ModelBundleReference
  let coreValues: [Float]
}

private func trainingRequest(
  dataset: URL,
  source: SourceFixture,
  candidate: URL,
  optimizerLearningRate: Float = 0.001
) throws -> KuyuMojoTrainingRequest {
  KuyuMojoTrainingRequest(
    runID: "run-1",
    datasetURL: dataset,
    sourceBundle: source.reference,
    candidateBundleID: "candidate-1",
    candidateBundleURL: candidate,
    criticHiddenSize: 2,
    ppo: try ManasPPOConfiguration(epochCount: 1, minibatchSize: 1),
    optimizer: try ManasAdamConfiguration(
      learningRate: optimizerLearningRate
    ),
    maximumTransitions: 8,
    maximumScalars: 1_000_000
  )
}

private func sourceBundle(
  at root: URL,
  observationSchemaID: String
) throws -> SourceFixture {
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: true
  )
  let configuration = try modelConfiguration()
  let schema = try ManasMojoParameterSchema(configuration: configuration)
  let coreValues = schema.coreParameters.flatMap { descriptor in
    [Float](repeating: 0, count: descriptor.elementCount)
  }
  let configurationURL = root.appendingPathComponent("model.json")
  let weightsURL = root.appendingPathComponent("core.safetensors")
  try JSONManasMojoModelConfigurationCodec().encode(configuration).write(
    to: configurationURL
  )
  try FileSystemManasMojoSafeTensorsWriter().write(
    parameters: schema.coreParameters,
    values: coreValues,
    to: weightsURL
  )
  let components = try [
    bundleComponent(
      role: .modelConfig,
      path: "model.json",
      contentType: FileSystemManasMojoModelBundleLoader
        .configurationContentType,
      at: configurationURL
    ),
    bundleComponent(
      role: .coreWeights,
      path: "core.safetensors",
      contentType: FileSystemManasMojoModelBundleLoader.weightsContentType,
      at: weightsURL
    ),
  ]
  try ManasModelBundleWriter().write(
    ManasModelBundleManifest(
      bundleID: "source-1",
      modelFamily: ManasMojoModelConfiguration.modelFamily,
      createdAt: Date(timeIntervalSince1970: 0),
      runtimeContract: ManasModelBundleRuntimeContract(
        embodimentHash: "embodiment",
        configHash: "configuration",
        observationSchemaID: observationSchemaID,
        driveSemanticsID: "drive-v1",
        corePeriodSeconds: 0.01
      ),
      components: components
    ),
    to: root
  )
  let unpinned = ModelBundleReference(
    bundleID: "source-1",
    kind: .source,
    url: root,
    observationSchemaID: observationSchemaID,
    actionSchemaID: "action"
  )
  let reference = try TrainingRunWorkerSourceIntegrityVerifier(
    allowedSourceRoots: [root.deletingLastPathComponent()]
  ).pinnedReference(unpinned)
  return SourceFixture(reference: reference, coreValues: coreValues)
}

private func modelConfiguration() throws -> ManasMojoModelConfiguration {
  let channels = try ManasMojoChannelLayout(
    typeEmbeddingCount: 2,
    ascendingTypeIndices: [0, 1],
    descendingTypeIndices: [],
    actuatorTypeIndices: [0]
  )
  return try ManasMojoModelConfiguration(
    core: try ManasMojoCoreConfiguration(
      channels: channels,
      typeEmbeddingDimension: 1,
      embeddingSize: 1,
      fastHiddenSize: 1,
      slowHiddenSize: 1,
      decoderHiddenSize: 1,
      morphologyDimension: 0,
      actuatorOutputs: [
        try ManasMojoActuatorOutput(
          lowerBound: -1,
          upperBound: 1,
          transform: .affineTanh
        )
      ]
    )
  )
}

private func datasetDescriptor(
  checkpointDigest: String
) -> KuyuDatasetDescriptor {
  KuyuDatasetDescriptor(
    identity: .init(
      datasetID: "dataset",
      scenarioID: "scenario",
      scenarioRevision: "1",
      suiteID: "suite",
      suiteVersion: "1",
      seed: 1,
      episodeID: "episode",
      segmentID: "segment",
      segmentIndex: 0
    ),
    producer: .init(id: "test", version: "1"),
    recordKind: .onPolicyTransition,
    execution: .init(
      dynamicsProgramSchemaVersion: 1,
      dynamicsProgramDigest: digest("d"),
      fidelityID: "reference",
      constraintProjectionID: "projection",
      mixerID: "mixer",
      rotorSpinConventionID: "spin",
      backendID: "scalar",
      backendVersion: "1",
      numericType: "float64",
      deviceClass: "cpu",
      determinismTier: "strict"
    ),
    spaces: .init(
      observation: space(id: "observation", digest: digest("e"), count: 2),
      criticState: space(id: "critic", digest: digest("f"), count: 2),
      policyAction: actionSpace(),
      realizedControl: space(id: "realized", digest: digest("a"), count: 1),
      actuatorCommand: space(id: "actuator", digest: digest("b"), count: 1)
    ),
    timing: .init(physicsTimeStep: 0.01, controlPeriodTicks: 2),
    semantics: .init(
      rewardDescriptorDigest: digest("a"),
      safetyCostDescriptorDigest: digest("b"),
      failureDescriptorDigest: digest("c"),
      taskQualityDescriptorDigest: digest("d")
    ),
    policy: .init(
      policyID: "policy",
      checkpointDigest: checkpointDigest,
      distributionContractDigest: digest("f")
    ),
    policyContext: .recurrent(
      .init(
        stateSpaceDigest: digest("1"),
        resetRule: "segment-initial-state",
        initialState: [0, 0],
        initialStateDigest: digest("2"),
        burnInCount: 0,
        lossStartTransitionIndex: 0
      )
    ),
    provenance: .init(
      codeDigest: digest("a"),
      configurationDigest: digest("b"),
      embodimentDigest: digest("c")
    )
  )
}

private func actionSpace() -> KuyuDatasetDescriptor.Space {
  KuyuDatasetDescriptor.Space(
    id: "action",
    version: "1",
    digest: digest("c"),
    channels: [
      KuyuDatasetDescriptor.Channel(
        index: 0,
        id: "action.0",
        unit: "normalized",
        lowerBound: -1,
        upperBound: 1,
        transform: .affineTanh
      )
    ]
  )
}

private func space(
  id: String,
  digest: String,
  count: Int
) -> KuyuDatasetDescriptor.Space {
  KuyuDatasetDescriptor.Space(
    id: id,
    version: "1",
    digest: digest,
    channels: (0..<count).map {
      KuyuDatasetDescriptor.Channel(
        index: $0,
        id: "\(id).\($0)",
        unit: "normalized"
      )
    }
  )
}

private func datasetRecord(
  index: Int = 0,
  source: [Double] = [0, 0],
  outcome: [Double] = [0.1, 0.1],
  inputStateDigest: String = digest("2"),
  outputStateDigest: String = digest("3"),
  boundary: KuyuTrajectoryBoundary = .segmentEnd(
    .init(bootstrapAllowed: false)
  ),
  checkpointDigest: String
) -> KuyuDatasetRecord {
  let sample = 0.2
  let action = tanh(sample)
  let startTime = Double(index) * 0.02
  let baseLogProbability =
    -0.5 * pow(sample / exp(-0.5), 2)
    + 0.5
    - 0.5 * log(2 * Double.pi)
  let transition = KuyuControlTransition(
    coordinate: .init(
      episodeID: "episode",
      segmentID: "segment",
      segmentIndex: 0,
      transitionIndex: index,
      decisionID: "decision-\(index)"
    ),
    sourceObservation: .init(time: startTime, values: source),
    sourceStateFacts: .init(values: source),
    policyAction: .init(values: [action]),
    realizedControl: .init(
      driveIntents: [.init(driveIndex: 0, activation: 0.4)],
      reflexCorrections: []
    ),
    actuatorCommand: .init(values: [0.4]),
    outcomeObservation: .init(time: startTime + 0.02, values: outcome),
    outcomeStateFacts: .init(values: outcome),
    reward: 1,
    safetyCost: 0.1,
    interval: .init(
      startTime: startTime,
      endTime: startTime + 0.02,
      actualDuration: 0.02,
      physicsTickCount: 2
    ),
    boundary: boundary
  )
  return .onPolicyTransition(
    .init(
      transition: transition,
      behavior: .init(
        policyID: "policy",
        checkpointDigest: checkpointDigest,
        distributionKinds: [.affineTanhGaussian],
        distributionVersion:
          KuyuBehaviorPolicyEvidence.currentDistributionVersion,
        distributionContractDigest: digest("f"),
        baseMean: [0],
        transformedMean: [0],
        baseLogStandardDeviation: [-0.5],
        preTransformSample: [sample],
        transformedAction: [action],
        logProbability: baseLogProbability - log(1 - action * action),
        rewardValue: 0,
        costValue: 0,
        inputRecurrentStateDigest: inputStateDigest,
        outputRecurrentStateDigest: outputStateDigest
      )
    )
  )
}

private func bundleComponent(
  role: ManasModelBundleComponentRole,
  path: String,
  contentType: String,
  at url: URL
) throws -> ManasModelBundleComponent {
  let data = try Data(contentsOf: url)
  return ManasModelBundleComponent(
    role: role,
    path: path,
    contentType: contentType,
    byteCount: data.count,
    fnv1a64: ManasModelBundleValidator.fnv1a64Hex(for: data)
  )
}

private func digest(_ character: Character) -> String {
  String(repeating: character, count: 64)
}

private func withTemporaryDirectory<Result>(
  _ operation: (URL) throws -> Result
) throws -> Result {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "kuyu-mojo-training-service-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: false
  )
  do {
    let result = try operation(root)
    try FileManager.default.removeItem(at: root)
    return result
  } catch {
    let operationError = error
    do {
      try FileManager.default.removeItem(at: root)
    } catch {
      throw TemporaryDirectoryCleanupError(
        operation: String(describing: operationError),
        cleanup: String(describing: error)
      )
    }
    throw operationError
  }
}

private func withTemporaryDirectoryForAsyncOperation<Result>(
  _ operation: (URL) async throws -> Result
) async throws -> Result {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "kuyu-mojo-training-service-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: false
  )
  do {
    let result = try await operation(root)
    try FileManager.default.removeItem(at: root)
    return result
  } catch {
    let operationError = error
    do {
      try FileManager.default.removeItem(at: root)
    } catch {
      throw TemporaryDirectoryCleanupError(
        operation: String(describing: operationError),
        cleanup: String(describing: error)
      )
    }
    throw operationError
  }
}

private struct TemporaryDirectoryCleanupError: Error {
  let operation: String
  let cleanup: String
}
