import Foundation

public protocol MojoAcceleratorWorkerBundlePreflighting: Sendable {
    func validatedBundle(
        at bundleURL: URL,
        requiring requirement: MojoAcceleratorWorkerBundleRequirement
    ) throws -> MojoAcceleratorWorkerBundle
}
