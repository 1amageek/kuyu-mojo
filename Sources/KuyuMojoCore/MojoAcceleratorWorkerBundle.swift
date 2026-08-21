import Foundation
import MojoRuntime

public struct MojoAcceleratorWorkerBundle: Sendable, Equatable {
    public let rootURL: URL
    public let executableURL: URL
    public let verification: MojoRuntimeBundleVerification

    public init(
        rootURL: URL,
        executableURL: URL,
        verification: MojoRuntimeBundleVerification
    ) {
        self.rootURL = rootURL
        self.executableURL = executableURL
        self.verification = verification
    }
}
