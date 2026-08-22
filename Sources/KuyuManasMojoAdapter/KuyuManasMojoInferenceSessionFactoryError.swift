import KuyuMojoAcceleratorRuntime
import KuyuMojoCore

public enum KuyuManasMojoInferenceSessionFactoryError:
  Error, Sendable, Equatable
{
  public enum SessionKind: String, Sendable, Equatable {
    case core
    case reflex
  }

  public enum Stage: String, Sendable, Equatable {
    case preflight
    case runtimeLoad
    case sessionCreation
    case operationValidation
  }

  case abiMismatch(
    kind: SessionKind,
    expectedFactory: String,
    actualFactory: String,
    expectedOperations: [String],
    actualOperations: [String]
  )
  case preflight(MojoAcceleratorRuntimeBundlePreflightError)
  case runtime(MojoAcceleratorRuntimeError)
  case sessionOperationMismatch(expected: [String], actual: [String])
  case unexpected(stage: Stage, diagnostic: String)
  case initializationCleanupFailure(
    initialization: String,
    cleanup: String
  )
}
