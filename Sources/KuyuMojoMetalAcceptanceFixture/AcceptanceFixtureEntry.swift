import Foundation
import KuyuMojoDynamics

@main
struct KuyuMojoMetalAcceptanceFixtureTool {
    enum ToolError: Error, Equatable {
        case invalidArguments
        case outputMustBeAbsolute(String)
        case outputAlreadyExists(String)
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            throw ToolError.invalidArguments
        }
        let outputPath = arguments[1]
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
        let source = try MojoMetalCanonicalAcceptanceSource.source()
        try Data(source.utf8).write(to: outputURL, options: .withoutOverwriting)
    }
}
