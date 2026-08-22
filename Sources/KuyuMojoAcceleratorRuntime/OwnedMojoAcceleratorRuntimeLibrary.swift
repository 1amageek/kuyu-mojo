@_spi(SwiftMojoGenerated) import Mojo
import MojoRuntime
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

final class OwnedMojoAcceleratorRuntimeLibrary:
  MojoAcceleratorRuntimeLibrary, Sendable
{
  // The dynamic loader defines this opaque token as a stable process-local
  // address. The Mutex protects exactly-once close state and all counters; the
  // raw pointer is reconstructed only for dlclose and never escapes.
  private struct LibraryHandle: Sendable {
    let address: UInt

    init(pointer: UnsafeMutableRawPointer) {
      self.address = UInt(bitPattern: pointer)
    }

    var pointer: UnsafeMutableRawPointer {
      // init receives a nonnull dlopen result, so zero cannot enter State.
      precondition(address != 0)
      return UnsafeMutableRawPointer(bitPattern: address)!
    }
  }

  private struct State: Sendable {
    var handle: LibraryHandle?
    var activeSessions: Int
    var activeCreations: Int
  }

  private let state: Mutex<State>
  private let abi: MojoAcceleratorDynamicABI
  private let sessionFactoryBindingID: UInt64
  private let executionBindings: [MojoRuntimeLibraryBinding]

  init(
    handle: UnsafeMutableRawPointer,
    abi: MojoAcceleratorDynamicABI,
    sessionFactoryBindingID: UInt64,
    executionBindings: [MojoRuntimeLibraryBinding]
  ) {
    self.state = Mutex(
      State(
        handle: LibraryHandle(pointer: handle),
        activeSessions: 0,
        activeCreations: 0
      )
    )
    self.abi = abi
    self.sessionFactoryBindingID = sessionFactoryBindingID
    self.executionBindings = executionBindings
  }

  var isShutdown: Bool {
    state.withLock { $0.handle == nil }
  }

  func makeSession(
    requirements: MojoSessionRequirements
  ) throws -> any MojoAcceleratorSession {
    try beginCreation()
    defer { finishCreation() }

    var sessionHandle: UnsafeMutableRawPointer?
    var responseSchema: UInt32 = 0
    var actualDeviceRawValue: UInt32 = 0
    var actualOrdinal: UInt32 = 0
    var availableCapabilitiesRawValue: UInt64 = 0
    let status = abi.createSession(
      sessionFactoryBindingID,
      MojoSessionRequirements.currentSchemaVersion,
      requirements.device.rawValue,
      requirements.ordinal,
      requirements.requiredCapabilities.rawValue,
      &sessionHandle,
      &responseSchema,
      &actualDeviceRawValue,
      &actualOrdinal,
      &availableCapabilitiesRawValue
    )
    guard status == 0 else {
      if let sessionHandle {
        abi.shutdownSession(sessionFactoryBindingID, sessionHandle)
      }
      throw MojoAcceleratorRuntimeError.sessionCreationFailed(
        status: status
      )
    }
    guard let sessionHandle else {
      throw MojoAcceleratorRuntimeError.missingSessionHandle
    }

    do {
      guard
        responseSchema
          == MojoSessionRequirements.currentSchemaVersion
      else {
        throw MojoAcceleratorRuntimeError.responseSchemaMismatch(
          expected: MojoSessionRequirements.currentSchemaVersion,
          actual: responseSchema
        )
      }
      guard
        let actualDevice = MojoDeviceKind(
          rawValue: actualDeviceRawValue
        )
      else {
        throw MojoAcceleratorRuntimeError.invalidResponseDevice(
          actualDeviceRawValue
        )
      }
      guard actualDevice == requirements.device else {
        throw MojoAcceleratorRuntimeError.responseDeviceMismatch(
          expected: requirements.device,
          actual: actualDevice
        )
      }
      guard actualOrdinal == requirements.ordinal else {
        throw MojoAcceleratorRuntimeError.responseOrdinalMismatch(
          expected: requirements.ordinal,
          actual: actualOrdinal
        )
      }
      let availableCapabilities = MojoSessionCapability(
        rawValue: availableCapabilitiesRawValue
      )
      guard
        availableCapabilities.contains(
          requirements.requiredCapabilities
        )
      else {
        throw MojoAcceleratorRuntimeError.missingCapabilities(
          required: requirements.requiredCapabilities,
          available: availableCapabilities
        )
      }

      registerSession()
      let library = self
      let owner = MojoSessionOwner(
        handle: sessionHandle,
        sessionDomainID: sessionFactoryBindingID,
        capabilities: MojoSessionCapabilities(
          device: actualDevice,
          ordinal: actualOrdinal,
          availableCapabilities: availableCapabilities
        ),
        destroy: { handle in
          library.abi.shutdownSession(
            library.sessionFactoryBindingID,
            handle
          )
          library.releaseSession()
        }
      )
      return OwnedMojoAcceleratorSession(
        owner: owner,
        abi: abi,
        sessionDomainID: sessionFactoryBindingID,
        executionBindings: executionBindings
      )
    } catch {
      abi.shutdownSession(sessionFactoryBindingID, sessionHandle)
      throw error
    }
  }

  func shutdown() throws {
    let handle = try state.withLock { state -> LibraryHandle? in
      guard let handle = state.handle else {
        return nil
      }
      guard state.activeSessions == 0,
        state.activeCreations == 0
      else {
        throw MojoAcceleratorRuntimeError.runtimeLibraryBusy(
          activeSessions: state.activeSessions,
          activeCreations: state.activeCreations
        )
      }
      state.handle = nil
      return handle
    }
    if let handle, dlclose(handle.pointer) != 0 {
      throw MojoAcceleratorRuntimeError.dynamicLibraryCloseFailed(
        Self.dynamicLoaderDiagnostic()
      )
    }
  }

  private func beginCreation() throws {
    try state.withLock { state in
      guard state.handle != nil else {
        throw MojoAcceleratorRuntimeError.runtimeLibraryShutdown
      }
      state.activeCreations += 1
    }
  }

  private func finishCreation() {
    state.withLock { state in
      precondition(state.activeCreations > 0)
      state.activeCreations -= 1
    }
  }

  private func registerSession() {
    state.withLock { state in
      precondition(state.handle != nil)
      precondition(state.activeCreations > 0)
      state.activeSessions += 1
    }
  }

  private func releaseSession() {
    state.withLock { state in
      precondition(state.activeSessions > 0)
      state.activeSessions -= 1
    }
  }

  private static func dynamicLoaderDiagnostic() -> String {
    guard let error = dlerror() else {
      return "dynamic loader returned no diagnostic"
    }
    return String(cString: error)
  }

  deinit {
    let handle = state.withLock { state -> LibraryHandle? in
      precondition(state.activeSessions == 0)
      precondition(state.activeCreations == 0)
      defer { state.handle = nil }
      return state.handle
    }
    if let handle {
      precondition(dlclose(handle.pointer) == 0)
    }
  }
}
