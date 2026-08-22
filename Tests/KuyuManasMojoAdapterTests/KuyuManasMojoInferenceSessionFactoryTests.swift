import Foundation
import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import ManasMojoRuntime
import Mojo
import MojoRuntime
import Synchronization
import Testing

@testable import KuyuManasMojoAdapter

@Suite("Kuyu Manas Mojo inference session factory")
struct KuyuManasMojoInferenceSessionFactoryTests {
  @Test(.timeLimit(.minutes(1)))
  func coreTransportRoutesExactABIAndOwnsShutdownOrder() throws {
    let fixture = try InferenceAdapterFixture(
      factoryFunctionName:
        ManasMojoInferenceABI.coreSessionFactoryFunctionName,
      operations: ManasMojoInferenceABI.coreOperations
    )
    let factory = KuyuManasMojoInferenceTransportFactory(
      bundleURL: fixture.rootURL,
      requirement: fixture.requirement,
      operations: ManasMojoInferenceABI.coreOperations,
      sessionRequirements: ManasMojoCoreModelSession.sessionRequirements(
        device: .accelerator
      ),
      preflight: fixture.preflight,
      runtimeLoader: fixture.loader
    )
    let transport = try factory.transport()
    var output: [Float] = [0]

    try transport.execute(
      .coreInitialization,
      request: [1],
      into: &output
    )

    #expect(output == [1])
    #expect(
      fixture.observation.requirements
        == ManasMojoCoreModelSession.sessionRequirements(
          device: .accelerator
        )
    )
    #expect(
      fixture.observation.functionNames == [
        ManasMojoInferenceOperation.coreInitialization.functionName
      ]
    )
    try transport.shutdown()
    #expect(
      fixture.observation.lifecycleEvents == [
        "session.shutdown",
        "runtime.shutdown",
      ]
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func publicFactoriesRejectCrossWiredABI() throws {
    let coreRequirement = try InferenceAdapterFixture.requirement(
      factoryFunctionName:
        ManasMojoInferenceABI.coreSessionFactoryFunctionName,
      operations: ManasMojoInferenceABI.coreOperations
    )

    #expect(throws: KuyuManasMojoInferenceSessionFactoryError.self) {
      _ = try KuyuManasMojoReflexInferenceSessionFactory(
        bundleURL: URL(fileURLWithPath: "/tmp/reflex-runtime"),
        requirement: coreRequirement
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func sessionOperationMismatchClosesSessionThenRuntime() throws {
    let fixture = try InferenceAdapterFixture(
      factoryFunctionName:
        ManasMojoInferenceABI.coreSessionFactoryFunctionName,
      operations: ManasMojoInferenceABI.coreOperations,
      sessionFunctionNames:
        ManasMojoInferenceABI.reflexExecutionFunctionNames
    )
    let factory = KuyuManasMojoInferenceTransportFactory(
      bundleURL: fixture.rootURL,
      requirement: fixture.requirement,
      operations: ManasMojoInferenceABI.coreOperations,
      sessionRequirements: ManasMojoCoreModelSession.sessionRequirements(
        device: .accelerator
      ),
      preflight: fixture.preflight,
      runtimeLoader: fixture.loader
    )

    #expect(
      throws:
        KuyuManasMojoInferenceSessionFactoryError
        .sessionOperationMismatch(
          expected: ManasMojoInferenceABI.coreExecutionFunctionNames,
          actual: ManasMojoInferenceABI.reflexExecutionFunctionNames
        )
    ) {
      _ = try factory.transport()
    }
    #expect(
      fixture.observation.lifecycleEvents == [
        "session.shutdown",
        "runtime.shutdown",
      ]
    )
  }
}

private struct InferenceAdapterFixture {
  let rootURL = URL(fileURLWithPath: "/tmp/kuyu-inference-fixture")
  let observation = InferenceAdapterObservation()
  let requirement: MojoAcceleratorRuntimeBundleRequirement
  let preflight: InferenceBundlePreflight
  let loader: InferenceRuntimeLoader

  init(
    factoryFunctionName: String,
    operations: [ManasMojoInferenceOperation],
    sessionFunctionNames: [String]? = nil
  ) throws {
    let requirement = try Self.requirement(
      factoryFunctionName: factoryFunctionName,
      operations: operations
    )
    let session = InferenceAcceleratorSession(
      executionFunctionNames:
        sessionFunctionNames ?? operations.map(\.functionName),
      observation: observation
    )
    let runtime = InferenceAcceleratorRuntime(
      session: session,
      observation: observation
    )
    self.requirement = requirement
    self.preflight = InferenceBundlePreflight(
      bundle: try Self.bundle(
        rootURL: rootURL,
        requirement: requirement
      )
    )
    self.loader = InferenceRuntimeLoader(runtime: runtime)
  }

  static func requirement(
    factoryFunctionName: String,
    operations: [ManasMojoInferenceOperation]
  ) throws -> MojoAcceleratorRuntimeBundleRequirement {
    try MojoAcceleratorRuntimeBundleRequirement(
      bundleDigest: digest("a"),
      receiptDigest: digest("b"),
      target: target,
      moduleName: "SwiftMojo_ManasMojoInference_ABI",
      inputGraphDigest: digest("c"),
      inputGraphIdentifier: 43,
      sessionFactoryFunctionName: factoryFunctionName,
      executionFunctionNames: operations.map(\.functionName)
    )
  }

  private static func bundle(
    rootURL: URL,
    requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws -> MojoAcceleratorRuntimeBundle {
    let factory = MojoRuntimeLibraryBinding(
      bindingID: 1,
      functionName: requirement.sessionFactoryFunctionName,
      signature: .runtimeSessionFactory
    )
    let executions = requirement.executionFunctionNames.enumerated().map {
      index,
      functionName in
      MojoRuntimeLibraryBinding(
        bindingID: UInt64(index + 2),
        functionName: functionName,
        signature: .sessionBorrowedMutableFloat32Buffers,
        sessionFactoryFunctionName: requirement.sessionFactoryFunctionName
      )
    }
    let library = MojoRuntimeBundleFile(
      relativePath: "lib/libInference.dylib",
      sha256Digest: digest("f")
    )
    let verification = MojoRuntimeLibraryBundleVerification(
      schemaVersion: 3,
      bundleDigest: requirement.bundleDigest,
      receiptDigest: requirement.receiptDigest,
      target: requirement.target,
      moduleName: requirement.moduleName,
      compilerVersion: "fixture",
      inputGraphDigest: requirement.inputGraphDigest,
      inputGraphIdentifier: requirement.inputGraphIdentifier,
      generatedSourceDigest: digest("d"),
      sourceMapDigest: digest("e"),
      bindings: [factory] + executions,
      loaderSearchPath: "@loader_path",
      library: library,
      runtimeLibraries: [],
      interfaceHeader: MojoRuntimeBundleFile(
        relativePath: "include/Inference.h",
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
      libraryURL: rootURL.appendingPathComponent(library.relativePath),
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

private final class InferenceAdapterObservation: Sendable {
  private struct State: Sendable {
    var requirements: MojoSessionRequirements?
    var functionNames: [String] = []
    var lifecycleEvents: [String] = []
  }

  private let state = Mutex(State())

  var requirements: MojoSessionRequirements? {
    state.withLock(\.requirements)
  }

  var functionNames: [String] {
    state.withLock(\.functionNames)
  }

  var lifecycleEvents: [String] {
    state.withLock(\.lifecycleEvents)
  }

  func record(requirements: MojoSessionRequirements) {
    state.withLock { $0.requirements = requirements }
  }

  func record(functionName: String) {
    state.withLock { $0.functionNames.append(functionName) }
  }

  func record(lifecycleEvent: String) {
    state.withLock { $0.lifecycleEvents.append(lifecycleEvent) }
  }
}

private struct InferenceBundlePreflight:
  MojoAcceleratorRuntimeBundlePreflighting, Sendable
{
  let bundle: MojoAcceleratorRuntimeBundle

  func validatedRuntimeBundle(
    at bundleURL: URL,
    requiring requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws -> MojoAcceleratorRuntimeBundle {
    bundle
  }
}

private struct InferenceRuntimeLoader: MojoAcceleratorRuntimeLoading, Sendable {
  let runtime: InferenceAcceleratorRuntime

  func load(
    _ bundle: MojoAcceleratorRuntimeBundle
  ) throws -> any MojoAcceleratorRuntimeLibrary {
    runtime
  }
}

private final class InferenceAcceleratorRuntime:
  MojoAcceleratorRuntimeLibrary, Sendable
{
  private let session: InferenceAcceleratorSession
  private let observation: InferenceAdapterObservation
  private let shutdownState = Mutex(false)

  init(
    session: InferenceAcceleratorSession,
    observation: InferenceAdapterObservation
  ) {
    self.session = session
    self.observation = observation
  }

  var isShutdown: Bool {
    shutdownState.withLock { $0 }
  }

  func makeSession(
    requirements: MojoSessionRequirements
  ) throws -> any MojoAcceleratorSession {
    observation.record(requirements: requirements)
    return session
  }

  func shutdown() throws {
    shutdownState.withLock { $0 = true }
    observation.record(lifecycleEvent: "runtime.shutdown")
  }
}

private final class InferenceAcceleratorSession:
  MojoAcceleratorSession, Sendable
{
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

  private let observation: InferenceAdapterObservation
  private let shutdownState = Mutex(false)

  init(
    executionFunctionNames: [String],
    observation: InferenceAdapterObservation
  ) {
    self.executionFunctionNames = executionFunctionNames
    self.observation = observation
  }

  var isShutdown: Bool {
    shutdownState.withLock { $0 }
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
    guard executionFunctionNames.contains(functionName) else {
      throw MojoAcceleratorRuntimeError.unavailableExecutionFunction(
        functionName
      )
    }
    observation.record(functionName: functionName)
    output = [1]
  }

  func shutdown() throws {
    shutdownState.withLock { $0 = true }
    observation.record(lifecycleEvent: "session.shutdown")
  }
}
