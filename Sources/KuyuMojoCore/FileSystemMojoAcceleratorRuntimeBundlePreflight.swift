import Foundation
import MojoRuntime

public struct FileSystemMojoAcceleratorRuntimeBundlePreflight:
  MojoAcceleratorRuntimeBundlePreflighting, Sendable
{
  private let runtimeVerifier: any MojoRuntimeLibraryBundleVerifying

  public init(
    runtimeVerifier: any MojoRuntimeLibraryBundleVerifying =
      FileSystemMojoRuntimeLibraryBundleVerifier()
  ) {
    self.runtimeVerifier = runtimeVerifier
  }

  public func validatedRuntimeBundle(
    at bundleURL: URL,
    requiring requirement: MojoAcceleratorRuntimeBundleRequirement
  ) throws -> MojoAcceleratorRuntimeBundle {
    guard bundleURL.isFileURL else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .nonFileBundleURL(bundleURL)
    }
    let rootURL = bundleURL.standardizedFileURL
    let verification: MojoRuntimeLibraryBundleVerification
    do {
      verification = try runtimeVerifier.verifyLibraryBundle(at: rootURL)
    } catch let error as MojoRuntimeBundleVerificationError {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .runtimeVerificationFailed(error)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .unexpectedRuntimeVerificationFailure(
          String(describing: error)
        )
    }

    guard verification.schemaVersion == requirement.schemaVersion else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .schemaVersionMismatch(
          expected: requirement.schemaVersion,
          actual: verification.schemaVersion
        )
    }
    guard verification.bundleDigest == requirement.bundleDigest else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .bundleDigestMismatch(
          expected: requirement.bundleDigest,
          actual: verification.bundleDigest
        )
    }
    guard verification.receiptDigest == requirement.receiptDigest else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .receiptDigestMismatch(
          expected: requirement.receiptDigest,
          actual: verification.receiptDigest
        )
    }
    guard verification.target == requirement.target else {
      throw MojoAcceleratorRuntimeBundlePreflightError.targetMismatch(
        expected: requirement.target,
        actual: verification.target
      )
    }
    guard verification.moduleName == requirement.moduleName else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .moduleNameMismatch(
          expected: requirement.moduleName,
          actual: verification.moduleName
        )
    }
    guard
      verification.inputGraphDigest
        == requirement.inputGraphDigest
    else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .inputGraphDigestMismatch(
          expected: requirement.inputGraphDigest,
          actual: verification.inputGraphDigest
        )
    }
    guard
      verification.inputGraphIdentifier
        == requirement.inputGraphIdentifier
    else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .inputGraphIdentifierMismatch(
          expected: requirement.inputGraphIdentifier,
          actual: verification.inputGraphIdentifier
        )
    }

    let libraryRelativePath = verification.library.relativePath
    guard Self.isSafeRelativePath(libraryRelativePath) else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .invalidLibraryRelativePath(libraryRelativePath)
    }
    let sessionFactories = verification.bindings.filter {
      $0.functionName == requirement.sessionFactoryFunctionName
        && $0.signature == .runtimeSessionFactory
        && $0.sessionFactoryFunctionName == nil
    }
    guard sessionFactories.count == 1,
      let sessionFactory = sessionFactories.first
    else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .sessionFactoryBindingMismatch(
          requirement.sessionFactoryFunctionName
        )
    }
    let executions = verification.bindings.filter {
      $0.functionName == requirement.executionFunctionName
        && $0.signature
          == .sessionBorrowedMutableFloat32Buffers
        && $0.sessionFactoryFunctionName
          == requirement.sessionFactoryFunctionName
    }
    guard executions.count == 1,
      let execution = executions.first
    else {
      throw
        MojoAcceleratorRuntimeBundlePreflightError
        .executionBindingMismatch(
          requirement.executionFunctionName
        )
    }

    return MojoAcceleratorRuntimeBundle(
      rootURL: rootURL,
      libraryURL: rootURL.appendingPathComponent(
        libraryRelativePath,
        isDirectory: false
      ),
      sessionFactoryBinding: sessionFactory,
      executionBinding: execution,
      verification: verification
    )
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
