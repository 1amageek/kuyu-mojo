import Foundation

public protocol MojoAcceleratorRuntimeBundlePreflighting: Sendable {
  func validatedRuntimeBundle(
    at bundleURL: URL,
    requiring requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws -> MojoAcceleratorRuntimeBundle
}
