import Foundation
import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import ManasMojoModels
import ManasMojoRuntime

public struct KuyuManasMojoCoreInferenceSessionFactory:
  ManasMojoCoreInferenceSessionCreating, Sendable
{
  public let bundleURL: URL
  public let requirement: MojoAcceleratorRuntimeBundleRequirement

  private let transportFactory: KuyuManasMojoInferenceTransportFactory

  public init(
    bundleURL: URL,
    requirement: MojoAcceleratorRuntimeBundleRequirement,
    preflight: any MojoAcceleratorRuntimeBundlePreflighting =
      FileSystemMojoAcceleratorRuntimeBundlePreflight(),
    runtimeLoader: any MojoAcceleratorRuntimeLoading =
      DynamicMojoAcceleratorRuntimeLoader()
  ) throws {
    try Self.validate(requirement: requirement)
    self.bundleURL = bundleURL
    self.requirement = requirement
    self.transportFactory = KuyuManasMojoInferenceTransportFactory(
      bundleURL: bundleURL,
      requirement: requirement,
      operations: ManasMojoInferenceABI.coreOperations,
      sessionRequirements: ManasMojoCoreModelSession.sessionRequirements(
        device: .accelerator
      ),
      preflight: preflight,
      runtimeLoader: runtimeLoader
    )
  }

  public func session(
    bundle: ManasMojoModelBundle
  ) throws -> any ManasMojoCoreInferenceSession {
    try ManasMojoCoreModelSession(
      bundle: bundle,
      transport: transportFactory.transport()
    )
  }

  private static func validate(
    requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws {
    guard
      requirement.sessionFactoryFunctionName
        == ManasMojoInferenceABI.coreSessionFactoryFunctionName,
      requirement.executionFunctionNames
        == ManasMojoInferenceABI.coreExecutionFunctionNames
    else {
      throw KuyuManasMojoInferenceSessionFactoryError.abiMismatch(
        kind: .core,
        expectedFactory:
          ManasMojoInferenceABI.coreSessionFactoryFunctionName,
        actualFactory: requirement.sessionFactoryFunctionName,
        expectedOperations:
          ManasMojoInferenceABI.coreExecutionFunctionNames,
        actualOperations: requirement.executionFunctionNames
      )
    }
  }
}
