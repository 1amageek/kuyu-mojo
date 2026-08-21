import Foundation
import MojoRuntime

public enum MojoAcceleratorWorkerBundlePreflightError:
    Error, Sendable, Equatable
{
    case nonFileBundleURL(URL)
    case runtimeVerificationFailed(MojoRuntimeBundleVerificationError)
    case unexpectedRuntimeVerificationFailure(String)
    case schemaVersionMismatch(expected: Int, actual: Int)
    case bundleDigestMismatch(expected: String, actual: String)
    case receiptDigestMismatch(expected: String, actual: String)
    case targetMismatch(
        expected: MojoRuntimeBundleTarget,
        actual: MojoRuntimeBundleTarget
    )
    case invalidExecutableRelativePath(String)
}
