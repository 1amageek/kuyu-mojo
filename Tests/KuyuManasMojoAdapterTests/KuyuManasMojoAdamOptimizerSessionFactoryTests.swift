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
    let metal = try metalFactory.session(
      configuration: configuration,
      initialState: initialState
    )
    defer {
      for session in [cpu as any ManasAdamOptimizerSession, metal] {
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
      let cpuProposal = try cpu.proposal(for: gradients)
      let metalProposal = try metal.proposal(for: gradients)
      Self.expectClose(
        metalProposal.descentDirection.values,
        cpuProposal.descentDirection.values
      )
      let cpuMetrics = try cpu.commit(
        cpuProposal,
        descentDirection: cpuProposal.descentDirection
      )
      let metalMetrics = try metal.commit(
        metalProposal,
        descentDirection: metalProposal.descentDirection
      )
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
    }
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
        "daaaaaa311e3a61729ff11368f71c0b95fd0f97273c73069f9c81e03661df161",
      receiptDigest:
        "bae966a967f03da812abba0e0c081118978d831697fcb62e9a9db9084c6ba1f0",
      target: MojoRuntimeBundleTarget(
        triple: "arm64-apple-macosx14.0",
        cpu: "apple-m4",
        accelerator: "metal:4"
      ),
      moduleName: "SwiftMojo_ManasMojoAdamAccelerator_ABI",
      inputGraphDigest:
        "e5c98830809ab66bcfb278362f375c3e2be95d4e81b9a424951f1715fb83b4ba",
      inputGraphIdentifier: 7_334_543_210_046_994_027,
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
