import Foundation
import ArgumentParser

public struct UninstallHookCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "uninstall-hook",
        abstract: "Remove shell hook installed by ding install-hook"
    )

    public init() {}

    public func run() async throws {
        let shell = detectShell()
        let hookDir = hookDirectory()
        let hookFile = hookDir.appendingPathComponent("hook.\(shell)")
        let rcFile = rcFilePath(for: shell)

        // Remove hook script file
        if FileManager.default.fileExists(atPath: hookFile.path) {
            try FileManager.default.removeItem(at: hookFile)
            print("✓ Removed hook script: \(hookFile.path)")
        } else {
            print("Hook script not found: \(hookFile.path)")
        }

        // Remove source line from RC file
        if let rcContent = try? String(contentsOf: rcFile, encoding: .utf8) {
            let guardComment = "# Added by ding"
            if rcContent.contains(guardComment) {
                // Remove the block: from "# Added by ding" to the next blank line after source
                let lines = rcContent.components(separatedBy: "\n")
                var filteredLines: [String] = []
                var skipMode = false
                for line in lines {
                    if line.contains(guardComment) {
                        skipMode = true
                        continue
                    }
                    if skipMode {
                        // Skip lines until we've passed the source line
                        if line.hasPrefix("source ") || line.hasPrefix("export DING_THRESHOLD") {
                            continue
                        }
                        skipMode = false
                    }
                    filteredLines.append(line)
                }
                let newContent = filteredLines.joined(separator: "\n")
                try newContent.write(to: rcFile, atomically: true, encoding: .utf8)
                print("✓ Removed hook source line from: \(rcFile.path)")
            } else {
                print("Hook source line not found in: \(rcFile.path)")
            }
        }

        print("")
        print("Hook uninstalled. Restart your shell to apply changes.")
    }

    private func detectShell() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if shell.hasSuffix("bash") { return "bash" }
        return "zsh"
    }

    private func hookDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/ding")
    }

    private func rcFilePath(for shell: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if shell == "bash" {
            return home.appendingPathComponent(".bashrc")
        }
        return home.appendingPathComponent(".zshrc")
    }
}
