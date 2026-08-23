import Foundation
import KuyuManasMojoAdapter
import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import ManasLearningContracts
import ManasMojoOptimizer
import Mojo
import MojoRuntime
import Synchronization
import Testing

@Suite("Kuyu Manas Mojo Adam optimizer session factory")
struct KuyuManasMojoAdamOptimizerSessionFactoryTests {
  @Test(.timeLimit(.minutes(1)))
  func routesTheExactABIAndReleasesSessionBeforeRuntime() throws {
    let fixture = try AdamAdapterFixture()
    let factory = try fixture.factory()
    let optimizer = try factory.session(
      configuration: ManasAdamConfiguration(learningRate: 0.001),
      initialState: try Self.initialState()
    )

    #expect(
      fixture.observation.sessionRequirements
        == ManasMojoAdamOptimizerSession.sessionRequirements(
          device: .accelerator
        )
    )
    #expect(
      fixture.session.functionNames
        == [ManasMojoAdamOperation.initialization.functionName]
    )
    #expect(
      throws: ManasMojoAdamOptimizerError.proposalAlreadyPending
    ) {
      _ = try optimizer.proposal(
        for: ManasAdamGradientVector(
          layout: optimizer.layout,
          values: [0.5]
        )
      )
    }
    #expect(
      fixture.session.functionNames
        == [
          ManasMojoAdamOperation.initialization.functionName,
          ManasMojoAdamOperation.proposal.functionName,
        ]
    )

    try optimizer.shutdown()
    #expect(
      fixture.observation.lifecycleEvents
        == ["session.shutdown", "runtime.shutdown"]
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func initializationFailureMapsThroughManasAndCleansUp() throws {
    let fixture = try AdamAdapterFixture(
      initializationFailureStatus: 23
    )
    let factory = try fixture.factory()

    #expect(throws: ManasMojoAdamOptimizerError.invalidInitialState) {
      _ = try factory.session(
        configuration: ManasAdamConfiguration(
          learningRate: 0.001
        ),
        initialState: try Self.initialState()
      )
    }
    #expect(
      fixture.observation.lifecycleEvents
        == ["session.shutdown", "runtime.shutdown"]
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsRuntimeOperationMismatchAndCleansUp() throws {
    let actualOperations = Array(
      ManasMojoAdamABI.executionFunctionNames.dropLast()
    )
    let fixture = try AdamAdapterFixture(
      sessionOperationNames: actualOperations
    )
    let factory = try fixture.factory()

    #expect(
      throws:
        KuyuManasMojoAdamOptimizerSessionFactoryError
        .sessionOperationMismatch(
          expected: ManasMojoAdamABI.executionFunctionNames,
          actual: actualOperations
        )
    ) {
      _ = try factory.session(
        configuration: ManasAdamConfiguration(
          learningRate: 0.001
        ),
        initialState: try Self.initialState()
      )
    }
    #expect(
      fixture.observation.lifecycleEvents
        == ["session.shutdown", "runtime.shutdown"]
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func failedSessionCreationClosesTheRuntime() throws {
    let fixture = try AdamAdapterFixture(
      sessionCreationError: .sessionCreationFailed(status: 17)
    )
    let factory = try fixture.factory()

    #expect(
      throws:
        KuyuManasMojoAdamOptimizerSessionFactoryError.runtime(
          .sessionCreationFailed(status: 17)
        )
    ) {
      _ = try factory.session(
        configuration: ManasAdamConfiguration(
          learningRate: 0.001
        ),
        initialState: try Self.initialState()
      )
    }
    #expect(
      fixture.observation.lifecycleEvents == ["runtime.shutdown"]
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsMismatchedABIAtFactoryConstruction() throws {
    let fixture = try AdamAdapterFixture()
    let mismatchedRequirement = try fixture.requirement(
      executionFunctionNames: ["unexpectedOperation"]
    )
    #expect(
      throws:
        KuyuManasMojoAdamOptimizerSessionFactoryError.abiMismatch(
          expectedFactory:
            ManasMojoAdamABI.sessionFactoryFunctionName,
          actualFactory:
            ManasMojoAdamABI.sessionFactoryFunctionName,
          expectedOperations:
            ManasMojoAdamABI.executionFunctionNames,
          actualOperations: ["unexpectedOperation"]
        )
    ) {
      _ = try fixture.factory(requirement: mismatchedRequirement)
    }
    #expect(fixture.observation.lifecycleEvents.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func executesOptInRealMetalBundleWithCPUParity() throws {
    guard
      let bundlePath = ProcessInfo.processInfo.environment[
        "KUYU_MOJO_TEST_ADAM_ACCELERATOR_LIBRARY_BUNDLE"
      ]
    else {
      return
    }
    let configuration = try ManasAdamConfiguration(
      learningRate: 0.0013,
      beta1: 0.7,
      beta2: 0.93,
      epsilon: 1.0e-5
    )
    let layout = try ManasAdamParameterLayout(
      entries: [
        try ManasAdamParameterLayout.Entry(
          name: "parameters",
          shape: [4]
        )
      ]
    )
    let initialState = try ManasAdamState(
      layout: layout,
      parameters: [-0.1, 0.2, -0.3, 0.4]
    )
    let cpu = try ManasMojoAdamOptimizerSession(
      configuration: configuration,
      initialState: initialState
    )
    let metalFactory = try KuyuManasMojoAdamOptimizerSessionFactory(
      bundleURL: URL(
        fileURLWithPath: bundlePath,
        isDirectory: true
      ),
      requirement: try Self.realMetalRequirement()
    )
    let metalSession = try metalFactory.session(
      configuration: configuration,
      initialState: initialState
    )
    let metal = try #require(
      metalSession as? ManasMojoAdamOptimizerSession
    )
    defer {
      for session in [
        cpu as any ManasAdamOptimizerSession,
        metal as any ManasAdamOptimizerSession,
      ] {
        do {
          try session.shutdown()
        } catch {
          Issue.record("Optimizer shutdown failed: \(error)")
        }
      }
    }

    let discardedGradients = try ManasAdamGradientVector(
      layout: layout,
      values: [0.75, -0.5, 0.25, -0.125]
    )
    let cpuDiscarded = try cpu.proposal(for: discardedGradients)
    let metalDiscarded = try metal.proposal(for: discardedGradients)
    Self.expectClose(
      metalDiscarded.descentDirection.values,
      cpuDiscarded.descentDirection.values
    )
    try cpu.discard(cpuDiscarded)
    try metal.discard(metalDiscarded)
    Self.expectEquivalent(
      try metal.checkpoint(),
      try cpu.checkpoint()
    )

    for values in [
      [Float(0.5), -0.25, 0.125, -0.75],
      [-0.2, 0.6, -0.1, 0.4],
      [0.05, -0.15, 0.25, -0.35],
    ] {
      let gradients = try ManasAdamGradientVector(
        layout: layout,
        values: values
      )
      let cpuMetrics = try cpu.update(gradients)
      let metalMetrics = try metal.update(gradients)
      #expect(metalMetrics.updateCount == cpuMetrics.updateCount)
      #expect(
        abs(
          metalMetrics.maximumAbsoluteGradient
            - cpuMetrics.maximumAbsoluteGradient
        ) <= 1.0e-7
      )
      #expect(
        abs(
          metalMetrics.maximumAbsoluteStep
            - cpuMetrics.maximumAbsoluteStep
        ) <= 1.0e-7
      )
      Self.expectEquivalent(
        try metal.checkpoint(),
        try cpu.checkpoint()
      )
      let expectedProfile = try ManasMojoAdamUpdateProfile(
        hostToDeviceFullVectorTransfers: 1,
        deviceToHostFullVectorTransfers: 0,
        deviceToHostSummaryElementTransfers: 8,
        deviceSynchronizations: 2
      )
      #expect(
        metal.lastUpdateProfile == expectedProfile
      )
    }

    let beforeFailure = try metal.checkpoint()
    #expect {
      _ = try metal.update(
        ManasAdamGradientVector(
          layout: layout,
          values: [Float.greatestFiniteMagnitude, 0, 0, 0]
        )
      )
    } throws: { error in
      error as? ManasMojoAdamOptimizerError == .arithmeticFailure
    }
    #expect(try metal.checkpoint() == beforeFailure)
    let recovery = try metal.update(
      ManasAdamGradientVector(
        layout: layout,
        values: [0.1, -0.1, 0.2, -0.2]
      )
    )
    #expect(
      recovery.updateCount == beforeFailure.state.updateCount + 1
    )
  }

  @Test(.timeLimit(.minutes(2)))
  func benchmarksOptInFusedMetalUpdateAgainstProjectedPath() throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      environment["KUYU_MOJO_RUN_ADAM_BENCHMARK"] == "1",
      let bundlePath = environment[
        "KUYU_MOJO_TEST_ADAM_ACCELERATOR_LIBRARY_BUNDLE"
      ]
    else {
      return
    }
    let parameterCount = 1_048_576
    let warmupCount = 2
    let iterationCount = 12
    let layout = try ManasAdamParameterLayout(
      entries: [
        try ManasAdamParameterLayout.Entry(
          name: "parameters",
          shape: [parameterCount]
        )
      ]
    )
    let initialState = try ManasAdamState(
      layout: layout,
      parameters: [Float](
        repeating: 0.25,
        count: parameterCount
      )
    )
    let configuration = try ManasAdamConfiguration(
      learningRate: 0.0013,
      beta1: 0.7,
      beta2: 0.93,
      epsilon: 1.0e-5
    )
    let factory = try KuyuManasMojoAdamOptimizerSessionFactory(
      bundleURL: URL(fileURLWithPath: bundlePath, isDirectory: true),
      requirement: try Self.realMetalRequirement()
    )
    let fusedSession = try factory.session(
      configuration: configuration,
      initialState: initialState
    )
    let fused = try #require(
      fusedSession as? ManasMojoAdamOptimizerSession
    )
    let projectedSession = try factory.session(
      configuration: configuration,
      initialState: initialState
    )
    let projected = try #require(
      projectedSession as? ManasMojoAdamOptimizerSession
    )
    defer {
      for session in [fused, projected] {
        do {
          try session.shutdown()
        } catch {
          Issue.record("Optimizer shutdown failed: \(error)")
        }
      }
    }
    let gradients = try ManasAdamGradientVector(
      layout: layout,
      values: [Float](repeating: 0.5, count: parameterCount)
    )

    for _ in 0..<warmupCount {
      _ = try fused.update(gradients)
      let proposal = try projected.proposal(for: gradients)
      _ = try projected.commit(
        proposal,
        descentDirection: proposal.descentDirection
      )
    }

    let clock = ContinuousClock()
    let fusedStart = clock.now
    for _ in 0..<iterationCount {
      _ = try fused.update(gradients)
    }
    let fusedDuration = fusedStart.duration(to: clock.now)

    let projectedStart = clock.now
    for _ in 0..<iterationCount {
      let proposal = try projected.proposal(for: gradients)
      _ = try projected.commit(
        proposal,
        descentDirection: proposal.descentDirection
      )
    }
    let projectedDuration = projectedStart.duration(to: clock.now)

    let fusedSeconds = Self.seconds(fusedDuration)
    let projectedSeconds = Self.seconds(projectedDuration)
    let fusedMillisecondsPerUpdate =
      1_000 * fusedSeconds / Double(iterationCount)
    let projectedMillisecondsPerUpdate =
      1_000 * projectedSeconds / Double(iterationCount)
    let speedup = projectedSeconds / fusedSeconds
    print(
      "KUYU_MOJO_ADAM_BENCHMARK "
        + "parameterCount=\(parameterCount) "
        + "iterations=\(iterationCount) "
        + "fusedMillisecondsPerUpdate=\(fusedMillisecondsPerUpdate) "
        + "projectedMillisecondsPerUpdate="
        + "\(projectedMillisecondsPerUpdate) "
        + "speedup=\(speedup)"
    )

    #expect(fusedSeconds > 0)
    #expect(projectedSeconds > 0)
    #expect(
      fused.lastUpdateProfile?.deviceToHostFullVectorTransfers == 0
    )
  }

  private static func initialState() throws -> ManasAdamState {
    let layout = try ManasAdamParameterLayout(
      entries: [
        try ManasAdamParameterLayout.Entry(
          name: "parameters",
          shape: [1]
        )
      ]
    )
    return try ManasAdamState(layout: layout, parameters: [0.25])
  }

  private static func realMetalRequirement() throws
    -> MojoAcceleratorRuntimeBundleRequirement
  {
    try MojoAcceleratorRuntimeBundleRequirement(
      bundleDigest:
        "5ee189b92b7983583bec2b896e6b50f58ecc28df0247fd83fc3b2a9b742c5198",
      receiptDigest:
        "40e9ac97ad5467995bb712a99d1c3aec1162df674cc9de8549b75850f8927f16",
      target: MojoRuntimeBundleTarget(
        triple: "arm64-apple-macosx14.0",
        cpu: "apple-m4",
        accelerator: "metal:4"
      ),
      moduleName: "SwiftMojo_ManasMojoAdamAccelerator_ABI",
      inputGraphDigest:
        "01d227cf470d32edcd9247f8e4a4100905d954242b500ca73c7372c368928849",
      inputGraphIdentifier: 131_211_110_350_926_573,
      sessionFactoryFunctionName:
        ManasMojoAdamABI.sessionFactoryFunctionName,
      executionFunctionNames:
        ManasMojoAdamABI.executionFunctionNames
    )
  }

  private static func expectEquivalent(
    _ actual: ManasAdamCheckpoint,
    _ expected: ManasAdamCheckpoint
  ) {
    #expect(actual.configuration == expected.configuration)
    #expect(actual.state.layout == expected.state.layout)
    #expect(actual.state.updateCount == expected.state.updateCount)
    Self.expectClose(actual.state.parameters, expected.state.parameters)
    Self.expectClose(
      actual.state.firstMoments,
      expected.state.firstMoments
    )
    Self.expectClose(
      actual.state.secondMoments,
      expected.state.secondMoments
    )
  }

  private static func expectClose(
    _ actual: [Float],
    _ expected: [Float],
    tolerance: Float = 1.0e-6
  ) {
    #expect(actual.count == expected.count)
    for (actualValue, expectedValue) in zip(actual, expected) {
      #expect(abs(actualValue - expectedValue) <= tolerance)
    }
  }

  private static func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds)
      + Double(components.attoseconds) / 1.0e18
  }
}

private struct AdamAdapterFixture {
  let rootURL = URL(fileURLWithPath: "/tmp/kuyu-adam-fixture")
  let observation = AdamAdapterObservation()
  let session: StubAdamAcceleratorSession
  let runtime: StubAdamAcceleratorRuntime
  let bundle: MojoAcceleratorRuntimeBundle

  init(
    sessionOperationNames: [String] =
      ManasMojoAdamABI.executionFunctionNames,
    initializationFailureStatus: Int32? = nil,
    sessionCreationError: MojoAcceleratorRuntimeError? = nil
  ) throws {
    let session = StubAdamAcceleratorSession(
      executionFunctionNames: sessionOperationNames,
      initializationFailureStatus: initializationFailureStatus,
      observation: observation
    )
    self.session = session
    self.runtime = StubAdamAcceleratorRuntime(
      session: session,
      creationError: sessionCreationError,
      observation: observation
    )
    self.bundle = try Self.bundle(rootURL: rootURL)
  }

  func factory(
    requirement: MojoAcceleratorRuntimeBundleRequirement? = nil
  ) throws -> KuyuManasMojoAdamOptimizerSessionFactory {
    try KuyuManasMojoAdamOptimizerSessionFactory(
      bundleURL: rootURL,
      requirement: try requirement ?? self.requirement(),
      preflight: StubAdamBundlePreflight(
        bundle: bundle,
        observation: observation
      ),
      runtimeLoader: StubAdamRuntimeLoader(
        runtime: runtime,
        observation: observation
      )
    )
  }

  func requirement(
    executionFunctionNames: [String] =
      ManasMojoAdamABI.executionFunctionNames
  ) throws -> MojoAcceleratorRuntimeBundleRequirement {
    try MojoAcceleratorRuntimeBundleRequirement(
      bundleDigest: Self.digest("a"),
      receiptDigest: Self.digest("b"),
      target: Self.target,
      moduleName: "SwiftMojo_ManasMojoAdamAccelerator_ABI",
      inputGraphDigest: Self.digest("c"),
      inputGraphIdentifier: 42,
      sessionFactoryFunctionName:
        ManasMojoAdamABI.sessionFactoryFunctionName,
      executionFunctionNames: executionFunctionNames
    )
  }

  private static func bundle(
    rootURL: URL
  ) throws -> MojoAcceleratorRuntimeBundle {
    let factory = MojoRuntimeLibraryBinding(
      bindingID: 1,
      functionName: ManasMojoAdamABI.sessionFactoryFunctionName,
      signature: .runtimeSessionFactory
    )
    let executions = ManasMojoAdamABI.executionFunctionNames.enumerated()
      .map { index, functionName in
        MojoRuntimeLibraryBinding(
          bindingID: UInt64(index + 2),
          functionName: functionName,
          signature: .sessionBorrowedMutableFloat32Buffers,
          sessionFactoryFunctionName:
            ManasMojoAdamABI.sessionFactoryFunctionName
        )
      }
    let library = MojoRuntimeBundleFile(
      relativePath: "lib/libAdam.dylib",
      sha256Digest: digest("f")
    )
    let verification = MojoRuntimeLibraryBundleVerification(
      schemaVersion: 3,
      bundleDigest: digest("a"),
      receiptDigest: digest("b"),
      target: target,
      moduleName: "SwiftMojo_ManasMojoAdamAccelerator_ABI",
      compilerVersion: "fixture",
      inputGraphDigest: digest("c"),
      inputGraphIdentifier: 42,
      generatedSourceDigest: digest("d"),
      sourceMapDigest: digest("e"),
      bindings: [factory] + executions,
      loaderSearchPath: "@loader_path",
      library: library,
      runtimeLibraries: [],
      interfaceHeader: MojoRuntimeBundleFile(
        relativePath: "include/Adam.h",
        sha256Digest: digest("1")
      ),
      moduleMap: MojoRuntimeBundleFile(
        relativePath: "include/module.modulemap",
        sha256Digest: digest("2")
      ),
      exportedSymbols: [],
      systemDependencies: []
    )
    return try MojoAcceleratorRuntimeBundle(
      rootURL: rootURL,
      libraryURL: rootURL.appendingPathComponent(
        library.relativePath
      ),
      sessionFactoryBinding: factory,
      executionBindings: executions,
      verification: verification
    )
  }

  private static let target = MojoRuntimeBundleTarget(
    triple: "arm64-apple-macosx14.0",
    cpu: "apple-m4",
    accelerator: "metal:4"
  )

  private static func digest(_ character: Character) -> String {
    String(repeating: character, count: 64)
  }
}

private final class AdamAdapterObservation: Sendable {
  private struct State: Sendable {
    var sessionRequirements: MojoSessionRequirements?
    var lifecycleEvents: [String] = []
  }

  private let state = Mutex(State())

  var sessionRequirements: MojoSessionRequirements? {
    state.withLock(\.sessionRequirements)
  }

  var lifecycleEvents: [String] {
    state.withLock(\.lifecycleEvents)
  }

  func record(requirements: MojoSessionRequirements) {
    state.withLock { $0.sessionRequirements = requirements }
  }

  func record(event: String) {
    state.withLock { $0.lifecycleEvents.append(event) }
  }
}

private struct StubAdamBundlePreflight:
  MojoAcceleratorRuntimeBundlePreflighting, Sendable
{
  let bundle: MojoAcceleratorRuntimeBundle
  let observation: AdamAdapterObservation

  func validatedRuntimeBundle(
    at bundleURL: URL,
    requiring requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws -> MojoAcceleratorRuntimeBundle {
    bundle
  }
}

private struct StubAdamRuntimeLoader:
  MojoAcceleratorRuntimeLoading, Sendable
{
  let runtime: StubAdamAcceleratorRuntime
  let observation: AdamAdapterObservation

  func load(
    _ bundle: MojoAcceleratorRuntimeBundle
  ) throws -> any MojoAcceleratorRuntimeLibrary {
    runtime
  }
}

private final class StubAdamAcceleratorRuntime:
  MojoAcceleratorRuntimeLibrary, Sendable
{
  private let session: StubAdamAcceleratorSession
  private let creationError: MojoAcceleratorRuntimeError?
  private let observation: AdamAdapterObservation
  private let shutdownState = Mutex(false)

  init(
    session: StubAdamAcceleratorSession,
    creationError: MojoAcceleratorRuntimeError?,
    observation: AdamAdapterObservation
  ) {
    self.session = session
    self.creationError = creationError
    self.observation = observation
  }

  var isShutdown: Bool {
    shutdownState.withLock { $0 }
  }

  func makeSession(
    requirements: MojoSessionRequirements
  ) throws -> any MojoAcceleratorSession {
    observation.record(requirements: requirements)
    if let creationError {
      throw creationError
    }
    return session
  }

  func shutdown() throws {
    shutdownState.withLock { $0 = true }
    observation.record(event: "runtime.shutdown")
  }
}

private final class StubAdamAcceleratorSession:
  MojoAcceleratorSession, Sendable
{
  private struct State: Sendable {
    var functionNames: [String] = []
    var isShutdown = false
  }

  let capabilities = MojoSessionCapabilities(
    device: .accelerator,
    ordinal: 0,
    availableCapabilities: [
      .synchronousInvocation,
      .deviceMemory,
      .float32,
    ]
  )
  let executionFunctionNames: [String]
  private let initializationFailureStatus: Int32?
  private let observation: AdamAdapterObservation
  private let state = Mutex(State())

  init(
    executionFunctionNames: [String],
    initializationFailureStatus: Int32?,
    observation: AdamAdapterObservation
  ) {
    self.executionFunctionNames = executionFunctionNames
    self.initializationFailureStatus = initializationFailureStatus
    self.observation = observation
  }

  var functionNames: [String] {
    state.withLock(\.functionNames)
  }

  var isShutdown: Bool {
    state.withLock(\.isShutdown)
  }

  func execute(
    request: borrowing [Float],
    into output: inout [Float]
  ) throws {
    try execute(
      functionName: executionFunctionNames[0],
      request: request,
      into: &output
    )
  }

  func execute(
    functionName: String,
    request: borrowing [Float],
    into output: inout [Float]
  ) throws {
    state.withLock { $0.functionNames.append(functionName) }
    switch functionName {
    case ManasMojoAdamOperation.initialization.functionName:
      if let initializationFailureStatus {
        throw MojoAcceleratorRuntimeError.invocationFailed(
          status: initializationFailureStatus
        )
      }
      output = [1]
    case ManasMojoAdamOperation.proposal.functionName:
      throw MojoAcceleratorRuntimeError.invocationFailed(status: 35)
    default:
      throw MojoAcceleratorRuntimeError.unavailableExecutionFunction(
        functionName
      )
    }
  }

  func shutdown() throws {
    state.withLock { $0.isShutdown = true }
    observation.record(event: "session.shutdown")
  }
}
