public enum KuyuMojoTrainingServiceError: Error, Sendable, Equatable {
  case emptyCandidateBundleID
  case invalidCriticHiddenSize(Int)
  case invalidInitialPolicyLogStandardDeviation(Float)
  case invalidMaximumTransitions(UInt64)
  case invalidMaximumScalars(Int)
  case sourceBundleIDMismatch(expected: String, actual: String)
  case missingVerifiedSourceDigest
  case missingDatasetPolicy
  case datasetCheckpointMismatch(expected: String, actual: String)
  case trajectoryExceedsMinibatch(actual: UInt64, maximum: Int)
  case observationSchemaMismatch(expected: String, actual: String)
  case actorInputDimensionMismatch(expected: Int, actual: Int)
  case criticInputDimensionOverflow
  case actionDimensionMismatch(expected: Int, actual: Int)
}
