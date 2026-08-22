import Foundation
import MojoRuntime

public enum MojoAcceleratorRuntimeBundlePreflightError:
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
  case moduleNameMismatch(expected: String, actual: String)
  case inputGraphDigestMismatch(expected: String, actual: String)
  case inputGraphIdentifierMismatch(expected: UInt64, actual: UInt64)
  case invalidLibraryRelativePath(String)
  case sessionFactoryBindingMismatch(String)
  case executionBindingMismatch(String)
}
