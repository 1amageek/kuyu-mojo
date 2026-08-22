import Mojo

public protocol MojoAcceleratorSession: AnyObject, Sendable {
  var capabilities: MojoSessionCapabilities { get }
  var executionFunctionNames: [String] { get }
  var isShutdown: Bool { get }

  func execute(
    request: borrowing [Float],
    into output: inout [Float]
  ) throws

  func execute(
    functionName: String,
    request: borrowing [Float],
    into output: inout [Float]
  ) throws

  func shutdown() throws
}
