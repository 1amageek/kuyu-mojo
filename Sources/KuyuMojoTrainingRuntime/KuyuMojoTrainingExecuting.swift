public protocol KuyuMojoTrainingExecuting: Sendable {
  func train(_ request: KuyuMojoTrainingRequest) throws
    -> KuyuMojoTrainingResult
}
