import Foundation
import KuyuMojoCore
import MojoRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct DynamicMojoAcceleratorRuntimeLoader:
  MojoAcceleratorRuntimeLoading, Sendable
{
  private static let supportedStaticABIVersion: UInt32 = 1
  private let runtimeVerifier: any MojoRuntimeLibraryBundleVerifying

  public init(
    runtimeVerifier: any MojoRuntimeLibraryBundleVerifying =
      FileSystemMojoRuntimeLibraryBundleVerifier()
  ) {
    self.runtimeVerifier = runtimeVerifier
  }

  public func load(
    _ bundle: MojoAcceleratorRuntimeBundle
  ) throws -> any MojoAcceleratorRuntimeLibrary {
    let verification: MojoRuntimeLibraryBundleVerification
    do {
      verification = try runtimeVerifier.verifyLibraryBundle(
        at: bundle.rootURL
      )
    } catch let error as MojoRuntimeBundleVerificationError {
      throw MojoAcceleratorRuntimeError.runtimeVerificationFailed(error)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw MojoAcceleratorRuntimeError.unexpectedRuntimeVerificationFailure(
        String(describing: error)
      )
    }
    guard verification == bundle.verification else {
      throw MojoAcceleratorRuntimeError.runtimeVerificationIdentityMismatch
    }

    let libraryRelativePath = verification.library.relativePath
    guard Self.isSafeRelativePath(libraryRelativePath) else {
      throw MojoAcceleratorRuntimeError.invalidRuntimeLibraryRelativePath(
        libraryRelativePath
      )
    }
    let expectedLibraryURL = bundle.rootURL.appendingPathComponent(
      libraryRelativePath,
      isDirectory: false
    ).standardizedFileURL
    let actualLibraryURL = bundle.libraryURL.standardizedFileURL
    guard expectedLibraryURL == actualLibraryURL else {
      throw MojoAcceleratorRuntimeError.runtimeLibraryURLMismatch(
        expected: expectedLibraryURL.path,
        actual: actualLibraryURL.path
      )
    }
    let factory = bundle.sessionFactoryBinding
    let execution = bundle.executionBinding
    guard
      factory.signature == .runtimeSessionFactory,
      factory.sessionFactoryFunctionName == nil,
      execution.signature == .sessionBorrowedMutableFloat32Buffers,
      execution.sessionFactoryFunctionName == factory.functionName,
      verification.bindings.filter({ $0 == factory }).count == 1,
      verification.bindings.filter({ $0 == execution }).count == 1
    else {
      throw MojoAcceleratorRuntimeError.runtimeBindingIdentityMismatch
    }

    let path = expectedLibraryURL.path
    guard
      let handle = path.withCString({
        dlopen($0, RTLD_NOW | RTLD_LOCAL)
      })
    else {
      throw MojoAcceleratorRuntimeError.dynamicLibraryOpenFailed(
        path: path,
        diagnostic: Self.dynamicLoaderDiagnostic()
      )
    }

    do {
      let abi = try MojoAcceleratorDynamicABI.load(
        handle: handle,
        bundle: bundle
      )
      let abiVersion = abi.staticABIVersion()
      guard abiVersion == Self.supportedStaticABIVersion else {
        throw MojoAcceleratorRuntimeError.unsupportedStaticABIVersion(
          expected: Self.supportedStaticABIVersion,
          actual: abiVersion
        )
      }
      let graphIdentifier = abi.inputGraphIdentifier()
      guard
        graphIdentifier
          == bundle.verification.inputGraphIdentifier
      else {
        throw
          MojoAcceleratorRuntimeError
          .inputGraphIdentifierMismatch(
            expected: bundle.verification.inputGraphIdentifier,
            actual: graphIdentifier
          )
      }
      for bindingID in [
        bundle.sessionFactoryBinding.bindingID,
        bundle.executionBinding.bindingID,
      ] where abi.hasBinding(bindingID) != 1 {
        throw MojoAcceleratorRuntimeError.unavailableBinding(bindingID)
      }
      return OwnedMojoAcceleratorRuntimeLibrary(
        handle: handle,
        abi: abi,
        sessionFactoryBindingID:
          bundle.sessionFactoryBinding.bindingID,
        executionBindingID: bundle.executionBinding.bindingID
      )
    } catch {
      _ = dlclose(handle)
      throw error
    }
  }

  private static func dynamicLoaderDiagnostic() -> String {
    guard let error = dlerror() else {
      return "dynamic loader returned no diagnostic"
    }
    return String(cString: error)
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/") else {
      return false
    }
    return path.split(
      separator: "/",
      omittingEmptySubsequences: false
    ).allSatisfy { component in
      !component.isEmpty && component != "." && component != ".."
    }
  }
}
