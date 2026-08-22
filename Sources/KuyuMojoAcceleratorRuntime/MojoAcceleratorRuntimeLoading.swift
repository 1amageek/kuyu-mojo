import KuyuMojoCore

public protocol MojoAcceleratorRuntimeLoading: Sendable {
  func load(
    _ bundle: MojoAcceleratorRuntimeBundle
  ) throws -> any MojoAcceleratorRuntimeLibrary
}
