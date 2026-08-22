import Foundation
import KuyuMojoCore
import MojoRuntime

struct StubAcceleratorBundlePreflight:
    MojoAcceleratorWorkerBundlePreflighting
{
    let returnedRootURL: URL?
    let returnedExecutableURL: URL?

    init(
        returnedRootURL: URL? = nil,
        returnedExecutableURL: URL? = nil
    ) {
        self.returnedRootURL = returnedRootURL
        self.returnedExecutableURL = returnedExecutableURL
    }

    func validatedBundle(
        at bundleURL: URL,
        requiring requirement: MojoAcceleratorWorkerBundleRequirement
    ) throws -> MojoAcceleratorWorkerBundle {
        let rootURL = returnedRootURL ?? bundleURL
        let executableRelativePath = "bin/kuyu-mojo-canonical"
        return MojoAcceleratorWorkerBundle(
            rootURL: rootURL,
            executableURL: returnedExecutableURL
                ?? rootURL.appendingPathComponent(
                    executableRelativePath,
                    isDirectory: false
                ),
            verification: MojoRuntimeBundleVerification(
                schemaVersion: requirement.schemaVersion,
                bundleDigest: requirement.bundleDigest,
                receiptDigest: requirement.receiptDigest,
                target: requirement.target,
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
