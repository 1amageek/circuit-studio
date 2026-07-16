import Foundation
import SignoffCLICore

@main
enum SignoffRunnerEntry {
    static func main() async {
        let exitCode = await SignoffCommand.run(
            arguments: Array(CommandLine.arguments.dropFirst())
        )
        exit(exitCode)
    }
}
