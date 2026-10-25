import FixtureRecording
import Foundation

/// Entry point of `swift run fixture-recorder`. See `CommandLineOptions.usage`.
@main
enum FixtureRecorderCommand {
    static func main() async {
        let options: CommandLineOptions
        do {
            options = try CommandLineOptions.parse(
                Array(CommandLine.arguments.dropFirst()),
                environment: ProcessInfo.processInfo.environment
            )
        } catch .helpRequested {
            print(CommandLineOptions.usage)
            return
        } catch {
            writeError("\(error.description)\n\n\(CommandLineOptions.usage)")
            exit(2)
        }

        print("Recording fixtures from \(options.storefrontConfiguration.endpoint.absoluteString) "
            + "(\(options.token == nil ? "tokenless" : "with token")) into \(options.outputDirectory.path)")
        do {
            let files = try await FixtureRecorder(options: options).run()
            print("Done: \(files.count) files written.")
        } catch {
            writeError("Recording failed: \(error)")
            exit(1)
        }
    }

    private static func writeError(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
    }
}
