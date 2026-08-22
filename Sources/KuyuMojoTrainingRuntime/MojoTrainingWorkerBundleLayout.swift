import Foundation

/// Separates the authenticated Kuyu worker executable from its nested
/// accelerator runtime resource inside one immutable attempt bundle.
public struct MojoTrainingWorkerBundleLayout: Sendable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidWorkerExecutableRelativePath(String)
        case invalidAcceleratorRuntimeRelativePath(String)
        case overlappingPaths(
            workerExecutableRelativePath: String,
            acceleratorRuntimeRelativePath: String
        )
    }

    public let workerExecutableRelativePath: String
    public let acceleratorRuntimeRelativePath: String

    public init(
        workerExecutableRelativePath: String,
        acceleratorRuntimeRelativePath: String
    ) throws {
        guard Self.isSafeRelativePath(workerExecutableRelativePath) else {
            throw ValidationError.invalidWorkerExecutableRelativePath(
                workerExecutableRelativePath
            )
        }
        guard Self.isSafeRelativePath(acceleratorRuntimeRelativePath) else {
            throw ValidationError.invalidAcceleratorRuntimeRelativePath(
                acceleratorRuntimeRelativePath
            )
        }
        guard !Self.contains(
            acceleratorRuntimeRelativePath,
            workerExecutableRelativePath
        ), !Self.contains(
            workerExecutableRelativePath,
            acceleratorRuntimeRelativePath
        ) else {
            throw ValidationError.overlappingPaths(
                workerExecutableRelativePath: workerExecutableRelativePath,
                acceleratorRuntimeRelativePath: acceleratorRuntimeRelativePath
            )
        }

        self.workerExecutableRelativePath = workerExecutableRelativePath
        self.acceleratorRuntimeRelativePath = acceleratorRuntimeRelativePath
    }

    func acceleratorRuntimeURL(in workerBundleRootURL: URL) -> URL {
        workerBundleRootURL.appendingPathComponent(
            acceleratorRuntimeRelativePath,
            isDirectory: true
        ).standardizedFileURL
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
            !path.hasPrefix("/"),
            path.utf8.allSatisfy({ $0 != 0 })
        else {
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

    private static func contains(_ root: String, _ candidate: String) -> Bool {
        candidate == root || candidate.hasPrefix(root + "/")
    }
}
