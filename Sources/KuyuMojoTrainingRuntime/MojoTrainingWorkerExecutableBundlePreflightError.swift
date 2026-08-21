import Foundation

public enum MojoTrainingWorkerExecutableBundlePreflightError:
    Error, Sendable, Equatable
{
    case rootMismatch(expected: URL, actual: URL)
    case executableRelativePathMismatch(expected: String, actual: String)
    case executableURLMismatch(expected: URL, actual: URL)
}
