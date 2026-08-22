import Foundation
import MojoRuntime

public struct MojoAcceleratorRuntimeBundle: Sendable, Equatable {
  public enum ValidationError: Error, Sendable, Equatable {
    case emptyExecutionBindings
  }

  public let rootURL: URL
  public let libraryURL: URL
  public let sessionFactoryBinding: MojoRuntimeLibraryBinding
  public let executionBindings: [MojoRuntimeLibraryBinding]
  public let verification: MojoRuntimeLibraryBundleVerification

  public var executionBinding: MojoRuntimeLibraryBinding {
    executionBindings[0]
  }

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
    self.executionBindings = [executionBinding]
    self.verification = verification
  }

  public init(
    rootURL: URL,
    libraryURL: URL,
    sessionFactoryBinding: MojoRuntimeLibraryBinding,
    executionBindings: [MojoRuntimeLibraryBinding],
    verification: MojoRuntimeLibraryBundleVerification
  ) throws {
    guard !executionBindings.isEmpty else {
      throw ValidationError.emptyExecutionBindings
    }
    self.rootURL = rootURL
    self.libraryURL = libraryURL
    self.sessionFactoryBinding = sessionFactoryBinding
    self.executionBindings = executionBindings
    self.verification = verification
  }
}
