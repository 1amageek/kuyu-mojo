import Foundation
import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import Mojo
import MojoRuntime
import Testing

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite("Dynamic Mojo accelerator runtime")
struct DynamicMojoAcceleratorRuntimeTests {
  @Test(.timeLimit(.minutes(1)))
  func ownsSessionExecutesRepeatedlyAndShutsDownInOrder() throws {
    try Fixture.withFixture { fixture in
      let runtime = try fixture.load(try fixture.bundle())
      let session = try runtime.makeSession(
        requirements: Fixture.requirements
      )

      var output = [Float](repeating: 0, count: 2)
      try session.execute(request: [41, 42], into: &output)
      #expect(output == [41, 42])
      try session.execute(request: [43, 44], into: &output)
      #expect(output == [43, 44])
      #expect(session.capabilities.satisfies(Fixture.requirements))

      #expect(
        throws: MojoAcceleratorRuntimeError.runtimeLibraryBusy(
          activeSessions: 1,
          activeCreations: 0
        )
      ) {
        try runtime.shutdown()
      }
      try session.shutdown()
      #expect(session.isShutdown)
      try runtime.shutdown()
      #expect(runtime.isShutdown)
      try runtime.shutdown()
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func reportsInvocationFailureAndUseAfterShutdown() throws {
    try Fixture.withFixture { fixture in
      let runtime = try fixture.load(try fixture.bundle())
      let session = try runtime.makeSession(
        requirements: Fixture.requirements
      )
      var output = [Float](repeating: 0, count: 2)

      #expect(
        throws: MojoAcceleratorRuntimeError.invocationFailed(
          status: 20
        )
      ) {
        try session.execute(request: [41], into: &output)
      }
      try session.shutdown()
      #expect(throws: MojoSessionError.shutdown) {
        try session.execute(request: [41, 42], into: &output)
      }
      try runtime.shutdown()
      #expect(throws: MojoAcceleratorRuntimeError.runtimeLibraryShutdown) {
        _ = try runtime.makeSession(
          requirements: Fixture.requirements
        )
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsGraphOrBindingMismatchBeforeCreatingASession() throws {
    try Fixture.withFixture { fixture in
      #expect(
        throws:
          MojoAcceleratorRuntimeError
          .inputGraphIdentifierMismatch(expected: 99, actual: 42)
      ) {
        let bundle = try fixture.bundle(inputGraphIdentifier: 99)
        _ = try fixture.load(bundle)
      }
      #expect(
        throws: MojoAcceleratorRuntimeError.unavailableBinding(99)
      ) {
        let bundle = try fixture.bundle(executionBindingID: 99)
        _ = try fixture.load(bundle)
      }
      #expect(
        throws:
          MojoAcceleratorRuntimeError.runtimeBindingIdentityMismatch
      ) {
        let bundle = try fixture.bundle(
          includeSecondaryExecution: true,
          secondaryExecutionBindingID: Fixture.executionBindingID
        )
        _ = try fixture.load(bundle)
      }
      #expect(
        throws:
          MojoAcceleratorRuntimeError.runtimeBindingIdentityMismatch
      ) {
        let bundle = try fixture.bundle(
          factoryBindingID: Fixture.executionBindingID
        )
        _ = try fixture.load(bundle)
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsUnverifiedOrDriftedMetadataBeforeDynamicLoading() throws {
    try Fixture.withFixture { fixture in
      let bundle = try fixture.bundle()
      let verificationError =
        MojoRuntimeBundleVerificationError
        .invalidBundle("fixture verification failed")
      #expect(
        throws: MojoAcceleratorRuntimeError.runtimeVerificationFailed(
          verificationError
        )
      ) {
        _ = try DynamicMojoAcceleratorRuntimeLoader(
          runtimeVerifier: FixtureRuntimeVerifier(
            outcome: .failure(verificationError)
          )
        ).load(bundle)
      }

      #expect(
        throws: MojoAcceleratorRuntimeError
          .runtimeVerificationIdentityMismatch
      ) {
        _ = try DynamicMojoAcceleratorRuntimeLoader(
          runtimeVerifier: FixtureRuntimeVerifier(
            outcome: .success(
              try fixture.bundle(inputGraphIdentifier: 99).verification
            )
          )
        ).load(bundle)
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsShutdownAndReentryAcrossConcurrentForeignCalls() async throws {
    try await Fixture.withAsyncFixture { fixture in
      let controls = try FixtureControls(libraryURL: fixture.libraryURL)
      let runtime = try fixture.load(
        try fixture.bundle(includeSecondaryExecution: true)
      )

      controls.blockNextCreation()
      let creation = Task {
        try runtime.makeSession(requirements: Fixture.requirements)
      }
      defer { controls.releaseCreation() }
      try await controls.waitForCreationEntry()
      #expect(
        throws: MojoAcceleratorRuntimeError.runtimeLibraryBusy(
          activeSessions: 0,
          activeCreations: 1
        )
      ) {
        try runtime.shutdown()
      }
      controls.releaseCreation()
      let session = try await creation.value

      controls.blockNextInvocation()
      let invocation = Task<[Float], Error> {
        var output = [Float](repeating: 0, count: 2)
        try session.execute(
          functionName: Fixture.secondaryExecutionFunctionName,
          request: [51, 52],
          into: &output
        )
        return output
      }
      defer { controls.releaseInvocation() }
      try await controls.waitForInvocationEntry()
      var competingOutput = [Float](repeating: 0, count: 2)
      #expect(throws: MojoSessionError.busy) {
        try session.execute(
          request: [61, 62],
          into: &competingOutput
        )
      }
      #expect(throws: MojoSessionError.busy) {
        try session.shutdown()
      }
      controls.releaseInvocation()
      #expect(try await invocation.value == [52, 53])

      try controls.shutdown()
      try session.shutdown()
      try runtime.shutdown()
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func routesNamedExecutionBindingsWithoutFallback() throws {
    try Fixture.withFixture { fixture in
      let runtime = try fixture.load(
        try fixture.bundle(includeSecondaryExecution: true)
      )
      let session = try runtime.makeSession(
        requirements: Fixture.requirements
      )

      #expect(
        session.executionFunctionNames == [
          "executeBatch",
          Fixture.secondaryExecutionFunctionName,
        ]
      )
      var output = [Float](repeating: 0, count: 2)
      try session.execute(request: [41, 42], into: &output)
      #expect(output == [41, 42])
      try session.execute(
        functionName: Fixture.secondaryExecutionFunctionName,
        request: [41, 42],
        into: &output
      )
      #expect(output == [42, 43])

      #expect(
        throws:
          MojoAcceleratorRuntimeError
          .unavailableExecutionFunction("missingExecution")
      ) {
        try session.execute(
          functionName: "missingExecution",
          request: [51, 52],
          into: &output
        )
      }
      #expect(output == [42, 43])

      try session.shutdown()
      try runtime.shutdown()
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func executesOptInRealMetalBundleThroughTypedLoader() throws {
    guard
      let bundlePath = ProcessInfo.processInfo.environment[
        "KUYU_MOJO_TEST_ACCELERATOR_LIBRARY_BUNDLE"
      ]
    else {
      return
    }
    let bundle = try FileSystemMojoAcceleratorRuntimeBundlePreflight()
      .validatedRuntimeBundle(
        at: URL(fileURLWithPath: bundlePath, isDirectory: true),
        requiring: try Self.realRequirement()
      )
    let runtime = try DynamicMojoAcceleratorRuntimeLoader().load(bundle)
    let session = try runtime.makeSession(
      requirements: Fixture.requirements
    )
    var request: [Float] = [
      4_937_050, 1, 2, 8, 1, 1,
      4_937_049, 1, 0, 1, 1, 16, 8, 8,
      41, 42,
    ]
    var output = [Float](repeating: 0, count: 2)

    try session.execute(request: request, into: &output)
    #expect(output == [41, 42])
    request[14] = 43
    request[15] = 44
    try session.execute(request: request, into: &output)
    #expect(output == [43, 44])

    try session.shutdown()
    try runtime.shutdown()
  }

  private static func realRequirement() throws
    -> MojoAcceleratorRuntimeBundleRequirement
  {
    try MojoAcceleratorRuntimeBundleRequirement(
      bundleDigest:
        "2e89bda4bc15fb935f5df9cb1a43f029336653ef095bea62d60076dbb3d84f99",
      receiptDigest:
        "3969ad6b6d12dd2416aa745bdc4037ad2faba85bd24b34d0abd3d5eb1c8be747",
      target: MojoRuntimeBundleTarget(
        triple: "arm64-apple-macosx14.0",
        cpu: "apple-m4",
        accelerator: "metal:4"
      ),
      moduleName: "SwiftMojo_KuyuMojoAcceleratorSession_ABI",
      inputGraphDigest:
        "d35ef968310c16a37cabbc86e05d9e969cd6370f39b554227d8b6dbae61b6c6e",
      inputGraphIdentifier: 6_007_513_178_853_611_171,
      sessionFactoryFunctionName: "createKuyuMojoAcceleratorSession",
      executionFunctionName: "executeKuyuMojoAcceleratorBatch"
    )
  }
}

private struct Fixture {
  static let factoryBindingID: UInt64 = 11
  static let executionBindingID: UInt64 = 12
  static let secondaryExecutionBindingID: UInt64 = 13
  static let secondaryExecutionFunctionName = "executeShiftedBatch"
  static let graphIdentifier: UInt64 = 42
  static let requirements = MojoSessionRequirements(
    device: .metal,
    requiredCapabilities: [
      .synchronousInvocation,
      .deviceMemory,
      .hostPinnedMemory,
      .float32,
    ]
  )

  let rootURL: URL
  let libraryURL: URL

  static func withFixture(
    _ operation: (Fixture) throws -> Void
  ) throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kuyu-mojo-dynamic-runtime-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: false
    )
    defer {
      do {
        try FileManager.default.removeItem(at: rootURL)
      } catch {
        Issue.record("Fixture cleanup failed: \(error)")
      }
    }

    let sourceURL = rootURL.appendingPathComponent("fixture.c")
    let libraryURL = rootURL.appendingPathComponent("libFixture.dylib")
    try Self.source.write(
      to: sourceURL,
      atomically: true,
      encoding: .utf8
    )
    try Self.compile(sourceURL: sourceURL, libraryURL: libraryURL)
    try operation(Fixture(rootURL: rootURL, libraryURL: libraryURL))
  }

  static func withAsyncFixture<Result>(
    _ operation: (Fixture) async throws -> Result
  ) async throws -> Result {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kuyu-mojo-dynamic-runtime-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: false
    )
    defer {
      do {
        try FileManager.default.removeItem(at: rootURL)
      } catch {
        Issue.record("Fixture cleanup failed: \(error)")
      }
    }

    let sourceURL = rootURL.appendingPathComponent("fixture.c")
    let libraryURL = rootURL.appendingPathComponent("libFixture.dylib")
    try Self.source.write(
      to: sourceURL,
      atomically: true,
      encoding: .utf8
    )
    try Self.compile(sourceURL: sourceURL, libraryURL: libraryURL)
    return try await operation(
      Fixture(rootURL: rootURL, libraryURL: libraryURL)
    )
  }

  func bundle(
    inputGraphIdentifier: UInt64 = graphIdentifier,
    factoryBindingID: UInt64 = factoryBindingID,
    executionBindingID: UInt64 = executionBindingID,
    includeSecondaryExecution: Bool = false,
    secondaryExecutionBindingID: UInt64 = secondaryExecutionBindingID
  ) throws -> MojoAcceleratorRuntimeBundle {
    let factory = MojoRuntimeLibraryBinding(
      bindingID: factoryBindingID,
      functionName: "createSession",
      signature: .runtimeSessionFactory
    )
    let execution = MojoRuntimeLibraryBinding(
      bindingID: executionBindingID,
      functionName: "executeBatch",
      signature: .sessionBorrowedMutableFloat32Buffers,
      sessionFactoryFunctionName: "createSession"
    )
    var executions = [execution]
    if includeSecondaryExecution {
      executions.append(
        MojoRuntimeLibraryBinding(
          bindingID: secondaryExecutionBindingID,
          functionName: Self.secondaryExecutionFunctionName,
          signature: .sessionBorrowedMutableFloat32Buffers,
          sessionFactoryFunctionName: "createSession"
        )
      )
    }
    let verification = MojoRuntimeLibraryBundleVerification(
      schemaVersion: 3,
      bundleDigest: String(repeating: "a", count: 64),
      receiptDigest: String(repeating: "b", count: 64),
      target: MojoRuntimeBundleTarget(
        triple: "arm64-apple-macosx14.0",
        cpu: "apple-m4",
        accelerator: "metal:4"
      ),
      moduleName: "Fixture",
      compilerVersion: "Fixture",
      inputGraphDigest: String(repeating: "c", count: 64),
      inputGraphIdentifier: inputGraphIdentifier,
      generatedSourceDigest: String(repeating: "d", count: 64),
      sourceMapDigest: String(repeating: "e", count: 64),
      bindings: [factory] + executions,
      loaderSearchPath: "@loader_path",
      library: MojoRuntimeBundleFile(
        relativePath: libraryURL.lastPathComponent,
        sha256Digest: String(repeating: "f", count: 64)
      ),
      runtimeLibraries: [],
      interfaceHeader: MojoRuntimeBundleFile(
        relativePath: "include/Fixture.h",
        sha256Digest: String(repeating: "1", count: 64)
      ),
      moduleMap: MojoRuntimeBundleFile(
        relativePath: "include/module.modulemap",
        sha256Digest: String(repeating: "2", count: 64)
      ),
      exportedSymbols: Self.exports,
      systemDependencies: ["/usr/lib/libSystem.B.dylib"]
    )
    return try MojoAcceleratorRuntimeBundle(
      rootURL: rootURL,
      libraryURL: libraryURL,
      sessionFactoryBinding: factory,
      executionBindings: executions,
      verification: verification
    )
  }

  func load(
    _ bundle: MojoAcceleratorRuntimeBundle
  ) throws -> any MojoAcceleratorRuntimeLibrary {
    try DynamicMojoAcceleratorRuntimeLoader(
      runtimeVerifier: FixtureRuntimeVerifier(
        outcome: .success(bundle.verification)
      )
    ).load(bundle)
  }

  private static func compile(sourceURL: URL, libraryURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
    process.arguments = [
      "-dynamiclib",
      "-arch", "arm64",
      "-o", libraryURL.path,
      sourceURL.path,
    ]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let diagnostic = String(
        decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      )
      throw FixtureError.compilationFailed(diagnostic)
    }
  }

  private static let exports = [
    "swift_mojo_fixture_static_abi_version",
    "swift_mojo_fixture_input_graph_identifier",
    "swift_mojo_fixture_has_binding",
    "swift_mojo_fixture_create_session_v1",
    "swift_mojo_fixture_shutdown_session_v1",
    "swift_mojo_fixture_call_session_f32_buffer_f32_buffer_i32_v1",
  ]

  private static let source = """
    #include <stdint.h>
    #include <stdatomic.h>
    #include <stdlib.h>
    #include <unistd.h>

    static _Atomic uint32_t block_creation = 0;
    static _Atomic uint32_t creation_entered = 0;
    static _Atomic uint32_t release_creation = 0;
    static _Atomic uint32_t block_invocation = 0;
    static _Atomic uint32_t invocation_entered = 0;
    static _Atomic uint32_t release_invocation = 0;

    void fixture_block_next_creation(void) {
        atomic_store(&creation_entered, 0);
        atomic_store(&release_creation, 0);
        atomic_store(&block_creation, 1);
    }

    uint32_t fixture_creation_entered(void) {
        return atomic_load(&creation_entered);
    }

    void fixture_release_creation(void) {
        atomic_store(&release_creation, 1);
    }

    void fixture_block_next_invocation(void) {
        atomic_store(&invocation_entered, 0);
        atomic_store(&release_invocation, 0);
        atomic_store(&block_invocation, 1);
    }

    uint32_t fixture_invocation_entered(void) {
        return atomic_load(&invocation_entered);
    }

    void fixture_release_invocation(void) {
        atomic_store(&release_invocation, 1);
    }

    typedef struct FixtureSession {
        uint32_t marker;
    } FixtureSession;

    uint32_t swift_mojo_fixture_static_abi_version(void) {
        return 1;
    }

    uint64_t swift_mojo_fixture_input_graph_identifier(void) {
        return 42;
    }

    uint32_t swift_mojo_fixture_has_binding(uint64_t binding_id) {
        return binding_id == 11 || binding_id == 12 || binding_id == 13;
    }

    int32_t swift_mojo_fixture_create_session_v1(
        uint64_t binding_id,
        uint32_t request_schema,
        uint32_t requested_device,
        uint32_t requested_ordinal,
        uint64_t required_capabilities,
        void **session_out,
        uint32_t *response_schema_out,
        uint32_t *actual_device_out,
        uint32_t *actual_ordinal_out,
        uint64_t *available_capabilities_out
    ) {
        if (binding_id != 11 || request_schema != 1
            || requested_device != 1 || requested_ordinal != 0
            || (required_capabilities & 29) != 29) {
            return 14;
        }
        if (atomic_exchange(&block_creation, 0) == 1) {
            atomic_store(&creation_entered, 1);
            while (atomic_load(&release_creation) == 0) {
                usleep(1000);
            }
        }
        FixtureSession *session = malloc(sizeof(FixtureSession));
        if (session == NULL) {
            return 15;
        }
        session->marker = 4937050;
        *session_out = session;
        *response_schema_out = 1;
        *actual_device_out = 1;
        *actual_ordinal_out = 0;
        *available_capabilities_out = 29;
        return 0;
    }

    void swift_mojo_fixture_shutdown_session_v1(
        uint64_t binding_id,
        void *session
    ) {
        if (binding_id == 11) {
            free(session);
        }
    }

    int32_t swift_mojo_fixture_call_session_f32_buffer_f32_buffer_i32_v1(
        uint64_t binding_id,
        void *session,
        const float *input,
        uint64_t input_count,
        float *output,
        uint64_t output_count
    ) {
        FixtureSession *typed_session = session;
        if ((binding_id != 12 && binding_id != 13) || typed_session == NULL
            || typed_session->marker != 4937050
            || input_count != output_count) {
            return 20;
        }
        if (atomic_exchange(&block_invocation, 0) == 1) {
            atomic_store(&invocation_entered, 1);
            while (atomic_load(&release_invocation) == 0) {
                usleep(1000);
            }
        }
        for (uint64_t index = 0; index < input_count; ++index) {
            output[index] = input[index] + (binding_id == 13 ? 1.0f : 0.0f);
        }
        return 0;
    }
    """
}

private struct FixtureRuntimeVerifier: MojoRuntimeLibraryBundleVerifying {
  enum Outcome: Sendable {
    case success(MojoRuntimeLibraryBundleVerification)
    case failure(MojoRuntimeBundleVerificationError)
  }

  let outcome: Outcome

  func verifyLibraryBundle(
    at bundleURL: URL
  ) throws -> MojoRuntimeLibraryBundleVerification {
    switch outcome {
    case .success(let verification):
      return verification
    case .failure(let error):
      throw error
    }
  }
}

private final class FixtureControls {
  private typealias FlagSetter = @convention(c) () -> Void
  private typealias FlagReader = @convention(c) () -> UInt32

  private var handle: UnsafeMutableRawPointer?
  private let blockCreation: FlagSetter
  private let creationEntered: FlagReader
  private let releaseCreationFunction: FlagSetter
  private let blockInvocation: FlagSetter
  private let invocationEntered: FlagReader
  private let releaseInvocationFunction: FlagSetter

  init(libraryURL: URL) throws {
    guard
      let handle = libraryURL.path.withCString({
        dlopen($0, RTLD_NOW | RTLD_LOCAL)
      })
    else {
      throw FixtureError.dynamicLibraryOpenFailed(libraryURL.path)
    }
    do {
      self.blockCreation = try Self.function(
        handle: handle,
        name: "fixture_block_next_creation",
        as: FlagSetter.self
      )
      self.creationEntered = try Self.function(
        handle: handle,
        name: "fixture_creation_entered",
        as: FlagReader.self
      )
      self.releaseCreationFunction = try Self.function(
        handle: handle,
        name: "fixture_release_creation",
        as: FlagSetter.self
      )
      self.blockInvocation = try Self.function(
        handle: handle,
        name: "fixture_block_next_invocation",
        as: FlagSetter.self
      )
      self.invocationEntered = try Self.function(
        handle: handle,
        name: "fixture_invocation_entered",
        as: FlagReader.self
      )
      self.releaseInvocationFunction = try Self.function(
        handle: handle,
        name: "fixture_release_invocation",
        as: FlagSetter.self
      )
      self.handle = handle
    } catch {
      _ = dlclose(handle)
      throw error
    }
  }

  func blockNextCreation() {
    blockCreation()
  }

  func releaseCreation() {
    guard handle != nil else {
      return
    }
    releaseCreationFunction()
  }

  func waitForCreationEntry() async throws {
    try await waitUntilSet(creationEntered)
  }

  func blockNextInvocation() {
    blockInvocation()
  }

  func releaseInvocation() {
    guard handle != nil else {
      return
    }
    releaseInvocationFunction()
  }

  func waitForInvocationEntry() async throws {
    try await waitUntilSet(invocationEntered)
  }

  func shutdown() throws {
    guard let handle else {
      return
    }
    releaseCreationFunction()
    releaseInvocationFunction()
    self.handle = nil
    guard dlclose(handle) == 0 else {
      throw FixtureError.dynamicLibraryCloseFailed
    }
  }

  private func waitUntilSet(_ read: FlagReader) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while read() == 0 {
      guard clock.now < deadline else {
        throw FixtureError.controlTimeout
      }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  private static func function<Function>(
    handle: UnsafeMutableRawPointer,
    name: String,
    as type: Function.Type
  ) throws -> Function {
    guard let symbol = name.withCString({ dlsym(handle, $0) }) else {
      throw FixtureError.dynamicSymbolMissing(name)
    }
    // The functions are test-only C controls whose declarations and image
    // lifetime are owned by this fixture instance.
    return unsafeBitCast(symbol, to: type)
  }

  deinit {
    if let handle {
      releaseCreationFunction()
      releaseInvocationFunction()
      precondition(dlclose(handle) == 0)
    }
  }
}

private enum FixtureError: Error {
  case compilationFailed(String)
  case dynamicLibraryOpenFailed(String)
  case dynamicLibraryCloseFailed
  case dynamicSymbolMissing(String)
  case controlTimeout
}
