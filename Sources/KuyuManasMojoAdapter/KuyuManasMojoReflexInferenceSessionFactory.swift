import Foundation
import KuyuMojoAcceleratorRuntime
import KuyuMojoCore
import ManasMojoModels
import ManasMojoRuntime

public struct KuyuManasMojoReflexInferenceSessionFactory:
  ManasMojoReflexInferenceSessionCreating, Sendable
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
      operations: ManasMojoInferenceABI.reflexOperations,
      sessionRequirements: ManasMojoReflexModelSession.sessionRequirements(
        device: .accelerator
      ),
      preflight: preflight,
      runtimeLoader: runtimeLoader
    )
  }

  public func session(
    bundle: ManasMojoModelBundle
  ) throws -> any ManasMojoReflexInferenceSession {
    try ManasMojoReflexModelSession(
      bundle: bundle,
      transport: transportFactory.transport()
    )
  }

  private static func validate(
    requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws {
    guard
      requirement.sessionFactoryFunctionName
        == ManasMojoInferenceABI.reflexSessionFactoryFunctionName,
      requirement.executionFunctionNames
        == ManasMojoInferenceABI.reflexExecutionFunctionNames
    else {
      throw KuyuManasMojoInferenceSessionFactoryError.abiMismatch(
        kind: .reflex,
        expectedFactory:
          ManasMojoInferenceABI.reflexSessionFactoryFunctionName,
        actualFactory: requirement.sessionFactoryFunctionName,
        expectedOperations:
          ManasMojoInferenceABI.reflexExecutionFunctionNames,
        actualOperations: requirement.executionFunctionNames
      )
    }
  }
}
