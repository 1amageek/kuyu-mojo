import Foundation
import KuyuMojoCore
import KuyuMojoTrainingRuntime
import KuyuTraining
import MojoRuntime
import Testing

@Suite("Mojo training worker bundle preflight")
struct MojoTrainingWorkerBundlePreflightTests {
  @Test(.timeLimit(.minutes(1)))
  func createsAWorkerSourceSeparateFromTheAcceleratorLibrary() throws {
    let rootURL = URL(
      fileURLWithPath: "/tmp/kuyu-mojo-training-worker",
      isDirectory: true
    )
    let adapter = try Self.adapter(
      acceleratorPreflight: StubAcceleratorBundlePreflight()
    )

    let source = try adapter.executableSource(at: rootURL)
    let accelerator = try adapter.validatedAcceleratorRuntime(at: rootURL)

    #expect(source.bundleRootURL == rootURL.standardizedFileURL)
    #expect(source.executableRelativePath == Self.workerRelativePath)
    #expect(
      source.executableURL
        == rootURL.appendingPathComponent(
          Self.workerRelativePath,
          isDirectory: false
        )
    )
    #expect(
      accelerator.rootURL
        == rootURL.appendingPathComponent(
          Self.acceleratorRuntimeRelativePath,
          isDirectory: true
        )
    )
    #expect(source.executableURL != accelerator.libraryURL)
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsLaunchingTheAcceleratorLibraryAsTheWorker() throws {
    let rootURL = URL(
      fileURLWithPath: "/tmp/kuyu-mojo-wrong-worker",
      isDirectory: true
    )
    let adapter = try Self.adapter(
      acceleratorPreflight: StubAcceleratorBundlePreflight()
    )

    #expect(
      throws:
        MojoTrainingWorkerBundlePreflightError
        .workerExecutableRelativePathMismatch(
          expected: Self.workerRelativePath,
          actual: Self.acceleratorRuntimeRelativePath
            + "/"
            + Self.acceleratorLibraryRelativePath
        )
    ) {
      try adapter.verifyBundle(
        at: rootURL,
        executableRelativePath:
          Self.acceleratorRuntimeRelativePath
          + "/"
          + Self.acceleratorLibraryRelativePath
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsAResultForAnotherAcceleratorRuntimeRoot() throws {
    let rootURL = URL(
      fileURLWithPath: "/tmp/kuyu-mojo-runtime-root",
      isDirectory: true
    )
    let actualRoot = URL(
      fileURLWithPath: "/tmp/other-accelerator-runtime",
      isDirectory: true
    )
    let adapter = try Self.adapter(
      acceleratorPreflight: StubAcceleratorBundlePreflight(
        returnedRootURL: actualRoot
      )
    )
    let expectedRoot = rootURL.appendingPathComponent(
      Self.acceleratorRuntimeRelativePath,
      isDirectory: true
    )

    #expect(
      throws:
        MojoTrainingWorkerBundlePreflightError
        .acceleratorRuntimeRootMismatch(
          expected: expectedRoot,
          actual: actualRoot
        )
    ) {
      _ = try adapter.executableSource(at: rootURL)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func rejectsAnAcceleratorLibraryURLThatDisagreesWithItsManifest() throws {
    let rootURL = URL(
      fileURLWithPath: "/tmp/kuyu-mojo-runtime-executable",
      isDirectory: true
    )
    let runtimeRoot = rootURL.appendingPathComponent(
      Self.acceleratorRuntimeRelativePath,
      isDirectory: true
    )
    let actualURL = runtimeRoot.appendingPathComponent(
      "bin/replaced-acceptance",
      isDirectory: false
    )
    let adapter = try Self.adapter(
      acceleratorPreflight: StubAcceleratorBundlePreflight(
        returnedLibraryURL: actualURL
      )
    )
    let expectedURL = runtimeRoot.appendingPathComponent(
      Self.acceleratorLibraryRelativePath,
      isDirectory: false
    )

    #expect(
      throws:
        MojoTrainingWorkerBundlePreflightError
        .acceleratorLibraryURLMismatch(
          expected: expectedURL,
          actual: actualURL
        )
    ) {
      _ = try adapter.executableSource(at: rootURL)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func directRuntimeLookupRejectsANonFileWorkerRoot() throws {
    let rootURL = try #require(
      URL(string: "https://example.com/kuyu-worker")
    )
    let adapter = try Self.adapter(
      acceleratorPreflight: StubAcceleratorBundlePreflight()
    )

    #expect(
      throws: TrainingRunWorkerExecutableSource.ValidationError
        .invalidBundleRoot(rootURL.absoluteString)
    ) {
      _ = try adapter.validatedAcceleratorRuntime(at: rootURL)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func genericLauncherRunsTheWorkerInsteadOfTheAcceleratorLibrary()
    async throws
  {
    let directory = try Self.temporaryDirectory("worker-selection")
    let workerBundleRoot = directory.appendingPathComponent(
      "worker-bundle",
      isDirectory: true
    )
    let workerURL = workerBundleRoot.appendingPathComponent(
      Self.workerRelativePath,
      isDirectory: false
    )
    let acceleratorURL =
      workerBundleRoot
      .appendingPathComponent(
        Self.acceleratorRuntimeRelativePath,
        isDirectory: true
      )
      .appendingPathComponent(
        Self.acceleratorLibraryRelativePath,
        isDirectory: false
      )
    try FileManager.default.createDirectory(
      at: workerURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: acceleratorURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      to: workerURL
    )
    try Data("accelerator-library".utf8).write(to: acceleratorURL)
    let adapter = try Self.adapter(
      acceleratorPreflight: StubAcceleratorBundlePreflight()
    )
    let source = try adapter.executableSource(at: workerBundleRoot)
    let launcher = TrainingRunWorkerProcessLauncher(
      configuration: TrainingRunWorkerProcessConfiguration(
        executableSource: source,
        launchRootDirectory: directory.appendingPathComponent(
          "launches",
          isDirectory: true
        )
      ),
      executableBundlePreflight: adapter
    )
    let handle = try await launcher.launch(
      try Self.launchArtifact(
        in: directory,
        runID: "mojo-worker-selection"
      )
    )

    await #expect {
      _ = try await handle.wait()
    } throws: { error in
      guard
        case TrainingRunWorkerProcessHandle.HandleError
          .missingTerminalOutcome(let status, _) = error
      else {
        return false
      }
      return status == 0
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func genericLauncherStagesAndVerifiesAnOptInRealRuntime() async throws {
    guard
      let runtimePath = ProcessInfo.processInfo.environment[
        "KUYU_MOJO_TEST_ACCELERATOR_LIBRARY_BUNDLE"
      ]
    else {
      return
    }
    let directory = try Self.temporaryDirectory("real-worker-runtime")
    let sourceRoot = try Self.workerBundle(
      in: directory,
      acceleratorRuntimeURL: URL(
        fileURLWithPath: runtimePath,
        isDirectory: true
      )
    )
    let adapter = try Self.adapter(
      requirement: Self.realBundleRequirement()
    )
    let source = try adapter.executableSource(at: sourceRoot)
    let launcher = TrainingRunWorkerProcessLauncher(
      configuration: TrainingRunWorkerProcessConfiguration(
        executableSource: source,
        launchRootDirectory: directory.appendingPathComponent(
          "launches",
          isDirectory: true
        )
      ),
      executableBundlePreflight: adapter
    )
    let handle = try await launcher.launch(
      try Self.launchArtifact(
        in: directory,
        runID: "mojo-real-runtime"
      )
    )

    await #expect {
      _ = try await handle.wait()
    } throws: { error in
      guard
        case TrainingRunWorkerProcessHandle.HandleError
          .missingTerminalOutcome(let status, _) = error
      else {
        return false
      }
      return status == 0
    }
  }

  private static let workerRelativePath = "bin/kuyu-worker"
  private static let acceleratorRuntimeRelativePath =
    "AcceleratorRuntime"
  private static let acceleratorLibraryRelativePath =
    "lib/libSwiftMojo_KuyuAccelerator_ABI.dylib"
  private static let bundleDigest = String(repeating: "a", count: 64)
  private static let receiptDigest = String(repeating: "b", count: 64)
  private static let target = MojoRuntimeBundleTarget(
    triple: "arm64-apple-macosx14.0",
    cpu: "apple-m4",
    accelerator: "apple-gpu"
  )

  private static func adapter(
    requirement: MojoAcceleratorRuntimeBundleRequirement? = nil,
    acceleratorPreflight:
      any MojoAcceleratorRuntimeBundlePreflighting =
      StubAcceleratorBundlePreflight()
  ) throws -> MojoTrainingWorkerBundlePreflight {
    MojoTrainingWorkerBundlePreflight(
      layout: try MojoTrainingWorkerBundleLayout(
        workerExecutableRelativePath: workerRelativePath,
        acceleratorRuntimeRelativePath:
          acceleratorRuntimeRelativePath
      ),
      requirement: try requirement ?? Self.requirement(),
      acceleratorPreflight: acceleratorPreflight
    )
  }

  private static func requirement() throws
    -> MojoAcceleratorRuntimeBundleRequirement
  {
    try MojoAcceleratorRuntimeBundleRequirement(
      bundleDigest: bundleDigest,
      receiptDigest: receiptDigest,
      target: target,
      moduleName: "SwiftMojo_KuyuAccelerator_ABI",
      inputGraphDigest: String(repeating: "c", count: 64),
      inputGraphIdentifier: 42,
      sessionFactoryFunctionName: "createKuyuSession",
      executionFunctionName: "executeKuyuBatch"
    )
  }

  private static func realBundleRequirement() throws
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

  private static func launchArtifact(
    in directory: URL,
    runID: String
  ) throws -> TrainingRunWorkerLaunchArtifact {
    let sourceParent = directory.appendingPathComponent(
      "sources-\(runID)",
      isDirectory: true
    )
    let sourceRoot = sourceParent.appendingPathComponent(
      "model",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: sourceRoot,
      withIntermediateDirectories: true
    )
    try Data("model".utf8).write(
      to: sourceRoot.appendingPathComponent(
        "model.json",
        isDirectory: false
      )
    )
    let modelSource = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [sourceParent]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: "source",
        kind: .source,
        url: sourceRoot
      )
    )
    return TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID(runID),
          artifactRoot: directory.appendingPathComponent(
            "artifacts-\(runID)",
            isDirectory: true
          ),
          taskProfileID: "lift",
          policyContract:
            ReferenceQuadrotorLearningContracts
            .temporalCTBRPolicyContract(),
          actionContract:
            ReferenceQuadrotorLearningContracts
            .bodyRateActionContract(),
          sourceBundle: modelSource
        )
      )
    )
  }

  private static func workerBundle(
    in directory: URL,
    acceleratorRuntimeURL: URL
  ) throws -> URL {
    let root = directory.appendingPathComponent(
      "worker-bundle",
      isDirectory: true
    )
    let workerURL = root.appendingPathComponent(
      workerRelativePath,
      isDirectory: false
    )
    try FileManager.default.createDirectory(
      at: workerURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      to: workerURL
    )
    try FileManager.default.copyItem(
      at: acceleratorRuntimeURL,
      to: root.appendingPathComponent(
        acceleratorRuntimeRelativePath,
        isDirectory: true
      )
    )
    return root
  }

  private static func temporaryDirectory(_ label: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "kuyu-mojo-\(label)-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}
