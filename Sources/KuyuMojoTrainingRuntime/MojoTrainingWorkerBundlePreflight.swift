import Foundation
import KuyuMojoCore
import KuyuTrainingRuntime

/// Adapts Mojo runtime verification to Kuyu's outer worker-bundle preflight
/// without making the accelerator evidence executable the worker entry point.
public struct MojoTrainingWorkerBundlePreflight:
    TrainingRunWorkerExecutableBundlePreflighting, Sendable
{
    public let layout: MojoTrainingWorkerBundleLayout

    private let requirement: MojoAcceleratorWorkerBundleRequirement
    private let acceleratorPreflight:
        any MojoAcceleratorWorkerBundlePreflighting

    public init(
        layout: MojoTrainingWorkerBundleLayout,
        requirement: MojoAcceleratorWorkerBundleRequirement,
        acceleratorPreflight:
            any MojoAcceleratorWorkerBundlePreflighting =
                FileSystemMojoAcceleratorWorkerBundlePreflight()
    ) {
        self.layout = layout
        self.requirement = requirement
        self.acceleratorPreflight = acceleratorPreflight
    }

    public func executableSource(
        at workerBundleRootURL: URL
    ) throws -> TrainingRunWorkerExecutableSource {
        let rootURL = workerBundleRootURL.standardizedFileURL
        let source = try TrainingRunWorkerExecutableSource(
            bundleRootURL: rootURL,
            executableRelativePath: layout.workerExecutableRelativePath
        )
        _ = try validatedAcceleratorRuntime(at: rootURL)
        return source
    }

    public func verifyBundle(
        at rootURL: URL,
        executableRelativePath: String
    ) throws {
        guard executableRelativePath
            == layout.workerExecutableRelativePath
        else {
            throw MojoTrainingWorkerBundlePreflightError
                .workerExecutableRelativePathMismatch(
                    expected: layout.workerExecutableRelativePath,
                    actual: executableRelativePath
                )
        }
        let rootURL = rootURL.standardizedFileURL
        _ = try TrainingRunWorkerExecutableSource(
            bundleRootURL: rootURL,
            executableRelativePath: executableRelativePath
        )
        _ = try validatedAcceleratorRuntime(at: rootURL)
    }

    /// Re-verifies and resolves the nested runtime for worker-local backend use.
    public func validatedAcceleratorRuntime(
        at workerBundleRootURL: URL
    ) throws -> MojoAcceleratorWorkerBundle {
        let workerBundleRootURL = try validatedWorkerBundleRoot(
            workerBundleRootURL
        )
        let expectedRootURL = layout.acceleratorRuntimeURL(
            in: workerBundleRootURL
        )
        let bundle = try acceleratorPreflight.validatedBundle(
            at: expectedRootURL,
            requiring: requirement
        )
        let actualRootURL = bundle.rootURL.standardizedFileURL
        guard actualRootURL == expectedRootURL else {
            throw MojoTrainingWorkerBundlePreflightError
                .acceleratorRuntimeRootMismatch(
                    expected: expectedRootURL,
                    actual: actualRootURL
                )
        }

        let expectedExecutableURL = expectedRootURL.appendingPathComponent(
            bundle.verification.executable.relativePath,
            isDirectory: false
        ).standardizedFileURL
        let actualExecutableURL = bundle.executableURL.standardizedFileURL
        guard actualExecutableURL == expectedExecutableURL else {
            throw MojoTrainingWorkerBundlePreflightError
                .acceleratorExecutableURLMismatch(
                    expected: expectedExecutableURL,
                    actual: actualExecutableURL
                )
        }
        return bundle
    }

    private func validatedWorkerBundleRoot(_ requestedURL: URL) throws -> URL {
        let source = try TrainingRunWorkerExecutableSource(
            bundleRootURL: requestedURL,
            executableRelativePath: layout.workerExecutableRelativePath
        )
        guard let rootURL = source.bundleRootURL else {
            throw TrainingRunWorkerExecutableSource.ValidationError
                .invalidBundleRoot(requestedURL.absoluteString)
        }
        return rootURL
    }
}
