import Foundation
import KuyuMojoCore
import KuyuMojoDynamics

@main
struct KuyuMojoAcceleratorAcceptanceFixtureTool {
    enum ToolError: Error, Equatable {
        case invalidArguments
        case unsupportedDeviceClass(String)
        case outputMustBeAbsolute(String)
        case outputAlreadyExists(String)
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            throw ToolError.invalidArguments
        }
        let rawDeviceClass = arguments[1]
        guard let deviceClass = MojoDeviceClass(rawValue: rawDeviceClass),
            deviceClass == .accelerator
        else {
            throw ToolError.unsupportedDeviceClass(rawDeviceClass)
        }
        let outputPath = arguments[2]
        guard outputPath.hasPrefix("/"), outputPath != "/" else {
            throw ToolError.outputMustBeAbsolute(outputPath)
        }
        let outputURL = URL(
            fileURLWithPath: outputPath,
            isDirectory: false
        ).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ToolError.outputAlreadyExists(outputURL.path)
        }
        let source = try MojoAcceleratorCanonicalAcceptanceSource.source(
            for: deviceClass
        )
        try Data(source.utf8).write(to: outputURL, options: .withoutOverwriting)
    }
}
