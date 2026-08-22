import Mojo

public protocol MojoAcceleratorRuntimeLibrary: AnyObject, Sendable {
  var isShutdown: Bool { get }

  func makeSession(
    requirements: MojoSessionRequirements
  ) throws -> any MojoAcceleratorSession

  func shutdown() throws
}
