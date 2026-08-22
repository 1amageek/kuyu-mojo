import Foundation
import KuyuMojoCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct MojoAcceleratorDynamicABI: Sendable {
  typealias StaticABIVersion = @Sendable @convention(c) () -> UInt32
  typealias InputGraphIdentifier = @Sendable @convention(c) () -> UInt64
  typealias HasBinding = @Sendable @convention(c) (UInt64) -> UInt32
  typealias CreateSession =
    @Sendable @convention(c) (
      UInt64,
      UInt32,
      UInt32,
      UInt32,
      UInt64,
      UnsafeMutablePointer<UnsafeMutableRawPointer?>,
      UnsafeMutablePointer<UInt32>,
      UnsafeMutablePointer<UInt32>,
      UnsafeMutablePointer<UInt32>,
      UnsafeMutablePointer<UInt64>
    ) -> Int32
  typealias ShutdownSession =
    @Sendable @convention(c) (
      UInt64,
      UnsafeMutableRawPointer
    ) -> Void
  typealias CallSession =
    @Sendable @convention(c) (
      UInt64,
      UnsafeMutableRawPointer,
      UnsafePointer<Float>?,
      UInt64,
      UnsafeMutablePointer<Float>?,
      UInt64
    ) -> Int32

  let staticABIVersion: StaticABIVersion
  let inputGraphIdentifier: InputGraphIdentifier
  let hasBinding: HasBinding
  let createSession: CreateSession
  let shutdownSession: ShutdownSession
  let callSession: CallSession

  static func load(
    handle: UnsafeMutableRawPointer,
    bundle: MojoAcceleratorRuntimeBundle
  ) throws -> Self {
    let exports = bundle.verification.exportedSymbols
    return try Self(
      staticABIVersion: function(
        handle: handle,
        name: try symbolName(
          suffix: "_static_abi_version",
          exports: exports
        ),
        as: StaticABIVersion.self
      ),
      inputGraphIdentifier: function(
        handle: handle,
        name: try symbolName(
          suffix: "_input_graph_identifier",
          exports: exports
        ),
        as: InputGraphIdentifier.self
      ),
      hasBinding: function(
        handle: handle,
        name: try symbolName(
          suffix: "_has_binding",
          exports: exports
        ),
        as: HasBinding.self
      ),
      createSession: function(
        handle: handle,
        name: try symbolName(
          suffix: "_create_session_v1",
          exports: exports
        ),
        as: CreateSession.self
      ),
      shutdownSession: function(
        handle: handle,
        name: try symbolName(
          suffix: "_shutdown_session_v1",
          exports: exports
        ),
        as: ShutdownSession.self
      ),
      callSession: function(
        handle: handle,
        name: try symbolName(
          suffix: "_call_session_f32_buffer_f32_buffer_i32_v1",
          exports: exports
        ),
        as: CallSession.self
      )
    )
  }

  private static func symbolName(
    suffix: String,
    exports: [String]
  ) throws -> String {
    let matches = exports.filter { $0.hasSuffix(suffix) }
    guard matches.count == 1, let name = matches.first else {
      if matches.isEmpty {
        throw MojoAcceleratorRuntimeError.dynamicSymbolMissing(suffix)
      }
      throw MojoAcceleratorRuntimeError.ambiguousExportSuffix(suffix)
    }
    return name
  }

  private static func function<Function>(
    handle: UnsafeMutableRawPointer,
    name: String,
    as type: Function.Type
  ) throws -> Function {
    _ = dlerror()
    guard let symbol = name.withCString({ dlsym(handle, $0) }) else {
      throw MojoAcceleratorRuntimeError.dynamicSymbolMissing(name)
    }
    // The verified schema-3 manifest binds the exact generated header,
    // symbol allowlist, static ABI version, and binding signatures. The
    // dynamic-library owner retains the handle for every stored function
    // pointer, so the pointer cannot outlive its defining image.
    return unsafeBitCast(symbol, to: type)
  }
}
