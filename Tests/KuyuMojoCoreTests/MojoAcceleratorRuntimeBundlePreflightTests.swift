import Foundation
import KuyuMojoCore
import MojoRuntime
import Testing

@Suite("Mojo accelerator runtime library preflight")
struct MojoAcceleratorRuntimeBundlePreflightTests {
  @Test(.timeLimit(.minutes(1)))
  func admitsExactIdentityAndTypedSessionRelationship() throws {
    let verification = Self.verification()
    let rootURL = URL(
      fileURLWithPath: "/tmp/kuyu-accelerator-runtime.bundle",
      isDirectory: true
    )
    let preflight = FileSystemMojoAcceleratorRuntimeBundlePreflight(
      runtimeVerifier: StubLibraryVerifier(.success(verification))
    )

    let bundle = try preflight.validatedRuntimeBundle(
      at: rootURL,
      requiring: Self.requirement()
    )

    #expect(bundle.rootURL == rootURL.standardizedFileURL)
    #expect(
      bundle.libraryURL
        == rootURL.appendingPathComponent(
          Self.libraryRelativePath,
          isDirectory: false
        )
    )
    #expect(bundle.sessionFactoryBinding.bindingID == 11)
    #expect(bundle.executionBinding.bindingID == 12)
    #expect(bundle.verification == verification)
  }

  @Test(.timeLimit(.minutes(1)))
  func admitsMultipleExecutionBindingsInRequiredOrder() throws {
    let secondary = MojoRuntimeLibraryBinding(
      bindingID: 13,
      functionName: Self.secondaryExecutionFunctionName,
      signature: .sessionBorrowedMutableFloat32Buffers,
      sessionFactoryFunctionName: Self.factoryFunctionName
    )
    let verification = Self.verification(
      additionalBindings: [secondary]
    )
    let requirement = try Self.requirement(
      executionFunctionNames: [
        Self.secondaryExecutionFunctionName,
        Self.executionFunctionName,
      ]
    )

    let bundle = try FileSystemMojoAcceleratorRuntimeBundlePreflight(
      runtimeVerifier: StubLibraryVerifier(.success(verification))
    ).validatedRuntimeBundle(
      at: URL(fileURLWithPath: "/tmp/runtime", isDirectory: true),
      requiring: requirement
    )

    #expect(
      bundle.executionBindings.map(\.functionName) == [
        Self.secondaryExecutionFunctionName,
        Self.executionFunctionName,
      ]
    )
    #expect(bundle.executionBindings.map(\.bindingID) == [13, 12])
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsEmptyOrDuplicateExecutionRequirements() throws {
    #expect(
      throws:
        MojoAcceleratorRuntimeBundleRequirement.ValidationError
        .emptyExecutionFunctionNames
    ) {
      _ = try Self.requirement(executionFunctionNames: [])
    }
    #expect(
      throws:
        MojoAcceleratorRuntimeBundleRequirement.ValidationError
        .duplicateExecutionFunctionName(Self.executionFunctionName)
    ) {
      _ = try Self.requirement(
        executionFunctionNames: [
          Self.executionFunctionName,
          Self.executionFunctionName,
        ]
      )
    }

    let verification = Self.verification()
    #expect(
      throws:
        MojoAcceleratorRuntimeBundle.ValidationError
        .emptyExecutionBindings
    ) {
      _ = try MojoAcceleratorRuntimeBundle(
        rootURL: URL(fileURLWithPath: "/tmp/runtime", isDirectory: true),
        libraryURL: URL(fileURLWithPath: "/tmp/runtime/lib/runtime.dylib"),
        sessionFactoryBinding: verification.bindings[0],
        executionBindings: [],
        verification: verification
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsIdentityAndBindingRelationshipDrift() throws {
    let requirement = try Self.requirement()
    let rootURL = URL(fileURLWithPath: "/tmp/runtime", isDirectory: true)
    let mismatches:
      [(
        MojoRuntimeLibraryBundleVerification,
        MojoAcceleratorRuntimeBundlePreflightError
      )] = [
        (
          Self.verification(schemaVersion: 2),
          .schemaVersionMismatch(expected: 3, actual: 2)
        ),
        (
          Self.verification(bundleDigest: Self.otherDigest),
          .bundleDigestMismatch(
            expected: Self.bundleDigest,
            actual: Self.otherDigest
          )
        ),
        (
          Self.verification(inputGraphIdentifier: 99),
          .inputGraphIdentifierMismatch(expected: 42, actual: 99)
        ),
        (
          Self.verification(executionFactoryName: "otherFactory"),
          .executionBindingMismatch(Self.executionFunctionName)
        ),
        (
          Self.verification(libraryRelativePath: "../lib/runtime.dylib"),
          .invalidLibraryRelativePath("../lib/runtime.dylib")
        ),
      ]

    for (verification, expectedError) in mismatches {
      let preflight = FileSystemMojoAcceleratorRuntimeBundlePreflight(
        runtimeVerifier: StubLibraryVerifier(.success(verification))
      )
      #expect(throws: expectedError) {
        _ = try preflight.validatedRuntimeBundle(
          at: rootURL,
          requiring: requirement
        )
      }
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func preservesTypedVerifierFailureAndCancellation() throws {
    let runtimeError = MojoRuntimeBundleVerificationError.invalidBundle(
      "changed managed tree"
    )
    let failing = FileSystemMojoAcceleratorRuntimeBundlePreflight(
      runtimeVerifier: StubLibraryVerifier(.runtimeFailure(runtimeError))
    )
    #expect(
      throws:
        MojoAcceleratorRuntimeBundlePreflightError
        .runtimeVerificationFailed(runtimeError)
    ) {
      _ = try failing.validatedRuntimeBundle(
        at: URL(fileURLWithPath: "/tmp/runtime", isDirectory: true),
        requiring: Self.requirement()
      )
    }

    let cancelled = FileSystemMojoAcceleratorRuntimeBundlePreflight(
      runtimeVerifier: StubLibraryVerifier(.cancellation)
    )
    #expect {
      _ = try cancelled.validatedRuntimeBundle(
        at: URL(fileURLWithPath: "/tmp/runtime", isDirectory: true),
        requiring: Self.requirement()
      )
    } throws: { error in
      error is CancellationError
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func verifiesOptInRealSchemaThreeBundle() throws {
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

    #expect(bundle.verification.schemaVersion == 3)
    #expect(bundle.sessionFactoryBinding.bindingID == 7_011_178_621_006_873_745)
    #expect(bundle.executionBinding.bindingID == 575_865_463_727_937_879)
    #expect(bundle.verification.runtimeLibraries.count == 4)
  }

  private static let bundleDigest = String(repeating: "a", count: 64)
  private static let receiptDigest = String(repeating: "b", count: 64)
  private static let inputGraphDigest = String(repeating: "c", count: 64)
  private static let otherDigest = String(repeating: "d", count: 64)
  private static let moduleName = "SwiftMojo_KuyuAccelerator_ABI"
  private static let factoryFunctionName = "createKuyuSession"
  private static let executionFunctionName = "executeKuyuBatch"
  private static let secondaryExecutionFunctionName = "commitKuyuBatch"
  private static let libraryRelativePath =
    "lib/libSwiftMojo_KuyuAccelerator_ABI.dylib"
  private static let target = MojoRuntimeBundleTarget(
    triple: "arm64-apple-macosx14.0",
    cpu: "apple-m4",
    accelerator: "metal:4"
  )

  private static func requirement() throws
    -> MojoAcceleratorRuntimeBundleRequirement
  {
    try MojoAcceleratorRuntimeBundleRequirement(
      bundleDigest: bundleDigest,
      receiptDigest: receiptDigest,
      target: target,
      moduleName: moduleName,
      inputGraphDigest: inputGraphDigest,
      inputGraphIdentifier: 42,
      sessionFactoryFunctionName: factoryFunctionName,
      executionFunctionName: executionFunctionName
    )
  }

  private static func requirement(
    executionFunctionNames: [String]
  ) throws -> MojoAcceleratorRuntimeBundleRequirement {
    try MojoAcceleratorRuntimeBundleRequirement(
      bundleDigest: bundleDigest,
      receiptDigest: receiptDigest,
      target: target,
      moduleName: moduleName,
      inputGraphDigest: inputGraphDigest,
      inputGraphIdentifier: 42,
      sessionFactoryFunctionName: factoryFunctionName,
      executionFunctionNames: executionFunctionNames
    )
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

  private static func verification(
    schemaVersion: Int = 3,
    bundleDigest: String = bundleDigest,
    inputGraphIdentifier: UInt64 = 42,
    executionFactoryName: String = factoryFunctionName,
    libraryRelativePath: String = libraryRelativePath,
    additionalBindings: [MojoRuntimeLibraryBinding] = []
  ) -> MojoRuntimeLibraryBundleVerification {
    MojoRuntimeLibraryBundleVerification(
      schemaVersion: schemaVersion,
      bundleDigest: bundleDigest,
      receiptDigest: receiptDigest,
      target: target,
      moduleName: moduleName,
      compilerVersion: "Mojo 1.0.0",
      inputGraphDigest: inputGraphDigest,
      inputGraphIdentifier: inputGraphIdentifier,
      generatedSourceDigest: String(repeating: "e", count: 64),
      sourceMapDigest: String(repeating: "f", count: 64),
      bindings: [
        MojoRuntimeLibraryBinding(
          bindingID: 11,
          functionName: factoryFunctionName,
          signature: .runtimeSessionFactory
        ),
        MojoRuntimeLibraryBinding(
          bindingID: 12,
          functionName: executionFunctionName,
          signature: .sessionBorrowedMutableFloat32Buffers,
          sessionFactoryFunctionName: executionFactoryName
        ),
      ] + additionalBindings,
      loaderSearchPath: "@loader_path",
      library: MojoRuntimeBundleFile(
        relativePath: libraryRelativePath,
        sha256Digest: String(repeating: "1", count: 64)
      ),
      runtimeLibraries: [],
      interfaceHeader: MojoRuntimeBundleFile(
        relativePath: "include/\(moduleName).h",
        sha256Digest: String(repeating: "2", count: 64)
      ),
      moduleMap: MojoRuntimeBundleFile(
        relativePath: "include/module.modulemap",
        sha256Digest: String(repeating: "3", count: 64)
      ),
      exportedSymbols: Self.exports,
      systemDependencies: ["/usr/lib/libSystem.B.dylib"]
    )
  }

  private static let exports = [
    "swift_mojo_fixture_static_abi_version",
    "swift_mojo_fixture_input_graph_identifier",
    "swift_mojo_fixture_has_binding",
    "swift_mojo_fixture_create_session_v1",
    "swift_mojo_fixture_shutdown_session_v1",
    "swift_mojo_fixture_call_session_f32_buffer_f32_buffer_i32_v1",
  ]
}

private struct StubLibraryVerifier: MojoRuntimeLibraryBundleVerifying {
  enum Outcome: Sendable {
    case success(MojoRuntimeLibraryBundleVerification)
    case runtimeFailure(MojoRuntimeBundleVerificationError)
    case cancellation
  }

  let outcome: Outcome

  init(_ outcome: Outcome) {
    self.outcome = outcome
  }

  func verifyLibraryBundle(
    at bundleURL: URL
  ) throws -> MojoRuntimeLibraryBundleVerification {
    switch outcome {
    case .success(let verification):
      verification
    case .runtimeFailure(let error):
      throw error
    case .cancellation:
      throw CancellationError()
    }
  }
}
