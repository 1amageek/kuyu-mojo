import Foundation
import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import ManasLearningContracts
import ManasMojoOptimizer
import Mojo

public struct KuyuManasMojoAdamOptimizerSessionFactory:
  ManasAdamOptimizerSessionCreating, Sendable
{
  public let bundleURL: URL
  public let requirement: MojoAcceleratorRuntimeBundleRequirement

  private let preflight: any MojoAcceleratorRuntimeBundlePreflighting
  private let runtimeLoader: any MojoAcceleratorRuntimeLoading

  public init(
    bundleURL: URL,
    requirement: MojoAcceleratorRuntimeBundleRequirement,
    preflight: any MojoAcceleratorRuntimeBundlePreflighting =
      FileSystemMojoAcceleratorRuntimeBundlePreflight(),
    runtimeLoader: any MojoAcceleratorRuntimeLoading =
      DynamicMojoAcceleratorRuntimeLoader()
  ) throws {
    guard
      requirement.sessionFactoryFunctionName
        == ManasMojoAdamABI.sessionFactoryFunctionName,
      requirement.executionFunctionNames
        == ManasMojoAdamABI.executionFunctionNames
    else {
      throw KuyuManasMojoAdamOptimizerSessionFactoryError.abiMismatch(
        expectedFactory:
          ManasMojoAdamABI.sessionFactoryFunctionName,
        actualFactory: requirement.sessionFactoryFunctionName,
        expectedOperations: ManasMojoAdamABI.executionFunctionNames,
        actualOperations: requirement.executionFunctionNames
      )
    }
    self.bundleURL = bundleURL
    self.requirement = requirement
    self.preflight = preflight
    self.runtimeLoader = runtimeLoader
  }

  public func session(
    configuration: ManasAdamConfiguration,
    initialState: ManasAdamState
  ) throws -> any ManasAdamOptimizerSession {
    let transport = try makeTransport()
    return try ManasMojoAdamOptimizerSession(
      configuration: configuration,
      initialState: initialState,
      transport: transport
    )
  }

  public func session(
    checkpoint: ManasAdamCheckpoint
  ) throws -> any ManasAdamOptimizerSession {
    try session(
      configuration: checkpoint.configuration,
      initialState: checkpoint.state
    )
  }

  private func makeTransport() throws
    -> KuyuManasMojoAdamSessionTransport
  {
    let bundle: MojoAcceleratorRuntimeBundle
    do {
      bundle = try preflight.validatedRuntimeBundle(
        at: bundleURL,
        requiring: requirement
      )
    } catch let error as MojoAcceleratorRuntimeBundlePreflightError {
      throw
        KuyuManasMojoAdamOptimizerSessionFactoryError
        .preflight(error)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw KuyuManasMojoAdamOptimizerSessionFactoryError.unexpected(
        stage: .preflight,
        diagnostic: String(describing: error)
      )
    }

    let runtime: any MojoAcceleratorRuntimeLibrary
    do {
      runtime = try runtimeLoader.load(bundle)
    } catch let error as MojoAcceleratorRuntimeError {
      throw KuyuManasMojoAdamOptimizerSessionFactoryError.runtime(error)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw KuyuManasMojoAdamOptimizerSessionFactoryError.unexpected(
        stage: .runtimeLoad,
        diagnostic: String(describing: error)
      )
    }

    let acceleratorSession: any MojoAcceleratorSession
    do {
      acceleratorSession = try runtime.makeSession(
        requirements:
          ManasMojoAdamOptimizerSession.sessionRequirements(
            device: .accelerator
          )
      )
    } catch {
      try cleanup(
        runtime: runtime,
        initializationError: error,
        stage: .sessionCreation
      )
    }

    do {
      return try KuyuManasMojoAdamSessionTransport(
        runtime: runtime,
        session: acceleratorSession
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
    stage: KuyuManasMojoAdamOptimizerSessionFactoryError.Stage
  ) throws -> Never {
    do {
      try runtime.shutdown()
    } catch {
      throw
        KuyuManasMojoAdamOptimizerSessionFactoryError
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
        KuyuManasMojoAdamOptimizerSessionFactoryError
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
    stage: KuyuManasMojoAdamOptimizerSessionFactoryError.Stage
  ) -> Error {
    if let error = error
      as? KuyuManasMojoAdamOptimizerSessionFactoryError
    {
      return error
    }
    if let error = error as? MojoAcceleratorRuntimeError {
      return KuyuManasMojoAdamOptimizerSessionFactoryError.runtime(error)
    }
    if error is CancellationError {
      return error
    }
    return KuyuManasMojoAdamOptimizerSessionFactoryError.unexpected(
      stage: stage,
      diagnostic: String(describing: error)
    )
  }
}
