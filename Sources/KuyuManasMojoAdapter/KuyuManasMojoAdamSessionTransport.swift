import KuyuMojoAcceleratorRuntime
import ManasMojoOptimizer
import Mojo

final class KuyuManasMojoAdamSessionTransport:
  ManasMojoAdamSessionTransport, Sendable
{
  private let runtime: any MojoAcceleratorRuntimeLibrary
  private let session: any MojoAcceleratorSession

  init(
    runtime: any MojoAcceleratorRuntimeLibrary,
    session: any MojoAcceleratorSession
  ) throws {
    guard
      session.executionFunctionNames
        == ManasMojoAdamABI.executionFunctionNames
    else {
      throw
        KuyuManasMojoAdamOptimizerSessionFactoryError
        .sessionOperationMismatch(
          expected: ManasMojoAdamABI.executionFunctionNames,
          actual: session.executionFunctionNames
        )
    }
    self.runtime = runtime
    self.session = session
  }

  var capabilities: MojoSessionCapabilities {
    session.capabilities
  }

  var isShutdown: Bool {
    session.isShutdown && runtime.isShutdown
  }

  func execute(
    _ operation: ManasMojoAdamOperation,
    request: borrowing [Float],
    into output: inout [Float]
  ) throws {
    do {
      try session.execute(
        functionName: operation.functionName,
        request: request,
        into: &output
      )
    } catch let error as MojoAcceleratorRuntimeError {
      switch error {
      case .invocationFailed(let status):
        throw ManasMojoAdamSessionTransportError.invocationFailed(
          status: status
        )
      case .unavailableExecutionFunction:
        throw ManasMojoAdamSessionTransportError.unavailableOperation(
          operation
        )
      default:
        throw ManasMojoAdamSessionTransportError.lifecycleFailure(
          stage: .execution,
          diagnostic: String(describing: error)
        )
      }
    } catch let error as MojoSessionError {
      throw ManasMojoAdamSessionTransportError.session(error)
    } catch {
      throw ManasMojoAdamSessionTransportError.lifecycleFailure(
        stage: .execution,
        diagnostic: String(describing: error)
      )
    }
  }

  func shutdown() throws {
    do {
      try session.shutdown()
    } catch let error as MojoSessionError {
      throw ManasMojoAdamSessionTransportError.session(error)
    } catch {
      throw ManasMojoAdamSessionTransportError.lifecycleFailure(
        stage: .shutdown,
        diagnostic: String(describing: error)
      )
    }

    do {
      try runtime.shutdown()
    } catch {
      throw ManasMojoAdamSessionTransportError.lifecycleFailure(
        stage: .shutdown,
        diagnostic: String(describing: error)
      )
    }
  }
}
