import Mojo
import MojoRuntime

public enum MojoAcceleratorRuntimeError: Error, Sendable, Equatable {
  case runtimeVerificationFailed(MojoRuntimeBundleVerificationError)
  case unexpectedRuntimeVerificationFailure(String)
  case runtimeVerificationIdentityMismatch
  case invalidRuntimeLibraryRelativePath(String)
  case runtimeLibraryURLMismatch(expected: String, actual: String)
  case runtimeBindingIdentityMismatch
  case dynamicLibraryOpenFailed(path: String, diagnostic: String)
  case dynamicSymbolMissing(String)
  case ambiguousExportSuffix(String)
  case unsupportedStaticABIVersion(expected: UInt32, actual: UInt32)
  case inputGraphIdentifierMismatch(expected: UInt64, actual: UInt64)
  case unavailableBinding(UInt64)
  case runtimeLibraryShutdown
  case runtimeLibraryBusy(activeSessions: Int, activeCreations: Int)
  case dynamicLibraryCloseFailed(String)
  case sessionCreationFailed(status: Int32)
  case missingSessionHandle
  case responseSchemaMismatch(expected: UInt32, actual: UInt32)
  case invalidResponseDevice(UInt32)
  case responseDeviceMismatch(expected: MojoDeviceKind, actual: MojoDeviceKind)
  case responseOrdinalMismatch(expected: UInt32, actual: UInt32)
  case missingCapabilities(
    required: MojoSessionCapability,
    available: MojoSessionCapability
  )
  case unavailableExecutionFunction(String)
  case invocationFailed(status: Int32)
}
