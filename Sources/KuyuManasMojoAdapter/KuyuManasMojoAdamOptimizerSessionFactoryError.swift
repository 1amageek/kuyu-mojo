import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import Mojo

public enum KuyuManasMojoAdamOptimizerSessionFactoryError:
  Error, Sendable, Equatable
{
  public enum Stage: String, Sendable, Equatable {
    case preflight
    case runtimeLoad
    case sessionCreation
    case operationValidation
  }

  case unsupportedDevice(MojoDeviceKind)
  case abiMismatch(
    expectedFactory: String,
    actualFactory: String,
    expectedOperations: [String],
    actualOperations: [String]
  )
  case sessionOperationMismatch(
    expected: [String],
    actual: [String]
  )
  case preflight(MojoAcceleratorRuntimeBundlePreflightError)
  case runtime(MojoAcceleratorRuntimeError)
  case unexpected(stage: Stage, diagnostic: String)
  case initializationCleanupFailure(
    initialization: String,
    cleanup: String
  )
}
