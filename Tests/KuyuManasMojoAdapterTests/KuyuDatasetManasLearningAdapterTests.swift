import Foundation
import KuyuManasMojoAdapter
import KuyuTrainingContracts
import KuyuTrainingValidation
import ManasLearningContracts
import ManasMojoModels
import ManasMojoTraining
import Synchronization
import Testing

@Suite
struct KuyuDatasetManasLearningAdapterTests {
  @Test
  func buildsValidatedImmutableTrajectory() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("artifact", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(),
        records: [makeRecord()],
        to: directory
      )
      let adapter = try KuyuDatasetManasLearningAdapter(
        encoder: KuyuDirectLearningInputEncoder(
          actorInputContractDigest: digest("a"),
          criticInputContractDigest: digest("b")
        ),
        maximumTransitions: 1,
        maximumScalars: 32
      )

      let trajectory = try adapter.trajectory(from: directory)

      #expect(trajectory.identity.datasetID == "dataset")
      #expect(trajectory.identity.actorInputContractDigest == digest("a"))
      #expect(trajectory.transitions.count == 1)
      #expect(trajectory.transitions[0].sourceActorInput == [0, 0])
      #expect(trajectory.transitions[0].outcomeCriticInput == [0.1, 0.1, 0.1, 0.1])
      #expect(trajectory.transitions[0].reward == 1)
      #expect(trajectory.transitions[0].boundary == .segmentEnd(bootstrapAllowed: false))
      #expect(trajectory.transitions[0].contributesToLoss)
    }
  }

  @Test
  func rejectsUnsupportedRecordKindBeforeConversion() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("artifact", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(recordKind: .demonstration),
        records: [makeDemonstrationRecord()],
        to: directory
      )
      let adapter = try makeAdapter()

      #expect(
        throws: KuyuDatasetManasLearningAdapter<TestEncoder>.AdapterError
          .unsupportedRecordKind(.demonstration)
      ) {
        _ = try adapter.trajectory(from: directory)
      }
    }
  }

  @Test
  func rejectsDeclaredTransitionCountAboveLimit() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("artifact", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(),
        records: [
          makeRecord(index: 0, isTerminal: false),
          makeRecord(index: 1, isTerminal: true),
        ],
        to: directory
      )
      let adapter = try makeAdapter(maximumTransitions: 1)

      #expect(
        throws: KuyuDatasetManasLearningAdapter<TestEncoder>.AdapterError
          .tooManyTransitions(maximum: 1)
      ) {
        _ = try adapter.trajectory(from: directory)
      }
    }
  }

  @Test
  func countsBehaviorEvidenceAgainstScalarBudget() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("artifact", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(),
        records: [makeRecord()],
        to: directory
      )
      let adapter = try makeAdapter(maximumScalars: 16)

      #expect(
        throws: KuyuDatasetManasLearningAdapter<TestEncoder>.AdapterError
          .tooManyScalars(maximum: 16)
      ) {
        _ = try adapter.trajectory(from: directory)
      }
    }
  }

  @Test
  func mapsRecurrentBurnInAndStateEvidence() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("artifact", isDirectory: true)
      let initialDigest = digest("1")
      let intermediateDigest = digest("2")
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(
          policyContext: .recurrent(
            .init(
              stateSpaceDigest: digest("3"),
              resetRule: "zero",
              initialState: [0],
              initialStateDigest: initialDigest,
              burnInCount: 1,
              lossStartTransitionIndex: 1
            ))),
        records: [
          makeRecord(
            index: 0,
            isTerminal: false,
            recurrentStateDigests: (initialDigest, intermediateDigest)
          ),
          makeRecord(
            index: 1,
            isTerminal: true,
            recurrentStateDigests: (intermediateDigest, digest("4"))
          ),
        ],
        to: directory
      )

      let trajectory = try makeAdapter().trajectory(from: directory)

      #expect(trajectory.transitions.map(\.contributesToLoss) == [false, true])
      #expect(trajectory.transitions[0].behavior.inputRecurrentStateDigest == initialDigest)
      #expect(trajectory.transitions[1].behavior.outputRecurrentStateDigest == digest("4"))
    }
  }

  @Test
  func rejectsNonFiniteEncoderOutput() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("artifact", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(),
        records: [makeRecord()],
        to: directory
      )
      let adapter = try KuyuDatasetManasLearningAdapter(
        encoder: NonFiniteEncoder()
      )

      #expect(
        throws: KuyuDatasetManasLearningAdapter<NonFiniteEncoder>.AdapterError
          .nonFiniteFloatConversion(field: "sourceActorInput", index: 0)
      ) {
        _ = try adapter.trajectory(from: directory)
      }
    }
  }

  @Test
  func exactVerifierRejectsFabricatedLogProbabilityDuringConversion() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent("artifact", isDirectory: true)
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(),
        records: [makeRecord(logProbability: 0)],
        to: directory
      )
      let adapter = try makeAdapter()

      #expect(throws: KuyuExactOnPolicyEvidenceVerifier.VerificationError.self) {
        _ = try adapter.trajectory(from: directory)
      }
    }
  }

  @Test
  func rejectsInvalidResourceLimits() throws {
    #expect(
      throws: KuyuDatasetManasLearningAdapter<TestEncoder>.AdapterError
        .invalidMaximumTransitions(0)
    ) {
      _ = try KuyuDatasetManasLearningAdapter(
        encoder: TestEncoder(),
        maximumTransitions: 0
      )
    }
    #expect(
      throws: KuyuDatasetManasLearningAdapter<TestEncoder>.AdapterError
        .invalidMaximumScalars(0)
    ) {
      _ = try KuyuDatasetManasLearningAdapter(
        encoder: TestEncoder(),
        maximumScalars: 0
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func executesValidatedDatasetInRealMojoPPOTrainingSession() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent(
        "artifact",
        isDirectory: true
      )
      let initialDigest = digest("1")
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(
          policyContext: .recurrent(
            .init(
              stateSpaceDigest: digest("2"),
              resetRule: "segment-initial-state",
              initialState: [0, 0],
              initialStateDigest: initialDigest,
              burnInCount: 0,
              lossStartTransitionIndex: 0
            ))),
        records: [
          makeRecord(
            recurrentStateDigests: (initialDigest, digest("3"))
          )
        ],
        to: directory
      )
      let adapter = try makeAdapter(
        maximumTransitions: 1,
        maximumScalars: 64
      )
      let configuration = try makeTrainingConfiguration()
      let schema = try ManasMojoTrainingParameterSchema(
        configuration: configuration
      )
      let initialState = try ManasMojoTrainingInitialState(
        schema: schema,
        actorCoreParameters: [Float](
          repeating: 0,
          count: schema.actorCoreRange.count
        ),
        costCriticParameters: [Float](
          repeating: 0,
          count: schema.costCriticRange.count
        ),
        policyLogStandardDeviation: [-0.5],
        rewardCriticParameters: [Float](
          repeating: 0,
          count: schema.rewardCriticRange.count
        ),
        lagrangeMultiplier: 0
      )
      let run = KuyuManasMojoTrainingRun(
        trajectoryAdapter: adapter
      )

      let result = try run.execute(
        datasetAt: directory,
        configuration: configuration,
        initialState: initialState
      )

      #expect(result.sourceIdentity.datasetID == "dataset")
      #expect(result.transitionCount == 1)
      #expect(result.metrics.updateCount == 1)
      #expect(result.metrics.gradientNorm > 0)
      #expect(result.checkpoint.optimizer.state.updateCount == 1)
      #expect(
        result.checkpoint.optimizer.state.parameters[
          schema.rewardCriticRange
        ].contains { $0 != 0 }
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func shutsDownTrainingSessionAfterOperationFailure() throws {
    try withTemporaryDirectory { root in
      let directory = root.appendingPathComponent(
        "artifact",
        isDirectory: true
      )
      let initialDigest = digest("1")
      try KuyuDatasetWriter().write(
        descriptor: makeDescriptor(
          policyContext: .recurrent(
            .init(
              stateSpaceDigest: digest("2"),
              resetRule: "segment-initial-state",
              initialState: [0, 0],
              initialStateDigest: initialDigest,
              burnInCount: 0,
              lossStartTransitionIndex: 0
            ))),
        records: [
          makeRecord(
            recurrentStateDigests: (initialDigest, digest("3"))
          )
        ],
        to: directory
      )
      let configuration = try makeTrainingConfiguration()
      let schema = try ManasMojoTrainingParameterSchema(
        configuration: configuration
      )
      let initialState = try ManasMojoTrainingInitialState(
        schema: schema,
        actorCoreParameters: [Float](
          repeating: 0,
          count: schema.actorCoreRange.count
        ),
        costCriticParameters: [Float](
          repeating: 0,
          count: schema.costCriticRange.count
        ),
        policyLogStandardDeviation: [-0.5],
        rewardCriticParameters: [Float](
          repeating: 0,
          count: schema.rewardCriticRange.count
        ),
        lagrangeMultiplier: 0
      )
      let session = FailingTrainingSession()
      let run = KuyuManasMojoTrainingRun(
        trajectoryAdapter: try makeAdapter(
          maximumTransitions: 1,
          maximumScalars: 64
        ),
        sessionFactory: FailingTrainingSessionFactory(session: session)
      )

      #expect(throws: TestTrainingFailure.update) {
        _ = try run.execute(
          datasetAt: directory,
          configuration: configuration,
          initialState: initialState
        )
      }
      #expect(session.isShutdown)
    }
  }
}

private enum TestTrainingFailure: Error {
  case update
}

private struct FailingTrainingSessionFactory:
  KuyuManasPPOTrainingSessionCreating
{
  let session: FailingTrainingSession

  func session(
    configuration: ManasMojoTrainingConfiguration,
    initialState: ManasMojoTrainingInitialState,
    policyID: String,
    checkpointDigest: String
  ) throws -> any ManasPPOTrainingSession {
    session
  }
}

private final class FailingTrainingSession: ManasPPOTrainingSession {
  private let shutdownState = Mutex(false)

  var isShutdown: Bool {
    shutdownState.withLock { $0 }
  }

  func update(
    _ trajectory: ManasOnPolicyTrajectory
  ) throws -> ManasPPOTrainingMetrics {
    throw TestTrainingFailure.update
  }

  func checkpoint() throws -> ManasPPOTrainingCheckpoint {
    throw TestTrainingFailure.update
  }

  func shutdown() throws {
    shutdownState.withLock { $0 = true }
  }
}

private struct TestEncoder: ManasLearningInputEncoding {
  let actorInputContractDigest = digest("a")
  let criticInputContractDigest = digest("b")

  func actorInput(observation: [Double], stateFacts: [Double]) throws -> [Float] {
    observation.map(Float.init)
  }

  func criticInput(observation: [Double], stateFacts: [Double]) throws -> [Float] {
    stateFacts.map(Float.init)
  }
}

private struct NonFiniteEncoder: ManasLearningInputEncoding {
  let actorInputContractDigest = digest("a")
  let criticInputContractDigest = digest("b")

  func actorInput(observation: [Double], stateFacts: [Double]) throws -> [Float] {
    [.infinity]
  }

  func criticInput(observation: [Double], stateFacts: [Double]) throws -> [Float] {
    [0]
  }
}

private func makeAdapter(
  maximumTransitions: UInt64 = 100_000,
  maximumScalars: Int = 8_000_000
) throws -> KuyuDatasetManasLearningAdapter<TestEncoder> {
  try KuyuDatasetManasLearningAdapter(
    encoder: TestEncoder(),
    maximumTransitions: maximumTransitions,
    maximumScalars: maximumScalars
  )
}

private func makeDescriptor(
  recordKind: KuyuDatasetRecord.Kind = .onPolicyTransition,
  policyContext suppliedPolicyContext: KuyuPolicyContextContract? = nil
) -> KuyuDatasetDescriptor {
  let actionSpace = KuyuDatasetDescriptor.Space(
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
  let isOnPolicy = recordKind == .onPolicyTransition
  return KuyuDatasetDescriptor(
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
    recordKind: recordKind,
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
      observation: makeSpace(id: "observation", digest: digest("e"), count: 2),
      criticState: makeSpace(id: "critic", digest: digest("f"), count: 2),
      policyAction: actionSpace,
      realizedControl: makeSpace(id: "realized", digest: digest("a"), count: 1),
      actuatorCommand: makeSpace(id: "actuator", digest: digest("b"), count: 1)
    ),
    timing: .init(physicsTimeStep: 0.01, controlPeriodTicks: 2),
    semantics: .init(
      rewardDescriptorDigest: digest("a"),
      safetyCostDescriptorDigest: digest("b"),
      failureDescriptorDigest: digest("c"),
      taskQualityDescriptorDigest: digest("d")
    ),
    policy: isOnPolicy
      ? .init(
        policyID: "policy",
        checkpointDigest: digest("e"),
        distributionContractDigest: digest("f")
      )
      : nil,
    policyContext: isOnPolicy
      ? suppliedPolicyContext
        ?? .fixedHistory(
          .init(
            historyLength: 1,
            featureOrderDigest: digest("a"),
            paddingRule: .zero,
            previousActionRule: .zeroBeforeFirstDecision
          ))
      : nil,
    provenance: .init(
      codeDigest: digest("a"),
      configurationDigest: digest("b"),
      embodimentDigest: digest("c")
    )
  )
}

private func makeSpace(
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

private func makeRecord(
  index: Int = 0,
  isTerminal: Bool = true,
  logProbability: Double? = nil,
  recurrentStateDigests: (input: String, output: String)? = nil
) -> KuyuDatasetRecord {
  let sample = 0.2
  let action = tanh(sample)
  let baseLogProbability =
    -0.5 * pow(sample / exp(-0.5), 2)
    + 0.5
    - 0.5 * log(2 * Double.pi)
  let exactLogProbability = baseLogProbability - log(1 - action * action)
  let sourceValues = index == 0 ? [0.0, 0.0] : [0.1, 0.1]
  let transition = KuyuControlTransition(
    coordinate: coordinate(index: index),
    sourceObservation: .init(time: Double(index) * 0.02, values: sourceValues),
    sourceStateFacts: .init(values: sourceValues),
    policyAction: .init(values: [action]),
    realizedControl: .init(
      driveIntents: [.init(driveIndex: 0, activation: 0.4)],
      reflexCorrections: []
    ),
    actuatorCommand: .init(values: [0.4]),
    outcomeObservation: .init(time: Double(index + 1) * 0.02, values: [0.1, 0.1]),
    outcomeStateFacts: .init(values: [0.1, 0.1]),
    reward: 1,
    safetyCost: 0.1,
    interval: .init(
      startTime: Double(index) * 0.02,
      endTime: Double(index + 1) * 0.02,
      actualDuration: 0.02,
      physicsTickCount: 2
    ),
    boundary: isTerminal
      ? .segmentEnd(.init(bootstrapAllowed: false))
      : .continues
  )
  return .onPolicyTransition(
    .init(
      transition: transition,
      behavior: .init(
        policyID: "policy",
        checkpointDigest: digest("e"),
        distributionKinds: [.affineTanhGaussian],
        distributionVersion: KuyuBehaviorPolicyEvidence.currentDistributionVersion,
        distributionContractDigest: digest("f"),
        baseMean: [0],
        transformedMean: [0],
        baseLogStandardDeviation: [-0.5],
        preTransformSample: [sample],
        transformedAction: [action],
        logProbability: logProbability ?? exactLogProbability,
        rewardValue: 0,
        costValue: 0,
        inputRecurrentStateDigest: recurrentStateDigests?.input,
        outputRecurrentStateDigest: recurrentStateDigests?.output
      )
    ))
}

private func makeDemonstrationRecord() -> KuyuDatasetRecord {
  .demonstration(
    .init(
      coordinate: coordinate(index: 0),
      observation: .init(time: 0, values: [0, 0]),
      stateFacts: .init(values: [0, 0]),
      teacherAction: .init(values: [0]),
      teacherID: "teacher"
    ))
}

private func coordinate(index: Int) -> KuyuTrajectoryCoordinate {
  .init(
    episodeID: "episode",
    segmentID: "segment",
    segmentIndex: 0,
    transitionIndex: index,
    decisionID: "decision-\(index)"
  )
}

private func digest(_ value: String) -> String {
  String(repeating: value, count: 64)
}

private func withTemporaryDirectory<T>(_ operation: (URL) throws -> T) throws -> T {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("kuyu-mojo-manas-adapter-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  do {
    let result = try operation(directory)
    try FileManager.default.removeItem(at: directory)
    return result
  } catch {
    let primaryError = error
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      throw TemporaryDirectoryCleanupError(
        primary: String(describing: primaryError),
        cleanup: String(describing: error)
      )
    }
    throw primaryError
  }
}

private func makeTrainingConfiguration() throws
  -> ManasMojoTrainingConfiguration
{
  let channels = try ManasMojoChannelLayout(
    typeEmbeddingCount: 1,
    ascendingTypeIndices: [0, 0],
    descendingTypeIndices: [],
    actuatorTypeIndices: [0]
  )
  let core = try ManasMojoCoreConfiguration(
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
  return try ManasMojoTrainingConfiguration(
    model: ManasMojoModelConfiguration(core: core),
    criticInputDimension: 2,
    criticHiddenSize: 1,
    ppo: ManasPPOConfiguration(epochCount: 1, minibatchSize: 1),
    optimizer: ManasAdamConfiguration(learningRate: 0.001),
    modelConfigurationDigest: digest("a"),
    actionSpaceDigest: digest("c"),
    distributionContractDigest: digest("f")
  )
}

private struct TemporaryDirectoryCleanupError: Error {
  let primary: String
  let cleanup: String
}
