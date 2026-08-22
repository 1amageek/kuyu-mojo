import Foundation
import MojoRuntime

public struct MojoAcceleratorRuntimeBundle: Sendable, Equatable {
  public let rootURL: URL
  public let libraryURL: URL
  public let sessionFactoryBinding: MojoRuntimeLibraryBinding
  public let executionBinding: MojoRuntimeLibraryBinding
  public let verification: MojoRuntimeLibraryBundleVerification

  public init(
    rootURL: URL,
    libraryURL: URL,
    sessionFactoryBinding: MojoRuntimeLibraryBinding,
    executionBinding: MojoRuntimeLibraryBinding,
    verification: MojoRuntimeLibraryBundleVerification
  ) {
    self.rootURL = rootURL
    self.libraryURL = libraryURL
    self.sessionFactoryBinding = sessionFactoryBinding
    self.executionBinding = executionBinding
    self.verification = verification
  }
}
