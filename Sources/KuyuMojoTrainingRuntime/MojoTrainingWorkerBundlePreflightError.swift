import Foundation

public enum MojoTrainingWorkerBundlePreflightError:
  Error, Sendable, Equatable
{
  case workerExecutableRelativePathMismatch(
    expected: String,
    actual: String
  )
  case acceleratorRuntimeRootMismatch(expected: URL, actual: URL)
  case acceleratorLibraryURLMismatch(expected: URL, actual: URL)
}
