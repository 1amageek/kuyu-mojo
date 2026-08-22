import KuyuMojoAcceleratorRuntime
import ManasMojoRuntime
import Mojo

final class KuyuManasMojoInferenceSessionTransport:
  ManasMojoInferenceSessionTransport, Sendable
{
  private let runtime: any MojoAcceleratorRuntimeLibrary
  private let session: any MojoAcceleratorSession
  private let operationsByName: [String: ManasMojoInferenceOperation]

  init(
    runtime: any MojoAcceleratorRuntimeLibrary,
    session: any MojoAcceleratorSession,
    operations: [ManasMojoInferenceOperation]
  ) throws {
    let expectedNames = operations.map(\.functionName)
    guard session.executionFunctionNames == expectedNames else {
      throw
        KuyuManasMojoInferenceSessionFactoryError
        .sessionOperationMismatch(
          expected: expectedNames,
          actual: session.executionFunctionNames
        )
    }
    self.runtime = runtime
    self.session = session
    self.operationsByName = Dictionary(
      uniqueKeysWithValues: operations.map { ($0.functionName, $0) }
    )
  }

  var capabilities: MojoSessionCapabilities {
    session.capabilities
  }

  var isShutdown: Bool {
    session.isShutdown && runtime.isShutdown
  }

  func execute(
    _ operation: ManasMojoInferenceOperation,
    request: borrowing [Float],
    into output: inout [Float]
  ) throws {
    guard operationsByName[operation.functionName] == operation else {
      throw
        ManasMojoInferenceSessionTransportError
        .unavailableOperation(operation)
    }
    do {
      try session.execute(
        functionName: operation.functionName,
        request: request,
        into: &output
      )
    } catch let error as MojoAcceleratorRuntimeError {
      switch error {
      case .invocationFailed(let status):
        throw ManasMojoInferenceSessionTransportError.invocationFailed(
          operation: operation,
          status: status
        )
      case .unavailableExecutionFunction:
        throw
          ManasMojoInferenceSessionTransportError
          .unavailableOperation(operation)
      default:
        throw ManasMojoInferenceSessionTransportError.lifecycleFailure(
          stage: .execution,
          diagnostic: String(describing: error)
        )
      }
    } catch let error as MojoSessionError {
      throw ManasMojoInferenceSessionTransportError.session(error)
    } catch {
      throw ManasMojoInferenceSessionTransportError.lifecycleFailure(
        stage: .execution,
        diagnostic: String(describing: error)
      )
    }
  }

  func shutdown() throws {
    do {
      try session.shutdown()
    } catch let error as MojoSessionError {
      throw ManasMojoInferenceSessionTransportError.session(error)
    } catch {
      throw ManasMojoInferenceSessionTransportError.lifecycleFailure(
        stage: .shutdown,
        diagnostic: String(describing: error)
      )
    }

    do {
      try runtime.shutdown()
    } catch {
      throw ManasMojoInferenceSessionTransportError.lifecycleFailure(
        stage: .shutdown,
        diagnostic: String(describing: error)
      )
    }
  }
}
