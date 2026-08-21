public struct MojoCompiledProgramIdentity: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case invalidProgramSchemaVersion(Int)
        case invalidProgramDigest(String)
        case invalidExecutorVersion(String)
    }

    public let programSchemaVersion: Int
    public let programDigest: String
    public let executorVersion: String
    public let numericType: MojoNumericType
    public let deviceClass: MojoDeviceClass

    public init(
        programSchemaVersion: Int,
        programDigest: String,
        executorVersion: String,
        numericType: MojoNumericType,
        deviceClass: MojoDeviceClass
    ) throws {
        guard programSchemaVersion > 0 else {
            throw ValidationError.invalidProgramSchemaVersion(
                programSchemaVersion
            )
        }
        guard programDigest.utf8.count == 64,
              programDigest.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw ValidationError.invalidProgramDigest(programDigest)
        }
        guard !executorVersion.isEmpty,
              executorVersion.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw ValidationError.invalidExecutorVersion(executorVersion)
        }
        self.programSchemaVersion = programSchemaVersion
        self.programDigest = programDigest
        self.executorVersion = executorVersion
        self.numericType = numericType
        self.deviceClass = deviceClass
    }
}
