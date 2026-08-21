import Foundation
import KuyuMojoCore
import KuyuTraining

public struct MojoTrainingWorkerExecutableBundlePreflight:
    TrainingRunWorkerExecutableBundlePreflighting, Sendable
{
    private let requirement: MojoAcceleratorWorkerBundleRequirement
    private let preflight: any MojoAcceleratorWorkerBundlePreflighting

    public init(
        requirement: MojoAcceleratorWorkerBundleRequirement,
        preflight: any MojoAcceleratorWorkerBundlePreflighting =
            FileSystemMojoAcceleratorWorkerBundlePreflight()
    ) {
        self.requirement = requirement
        self.preflight = preflight
    }

    public func executableSource(
        at bundleURL: URL
    ) throws -> TrainingRunWorkerExecutableSource {
        let bundle = try validatedBundle(
            at: bundleURL,
            expectedExecutableRelativePath: nil
        )
        return try TrainingRunWorkerExecutableSource(
            bundleRootURL: bundle.rootURL,
            executableRelativePath:
                bundle.verification.executable.relativePath
        )
    }

    public func verifyBundle(
        at rootURL: URL,
        executableRelativePath: String
    ) throws {
        _ = try validatedBundle(
            at: rootURL,
            expectedExecutableRelativePath: executableRelativePath
        )
    }

    private func validatedBundle(
        at requestedRootURL: URL,
        expectedExecutableRelativePath: String?
    ) throws -> MojoAcceleratorWorkerBundle {
        let expectedRootURL = requestedRootURL.standardizedFileURL
        let bundle = try preflight.validatedBundle(
            at: expectedRootURL,
            requiring: requirement
        )
        let actualRootURL = bundle.rootURL.standardizedFileURL
        guard actualRootURL == expectedRootURL else {
            throw MojoTrainingWorkerExecutableBundlePreflightError
                .rootMismatch(
                    expected: expectedRootURL,
                    actual: actualRootURL
                )
        }

        let actualExecutableRelativePath =
            bundle.verification.executable.relativePath
        if let expectedExecutableRelativePath,
            actualExecutableRelativePath != expectedExecutableRelativePath
        {
            throw MojoTrainingWorkerExecutableBundlePreflightError
                .executableRelativePathMismatch(
                    expected: expectedExecutableRelativePath,
                    actual: actualExecutableRelativePath
                )
        }

        let expectedExecutableURL = expectedRootURL.appendingPathComponent(
            actualExecutableRelativePath,
            isDirectory: false
        ).standardizedFileURL
        let actualExecutableURL = bundle.executableURL.standardizedFileURL
        guard actualExecutableURL == expectedExecutableURL else {
            throw MojoTrainingWorkerExecutableBundlePreflightError
                .executableURLMismatch(
                    expected: expectedExecutableURL,
                    actual: actualExecutableURL
                )
        }
        return bundle
    }
}
