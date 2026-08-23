public enum KuyuManasMojoTrainingRunError: Error, Sendable, Equatable {
  case shutdownFailure(String)
  case operationCleanupFailure(operation: String, cleanup: String)
}
