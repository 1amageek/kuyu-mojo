import Mojo

public protocol MojoAcceleratorSession: AnyObject, Sendable {
  var capabilities: MojoSessionCapabilities { get }
  var isShutdown: Bool { get }

  func execute(
    request: borrowing [Float],
    into output: inout [Float]
  ) throws

  func shutdown() throws
}
