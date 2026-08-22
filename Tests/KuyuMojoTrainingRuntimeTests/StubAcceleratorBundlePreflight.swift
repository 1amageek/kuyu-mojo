import Foundation
import KuyuMojoCore
import MojoRuntime

struct StubAcceleratorBundlePreflight:
  MojoAcceleratorRuntimeBundlePreflighting
{
  let returnedRootURL: URL?
  let returnedLibraryURL: URL?

  init(
    returnedRootURL: URL? = nil,
    returnedLibraryURL: URL? = nil
  ) {
    self.returnedRootURL = returnedRootURL
    self.returnedLibraryURL = returnedLibraryURL
  }

  func validatedRuntimeBundle(
    at bundleURL: URL,
    requiring requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws -> MojoAcceleratorRuntimeBundle {
    let rootURL = returnedRootURL ?? bundleURL
    let libraryRelativePath =
      "lib/libSwiftMojo_KuyuAccelerator_ABI.dylib"
    let factory = MojoRuntimeLibraryBinding(
      bindingID: 11,
      functionName: requirement.sessionFactoryFunctionName,
      signature: .runtimeSessionFactory
    )
    let execution = MojoRuntimeLibraryBinding(
      bindingID: 12,
      functionName: requirement.executionFunctionName,
      signature: .sessionBorrowedMutableFloat32Buffers,
      sessionFactoryFunctionName:
        requirement.sessionFactoryFunctionName
    )
    return MojoAcceleratorRuntimeBundle(
      rootURL: rootURL,
      libraryURL: returnedLibraryURL
        ?? rootURL.appendingPathComponent(
          libraryRelativePath,
          isDirectory: false
        ),
      sessionFactoryBinding: factory,
      executionBinding: execution,
      verification: MojoRuntimeLibraryBundleVerification(
        schemaVersion: requirement.schemaVersion,
        bundleDigest: requirement.bundleDigest,
        receiptDigest: requirement.receiptDigest,
        target: requirement.target,
        moduleName: requirement.moduleName,
        compilerVersion: "Mojo 1.0.0",
        inputGraphDigest: requirement.inputGraphDigest,
        inputGraphIdentifier: requirement.inputGraphIdentifier,
        generatedSourceDigest: String(repeating: "d", count: 64),
        sourceMapDigest: String(repeating: "e", count: 64),
        bindings: [factory, execution],
        loaderSearchPath: "@loader_path",
        library: MojoRuntimeBundleFile(
          relativePath: libraryRelativePath,
          sha256Digest: String(repeating: "c", count: 64)
        ),
        runtimeLibraries: [],
        interfaceHeader: MojoRuntimeBundleFile(
          relativePath: "include/\(requirement.moduleName).h",
          sha256Digest: String(repeating: "f", count: 64)
        ),
        moduleMap: MojoRuntimeBundleFile(
          relativePath: "include/module.modulemap",
          sha256Digest: String(repeating: "1", count: 64)
        ),
        exportedSymbols: [
          "swift_mojo_fixture_static_abi_version",
          "swift_mojo_fixture_input_graph_identifier",
          "swift_mojo_fixture_has_binding",
          "swift_mojo_fixture_create_session_v1",
          "swift_mojo_fixture_shutdown_session_v1",
          "swift_mojo_fixture_call_session_f32_buffer_f32_buffer_i32_v1",
        ],
        systemDependencies: ["/usr/lib/libSystem.B.dylib"]
      )
    )
  }
}
