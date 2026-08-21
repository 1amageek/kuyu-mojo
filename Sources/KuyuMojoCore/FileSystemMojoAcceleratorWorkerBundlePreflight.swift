import Foundation
import MojoRuntime

public struct FileSystemMojoAcceleratorWorkerBundlePreflight:
    MojoAcceleratorWorkerBundlePreflighting, Sendable
{
    private let runtimeVerifier: any MojoRuntimeBundleVerifying

    public init(
        runtimeVerifier: any MojoRuntimeBundleVerifying =
            FileSystemMojoRuntimeBundleVerifier()
    ) {
        self.runtimeVerifier = runtimeVerifier
    }

    public func validatedBundle(
        at bundleURL: URL,
        requiring requirement: MojoAcceleratorWorkerBundleRequirement
    ) throws -> MojoAcceleratorWorkerBundle {
        guard bundleURL.isFileURL else {
            throw MojoAcceleratorWorkerBundlePreflightError
                .nonFileBundleURL(bundleURL)
        }

        let rootURL = bundleURL.standardizedFileURL
        let verification: MojoRuntimeBundleVerification
        do {
            verification = try runtimeVerifier.verifyBundle(at: rootURL)
        } catch let error as MojoRuntimeBundleVerificationError {
            throw MojoAcceleratorWorkerBundlePreflightError
                .runtimeVerificationFailed(error)
        } catch {
            throw MojoAcceleratorWorkerBundlePreflightError
                .unexpectedRuntimeVerificationFailure(
                    String(describing: error)
                )
        }

        guard verification.schemaVersion == requirement.schemaVersion else {
            throw MojoAcceleratorWorkerBundlePreflightError
                .schemaVersionMismatch(
                    expected: requirement.schemaVersion,
                    actual: verification.schemaVersion
                )
        }
        guard verification.bundleDigest == requirement.bundleDigest else {
            throw MojoAcceleratorWorkerBundlePreflightError
                .bundleDigestMismatch(
                    expected: requirement.bundleDigest,
                    actual: verification.bundleDigest
                )
        }
        guard verification.receiptDigest == requirement.receiptDigest else {
            throw MojoAcceleratorWorkerBundlePreflightError
                .receiptDigestMismatch(
                    expected: requirement.receiptDigest,
                    actual: verification.receiptDigest
                )
        }
        guard verification.target == requirement.target else {
            throw MojoAcceleratorWorkerBundlePreflightError.targetMismatch(
                expected: requirement.target,
                actual: verification.target
            )
        }

        let executableRelativePath = verification.executable.relativePath
        guard Self.isSafeRelativePath(executableRelativePath) else {
            throw MojoAcceleratorWorkerBundlePreflightError
                .invalidExecutableRelativePath(executableRelativePath)
        }

        return MojoAcceleratorWorkerBundle(
            rootURL: rootURL,
            executableURL: rootURL.appendingPathComponent(
                executableRelativePath,
                isDirectory: false
            ),
            verification: verification
        )
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }

        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }
}
