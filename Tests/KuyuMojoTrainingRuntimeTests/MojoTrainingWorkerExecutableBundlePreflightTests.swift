import Foundation
import KuyuMojoCore
import KuyuMojoTrainingRuntime
import KuyuTraining
import MojoRuntime
import Testing

@Suite("Mojo training worker executable bundle preflight")
struct MojoTrainingWorkerExecutableBundlePreflightTests {
    @Test(.timeLimit(.minutes(1)))
    func createsTheGenericExecutableSourceFromTheVerifiedBundle() throws {
        let rootURL = URL(
            fileURLWithPath: "/tmp/kuyu-mojo-training-worker",
            isDirectory: true
        )
        let adapter = MojoTrainingWorkerExecutableBundlePreflight(
            requirement: try Self.requirement(),
            preflight: StubAcceleratorBundlePreflight(
                bundle: Self.bundle(rootURL: rootURL)
            )
        )

        let source = try adapter.executableSource(at: rootURL)

        #expect(source.bundleRootURL == rootURL.standardizedFileURL)
        #expect(source.executableRelativePath == Self.executableRelativePath)
        #expect(
            source.executableURL
                == rootURL.appendingPathComponent(
                    Self.executableRelativePath,
                    isDirectory: false
                )
        )
        try adapter.verifyBundle(
            at: rootURL,
            executableRelativePath: Self.executableRelativePath
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAResultForAnotherBundleRoot() throws {
        let requestedRoot = URL(
            fileURLWithPath: "/tmp/requested-worker",
            isDirectory: true
        )
        let actualRoot = URL(
            fileURLWithPath: "/tmp/other-worker",
            isDirectory: true
        )
        let adapter = MojoTrainingWorkerExecutableBundlePreflight(
            requirement: try Self.requirement(),
            preflight: StubAcceleratorBundlePreflight(
                bundle: Self.bundle(rootURL: actualRoot)
            )
        )

        #expect(
            throws: MojoTrainingWorkerExecutableBundlePreflightError
                .rootMismatch(
                    expected: requestedRoot,
                    actual: actualRoot
                )
        ) {
            _ = try adapter.executableSource(at: requestedRoot)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAChangedExecutableRelativePath() throws {
        let rootURL = URL(
            fileURLWithPath: "/tmp/kuyu-mojo-relative-path",
            isDirectory: true
        )
        let adapter = MojoTrainingWorkerExecutableBundlePreflight(
            requirement: try Self.requirement(),
            preflight: StubAcceleratorBundlePreflight(
                bundle: Self.bundle(rootURL: rootURL)
            )
        )

        #expect(
            throws: MojoTrainingWorkerExecutableBundlePreflightError
                .executableRelativePathMismatch(
                    expected: "bin/replaced-worker",
                    actual: Self.executableRelativePath
                )
        ) {
            try adapter.verifyBundle(
                at: rootURL,
                executableRelativePath: "bin/replaced-worker"
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAnExecutableURLThatDisagreesWithTheManifest() throws {
        let rootURL = URL(
            fileURLWithPath: "/tmp/kuyu-mojo-executable-url",
            isDirectory: true
        )
        let actualURL = rootURL.appendingPathComponent(
            "bin/replaced-worker",
            isDirectory: false
        )
        let adapter = MojoTrainingWorkerExecutableBundlePreflight(
            requirement: try Self.requirement(),
            preflight: StubAcceleratorBundlePreflight(
                bundle: Self.bundle(
                    rootURL: rootURL,
                    executableURL: actualURL
                )
            )
        )
        let expectedURL = rootURL.appendingPathComponent(
            Self.executableRelativePath,
            isDirectory: false
        )

        #expect(
            throws: MojoTrainingWorkerExecutableBundlePreflightError
                .executableURLMismatch(
                    expected: expectedURL,
                    actual: actualURL
                )
        ) {
            _ = try adapter.executableSource(at: rootURL)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func verifiesAnOptInRealBundleBeforeAndAfterRelocation() throws {
        guard let bundlePath = ProcessInfo.processInfo.environment[
            "KUYU_MOJO_TEST_ACCELERATOR_BUNDLE"
        ] else {
            return
        }
        let sourceRoot = URL(
            fileURLWithPath: bundlePath,
            isDirectory: true
        )
        let adapter = MojoTrainingWorkerExecutableBundlePreflight(
            requirement: try Self.realBundleRequirement()
        )
        let source = try adapter.executableSource(at: sourceRoot)
        let relocatedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "kuyu-mojo-relocated-worker-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.copyItem(at: sourceRoot, to: relocatedRoot)
        try adapter.verifyBundle(
            at: relocatedRoot,
            executableRelativePath: try #require(
                source.executableRelativePath
            )
        )
    }

    private static let executableRelativePath = "bin/kuyu-mojo-worker"
    private static let bundleDigest = String(repeating: "a", count: 64)
    private static let receiptDigest = String(repeating: "b", count: 64)
    private static let target = MojoRuntimeBundleTarget(
        triple: "arm64-apple-macosx14.0",
        cpu: "apple-m4",
        accelerator: "apple-gpu"
    )

    private static func requirement() throws
        -> MojoAcceleratorWorkerBundleRequirement
    {
        try MojoAcceleratorWorkerBundleRequirement(
            bundleDigest: bundleDigest,
            receiptDigest: receiptDigest,
            target: target
        )
    }

    private static func realBundleRequirement() throws
        -> MojoAcceleratorWorkerBundleRequirement
    {
        try MojoAcceleratorWorkerBundleRequirement(
            bundleDigest:
                "38075467012f877bb5ea23daf3d4639aa175b478bfaca898706bd33e1ff72e77",
            receiptDigest:
                "050ceac20bc593aed6e36757c050e01a0f0ec7d002bcebb49f3675d77ba4e179",
            target: MojoRuntimeBundleTarget(
                triple: "arm64-apple-macosx14.0",
                cpu: "apple-m4",
                accelerator: "apple-gpu"
            )
        )
    }

    private static func bundle(
        rootURL: URL,
        executableURL: URL? = nil
    ) -> MojoAcceleratorWorkerBundle {
        MojoAcceleratorWorkerBundle(
            rootURL: rootURL,
            executableURL: executableURL
                ?? rootURL.appendingPathComponent(
                    executableRelativePath,
                    isDirectory: false
                ),
            verification: MojoRuntimeBundleVerification(
                schemaVersion: 1,
                bundleDigest: bundleDigest,
                receiptDigest: receiptDigest,
                target: target,
                loaderSearchPath: "@executable_path/../lib",
                programInterpreter: nil,
                executable: MojoRuntimeBundleFile(
                    relativePath: executableRelativePath,
                    sha256Digest: String(repeating: "c", count: 64)
                ),
                libraries: [],
                systemDependencies: ["/usr/lib/libSystem.B.dylib"]
            )
        )
    }
}

private struct StubAcceleratorBundlePreflight:
    MojoAcceleratorWorkerBundlePreflighting
{
    let bundle: MojoAcceleratorWorkerBundle

    func validatedBundle(
        at bundleURL: URL,
        requiring requirement: MojoAcceleratorWorkerBundleRequirement
    ) throws -> MojoAcceleratorWorkerBundle {
        bundle
    }
}
