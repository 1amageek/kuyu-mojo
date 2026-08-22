import Foundation
import KuyuMojoCore
import MojoRuntime
import Testing

@Suite("Mojo accelerator worker bundle preflight")
struct MojoAcceleratorWorkerBundlePreflightTests {
    @Test(.timeLimit(.minutes(1)))
    func acceptsOnlyTheExactDeclaredBundleIdentity() throws {
        let verification = Self.verification()
        let preflight = FileSystemMojoAcceleratorWorkerBundlePreflight(
            runtimeVerifier: StubRuntimeVerifier(.success(verification))
        )
        let rootURL = URL(
            fileURLWithPath: "/tmp/kuyu-accelerator-worker.bundle",
            isDirectory: true
        )

        let bundle = try preflight.validatedBundle(
            at: rootURL,
            requiring: Self.requirement()
        )

        #expect(bundle.rootURL == rootURL.standardizedFileURL)
        #expect(
            bundle.executableURL
                == rootURL.appendingPathComponent(
                    "bin/kuyu-mojo-worker",
                    isDirectory: false
                )
        )
        #expect(bundle.verification == verification)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsEveryIdentityMismatchAsATypedFailure() throws {
        let requirement = try Self.requirement()
        let rootURL = URL(fileURLWithPath: "/tmp/runtime", isDirectory: true)
        let cases: [(
            MojoRuntimeBundleVerification,
            MojoAcceleratorWorkerBundlePreflightError
        )] = [
            (
                Self.verification(schemaVersion: 2),
                .schemaVersionMismatch(expected: 1, actual: 2)
            ),
            (
                Self.verification(bundleDigest: Self.otherDigest),
                .bundleDigestMismatch(
                    expected: Self.bundleDigest,
                    actual: Self.otherDigest
                )
            ),
            (
                Self.verification(receiptDigest: Self.otherDigest),
                .receiptDigestMismatch(
                    expected: Self.receiptDigest,
                    actual: Self.otherDigest
                )
            ),
            (
                Self.verification(
                    target: MojoRuntimeBundleTarget(
                        triple: "aarch64-unknown-linux-gnu",
                        cpu: "cortex-a78ae",
                        accelerator: "sm_87"
                    )
                ),
                .targetMismatch(
                    expected: Self.target,
                    actual: MojoRuntimeBundleTarget(
                        triple: "aarch64-unknown-linux-gnu",
                        cpu: "cortex-a78ae",
                        accelerator: "sm_87"
                    )
                )
            ),
        ]

        for (verification, expectedError) in cases {
            let preflight = FileSystemMojoAcceleratorWorkerBundlePreflight(
                runtimeVerifier: StubRuntimeVerifier(.success(verification))
            )
            #expect(throws: expectedError) {
                _ = try preflight.validatedBundle(
                    at: rootURL,
                    requiring: requirement
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsUnsafeExecutablePathsEvenFromInjectedVerifiers() throws {
        let verification = Self.verification(
            executableRelativePath: "../bin/kuyu-mojo-worker"
        )
        let preflight = FileSystemMojoAcceleratorWorkerBundlePreflight(
            runtimeVerifier: StubRuntimeVerifier(.success(verification))
        )

        #expect(
            throws: MojoAcceleratorWorkerBundlePreflightError
                .invalidExecutableRelativePath(
                    "../bin/kuyu-mojo-worker"
                )
        ) {
            _ = try preflight.validatedBundle(
                at: URL(fileURLWithPath: "/tmp/runtime", isDirectory: true),
                requiring: Self.requirement()
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesRuntimeVerificationFailures() throws {
        let runtimeError = MojoRuntimeBundleVerificationError.invalidBundle(
            "changed managed tree"
        )
        let preflight = FileSystemMojoAcceleratorWorkerBundlePreflight(
            runtimeVerifier: StubRuntimeVerifier(.runtimeFailure(runtimeError))
        )

        #expect(
            throws: MojoAcceleratorWorkerBundlePreflightError
                .runtimeVerificationFailed(runtimeError)
        ) {
            _ = try preflight.validatedBundle(
                at: URL(fileURLWithPath: "/tmp/runtime", isDirectory: true),
                requiring: Self.requirement()
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesCancellation() throws {
        let preflight = FileSystemMojoAcceleratorWorkerBundlePreflight(
            runtimeVerifier: StubRuntimeVerifier(.cancellation)
        )

        #expect {
            _ = try preflight.validatedBundle(
                at: URL(fileURLWithPath: "/tmp/runtime", isDirectory: true),
                requiring: Self.requirement()
            )
        } throws: { error in
            error is CancellationError
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsInvalidRequirementsAndNonFileRoots() throws {
        #expect(
            throws: MojoAcceleratorWorkerBundleRequirement.ValidationError
                .invalidBundleDigest(String(repeating: "A", count: 64))
        ) {
            _ = try MojoAcceleratorWorkerBundleRequirement(
                bundleDigest: String(repeating: "A", count: 64),
                receiptDigest: Self.receiptDigest,
                target: Self.target
            )
        }
        let missingAcceleratorTarget = MojoRuntimeBundleTarget(
            triple: "arm64-apple-macosx14.0",
            cpu: "apple-m4",
            accelerator: nil
        )
        #expect(
            throws: MojoAcceleratorWorkerBundleRequirement.ValidationError
                .missingAccelerator(missingAcceleratorTarget)
        ) {
            _ = try MojoAcceleratorWorkerBundleRequirement(
                bundleDigest: Self.bundleDigest,
                receiptDigest: Self.receiptDigest,
                target: missingAcceleratorTarget
            )
        }
        #expect(
            throws: MojoAcceleratorWorkerBundleRequirement.ValidationError
                .invalidTargetCPU("")
        ) {
            _ = try MojoAcceleratorWorkerBundleRequirement(
                bundleDigest: Self.bundleDigest,
                receiptDigest: Self.receiptDigest,
                target: MojoRuntimeBundleTarget(
                    triple: "arm64-apple-macosx14.0",
                    cpu: "",
                    accelerator: "apple-gpu"
                )
            )
        }

        let remoteURL = try #require(URL(string: "https://example.invalid"))
        let preflight = FileSystemMojoAcceleratorWorkerBundlePreflight(
            runtimeVerifier: StubRuntimeVerifier(
                .unexpectedFailure("must not be called")
            )
        )
        #expect(
            throws: MojoAcceleratorWorkerBundlePreflightError
                .nonFileBundleURL(remoteURL)
        ) {
            _ = try preflight.validatedBundle(
                at: remoteURL,
                requiring: Self.requirement()
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func verifiesOptInRealBundleThroughKuyuPreflight() throws {
        guard let bundlePath = ProcessInfo.processInfo.environment[
            "KUYU_MOJO_TEST_ACCELERATOR_BUNDLE"
        ] else {
            return
        }

        let bundle = try FileSystemMojoAcceleratorWorkerBundlePreflight()
            .validatedBundle(
                at: URL(fileURLWithPath: bundlePath, isDirectory: true),
                requiring: Self.realBundleRequirement()
            )

        #expect(
            bundle.executableURL.lastPathComponent
                == "kuyu-mojo-metal-canonical"
        )
        #expect(bundle.verification.libraries.count == 4)
    }

    private static let bundleDigest = String(repeating: "a", count: 64)
    private static let receiptDigest = String(repeating: "b", count: 64)
    private static let otherDigest = String(repeating: "c", count: 64)
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
                "0159c5a65dc14324bcbb5c09b2208857feb242d431df79a420d578d6a8837303",
            receiptDigest:
                "5e3ea40d3236289a757e6d063cbe8a2f8bde406cb82537c8338610b81283a6ab",
            target: MojoRuntimeBundleTarget(
                triple: "arm64-apple-macosx14.0",
                cpu: "apple-m4",
                accelerator: "metal:4"
            )
        )
    }

    private static func verification(
        schemaVersion: Int = 1,
        bundleDigest: String = bundleDigest,
        receiptDigest: String = receiptDigest,
        target: MojoRuntimeBundleTarget = target,
        executableRelativePath: String = "bin/kuyu-mojo-worker"
    ) -> MojoRuntimeBundleVerification {
        MojoRuntimeBundleVerification(
            schemaVersion: schemaVersion,
            bundleDigest: bundleDigest,
            receiptDigest: receiptDigest,
            target: target,
            loaderSearchPath: "@executable_path/../lib",
            programInterpreter: nil,
            executable: MojoRuntimeBundleFile(
                relativePath: executableRelativePath,
                sha256Digest: String(repeating: "d", count: 64)
            ),
            libraries: [
                MojoRuntimeBundleFile(
                    relativePath: "lib/libRuntime.dylib",
                    sha256Digest: String(repeating: "e", count: 64)
                ),
            ],
            systemDependencies: ["/usr/lib/libSystem.B.dylib"]
        )
    }
}

private struct StubRuntimeVerifier: MojoRuntimeBundleVerifying {
    enum Outcome: Sendable {
        case success(MojoRuntimeBundleVerification)
        case runtimeFailure(MojoRuntimeBundleVerificationError)
        case unexpectedFailure(String)
        case cancellation
    }

    let outcome: Outcome

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func verifyBundle(at bundleURL: URL) throws
        -> MojoRuntimeBundleVerification
    {
        switch outcome {
        case .success(let verification):
            verification
        case .runtimeFailure(let error):
            throw error
        case .unexpectedFailure(let detail):
            throw StubRuntimeVerifierError(detail: detail)
        case .cancellation:
            throw CancellationError()
        }
    }
}

private struct StubRuntimeVerifierError: Error, Sendable {
    let detail: String
}
