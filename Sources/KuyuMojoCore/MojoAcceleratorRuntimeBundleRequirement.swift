import MojoRuntime

public struct MojoAcceleratorRuntimeBundleRequirement: Sendable, Equatable {
  public enum ValidationError: Error, Sendable, Equatable {
    case invalidSchemaVersion(Int)
    case invalidBundleDigest(String)
    case invalidReceiptDigest(String)
    case invalidInputGraphDigest(String)
    case invalidTargetTriple(String)
    case invalidTargetCPU(String)
    case missingAccelerator(MojoRuntimeBundleTarget)
    case invalidAccelerator(String)
    case invalidModuleName(String)
    case invalidSessionFactoryFunctionName(String)
    case invalidExecutionFunctionName(String)
    case identicalBindingFunctionNames(String)
  }

  public let schemaVersion: Int
  public let bundleDigest: String
  public let receiptDigest: String
  public let target: MojoRuntimeBundleTarget
  public let moduleName: String
  public let inputGraphDigest: String
  public let inputGraphIdentifier: UInt64
  public let sessionFactoryFunctionName: String
  public let executionFunctionName: String

  public init(
    schemaVersion: Int = 3,
    bundleDigest: String,
    receiptDigest: String,
    target: MojoRuntimeBundleTarget,
    moduleName: String,
    inputGraphDigest: String,
    inputGraphIdentifier: UInt64,
    sessionFactoryFunctionName: String,
    executionFunctionName: String
  ) throws {
    guard schemaVersion > 0 else {
      throw ValidationError.invalidSchemaVersion(schemaVersion)
    }
    guard Self.isSHA256Digest(bundleDigest) else {
      throw ValidationError.invalidBundleDigest(bundleDigest)
    }
    guard Self.isSHA256Digest(receiptDigest) else {
      throw ValidationError.invalidReceiptDigest(receiptDigest)
    }
    guard Self.isSHA256Digest(inputGraphDigest) else {
      throw ValidationError.invalidInputGraphDigest(inputGraphDigest)
    }
    guard Self.isPrintableIdentityComponent(target.triple) else {
      throw ValidationError.invalidTargetTriple(target.triple)
    }
    guard Self.isPrintableIdentityComponent(target.cpu) else {
      throw ValidationError.invalidTargetCPU(target.cpu)
    }
    guard let accelerator = target.accelerator else {
      throw ValidationError.missingAccelerator(target)
    }
    guard Self.isPrintableIdentityComponent(accelerator) else {
      throw ValidationError.invalidAccelerator(accelerator)
    }
    guard Self.isPortableIdentifier(moduleName) else {
      throw ValidationError.invalidModuleName(moduleName)
    }
    guard Self.isPortableIdentifier(sessionFactoryFunctionName) else {
      throw ValidationError.invalidSessionFactoryFunctionName(
        sessionFactoryFunctionName
      )
    }
    guard Self.isPortableIdentifier(executionFunctionName) else {
      throw ValidationError.invalidExecutionFunctionName(
        executionFunctionName
      )
    }
    guard sessionFactoryFunctionName != executionFunctionName else {
      throw ValidationError.identicalBindingFunctionNames(
        sessionFactoryFunctionName
      )
    }

    self.schemaVersion = schemaVersion
    self.bundleDigest = bundleDigest
    self.receiptDigest = receiptDigest
    self.target = target
    self.moduleName = moduleName
    self.inputGraphDigest = inputGraphDigest
    self.inputGraphIdentifier = inputGraphIdentifier
    self.sessionFactoryFunctionName = sessionFactoryFunctionName
    self.executionFunctionName = executionFunctionName
  }

  private static func isSHA256Digest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (97...102).contains(byte)
      }
  }

  private static func isPrintableIdentityComponent(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy { byte in
        byte > 32 && byte < 127
      }
  }

  private static func isPortableIdentifier(_ value: String) -> Bool {
    guard let first = value.utf8.first,
      Self.isASCIILetter(first) || first == 95
    else {
      return false
    }
    return value.utf8.dropFirst().allSatisfy { byte in
      Self.isASCIILetter(byte) || (48...57).contains(byte) || byte == 95
    }
  }

  private static func isASCIILetter(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte)
  }
}
