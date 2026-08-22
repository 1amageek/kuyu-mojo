import Foundation
@_spi(SwiftMojoGenerated) import Mojo

final class OwnedMojoAcceleratorSession: MojoAcceleratorSession, Sendable {
  private let owner: MojoSessionOwner
  private let abi: MojoAcceleratorDynamicABI
  private let sessionDomainID: UInt64
  private let executionBindingID: UInt64

  init(
    owner: MojoSessionOwner,
    abi: MojoAcceleratorDynamicABI,
    sessionDomainID: UInt64,
    executionBindingID: UInt64
  ) {
    self.owner = owner
    self.abi = abi
    self.sessionDomainID = sessionDomainID
    self.executionBindingID = executionBindingID
  }

  var capabilities: MojoSessionCapabilities {
    owner.capabilities
  }

  var isShutdown: Bool {
    owner.isShutdown
  }

  func execute(
    request: borrowing [Float],
    into output: inout [Float]
  ) throws {
    try autoreleasepool {
      try owner.withOpaqueHandle(
        expectedSessionDomainID: sessionDomainID
      ) { handle in
        let status = request.withUnsafeBufferPointer { inputBuffer in
          output.withUnsafeMutableBufferPointer { outputBuffer in
            abi.callSession(
              executionBindingID,
              handle,
              inputBuffer.baseAddress,
              UInt64(inputBuffer.count),
              outputBuffer.baseAddress,
              UInt64(outputBuffer.count)
            )
          }
        }
        guard status == 0 else {
          throw MojoAcceleratorRuntimeError.invocationFailed(
            status: status
          )
        }
      }
    }
  }

  func shutdown() throws {
    try owner.shutdown()
  }
}
