import MojoRuntime

public struct MojoAcceleratorWorkerBundleRequirement: Sendable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidSchemaVersion(Int)
        case invalidBundleDigest(String)
        case invalidReceiptDigest(String)
        case invalidTargetTriple(String)
        case invalidTargetCPU(String)
        case missingAccelerator(MojoRuntimeBundleTarget)
        case invalidAccelerator(String)
    }

    public let schemaVersion: Int
    public let bundleDigest: String
    public let receiptDigest: String
    public let target: MojoRuntimeBundleTarget

    public init(
        schemaVersion: Int = 1,
        bundleDigest: String,
        receiptDigest: String,
        target: MojoRuntimeBundleTarget
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

        self.schemaVersion = schemaVersion
        self.bundleDigest = bundleDigest
        self.receiptDigest = receiptDigest
        self.target = target
    }

    private static func isSHA256Digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private static func isPrintableIdentityComponent(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            byte > 32 && byte < 127
        }
    }
}
