import Foundation
@_spi(SwiftMojoGenerated) import Mojo
import MojoRuntime

final class OwnedMojoAcceleratorSession: MojoAcceleratorSession, Sendable {
  private let owner: MojoSessionOwner
  private let abi: MojoAcceleratorDynamicABI
  private let sessionDomainID: UInt64
  let executionFunctionNames: [String]
  private let executionBindingIDs: [String: UInt64]

  init(
    owner: MojoSessionOwner,
    abi: MojoAcceleratorDynamicABI,
    sessionDomainID: UInt64,
    executionBindings: [MojoRuntimeLibraryBinding]
  ) {
    self.owner = owner
    self.abi = abi
    self.sessionDomainID = sessionDomainID
    self.executionFunctionNames = executionBindings.map(\.functionName)
    self.executionBindingIDs = Dictionary(
      uniqueKeysWithValues: executionBindings.map {
        ($0.functionName, $0.bindingID)
      }
    )
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
    try execute(
      functionName: executionFunctionNames[0],
      request: request,
      into: &output
    )
  }

  func execute(
    functionName: String,
    request: borrowing [Float],
    into output: inout [Float]
  ) throws {
    guard let executionBindingID = executionBindingIDs[functionName] else {
      throw MojoAcceleratorRuntimeError.unavailableExecutionFunction(
        functionName
      )
    }
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
