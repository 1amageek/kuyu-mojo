import Foundation
import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import ManasMojoRuntime
import Mojo

struct KuyuManasMojoInferenceTransportFactory: Sendable {
  let bundleURL: URL
  let requirement: MojoAcceleratorRuntimeBundleRequirement
  let operations: [ManasMojoInferenceOperation]
  let sessionRequirements: MojoSessionRequirements
  let preflight: any MojoAcceleratorRuntimeBundlePreflighting
  let runtimeLoader: any MojoAcceleratorRuntimeLoading

  func transport() throws -> KuyuManasMojoInferenceSessionTransport {
    let bundle: MojoAcceleratorRuntimeBundle
    do {
      bundle = try preflight.validatedRuntimeBundle(
        at: bundleURL,
        requiring: requirement
      )
    } catch let error as MojoAcceleratorRuntimeBundlePreflightError {
      throw KuyuManasMojoInferenceSessionFactoryError.preflight(error)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw KuyuManasMojoInferenceSessionFactoryError.unexpected(
        stage: .preflight,
        diagnostic: String(describing: error)
      )
    }

    let runtime: any MojoAcceleratorRuntimeLibrary
    do {
      runtime = try runtimeLoader.load(bundle)
    } catch let error as MojoAcceleratorRuntimeError {
      throw KuyuManasMojoInferenceSessionFactoryError.runtime(error)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw KuyuManasMojoInferenceSessionFactoryError.unexpected(
        stage: .runtimeLoad,
        diagnostic: String(describing: error)
      )
    }

    let acceleratorSession: any MojoAcceleratorSession
    do {
      acceleratorSession = try runtime.makeSession(
        requirements: sessionRequirements
      )
    } catch {
      try cleanup(
        runtime: runtime,
        initializationError: error,
        stage: .sessionCreation
      )
    }

    do {
      return try KuyuManasMojoInferenceSessionTransport(
        runtime: runtime,
        session: acceleratorSession,
        operations: operations
      )
    } catch {
      try cleanup(
        session: acceleratorSession,
        runtime: runtime,
        initializationError: error
      )
    }
  }

  private func cleanup(
    runtime: any MojoAcceleratorRuntimeLibrary,
    initializationError: Error,
    stage: KuyuManasMojoInferenceSessionFactoryError.Stage
  ) throws -> Never {
    do {
      try runtime.shutdown()
    } catch {
      throw
        KuyuManasMojoInferenceSessionFactoryError
        .initializationCleanupFailure(
          initialization: String(describing: initializationError),
          cleanup: String(describing: error)
        )
    }
    throw Self.factoryError(initializationError, stage: stage)
  }

  private func cleanup(
    session: any MojoAcceleratorSession,
    runtime: any MojoAcceleratorRuntimeLibrary,
    initializationError: Error
  ) throws -> Never {
    do {
      try session.shutdown()
      try runtime.shutdown()
    } catch {
      throw
        KuyuManasMojoInferenceSessionFactoryError
        .initializationCleanupFailure(
          initialization: String(describing: initializationError),
          cleanup: String(describing: error)
        )
    }
    throw Self.factoryError(
      initializationError,
      stage: .operationValidation
    )
  }

  private static func factoryError(
    _ error: Error,
    stage: KuyuManasMojoInferenceSessionFactoryError.Stage
  ) -> Error {
    if let error = error as? KuyuManasMojoInferenceSessionFactoryError {
      return error
    }
    if let error = error as? MojoAcceleratorRuntimeError {
      return KuyuManasMojoInferenceSessionFactoryError.runtime(error)
    }
    if error is CancellationError {
      return error
    }
    return KuyuManasMojoInferenceSessionFactoryError.unexpected(
      stage: stage,
      diagnostic: String(describing: error)
    )
  }
}
