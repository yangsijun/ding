import Foundation
import ArgumentParser

public struct InstallHookCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install-hook",
        abstract: "Install shell hook to auto-notify on long-running commands"
    )

    @Option(name: .long, help: "Minimum command duration in seconds to trigger notification (default: 30)")
    public var threshold: Int = 30

    public init() {}

    public func run() async throws {
        let shell = detectShell()
        let hookDir = hookDirectory()
        let hookFile = hookDir.appendingPathComponent("hook.\(shell)")
        let rcFile = rcFilePath(for: shell)

        // Create hook directory
        try FileManager.default.createDirectory(at: hookDir, withIntermediateDirectories: true)

        // Write hook script
        let hookContent = hookScript(for: shell, threshold: threshold)
        try hookContent.write(to: hookFile, atomically: true, encoding: .utf8)

        // Make hook script executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookFile.path)

        // Append source line to RC file (if not already present)
        let sourceLine = "\n# Added by ding\nexport DING_THRESHOLD=\(threshold)\nsource \"\(hookFile.path)\"\n"
        let guardComment = "# Added by ding"

        let rcContent = (try? String(contentsOf: rcFile, encoding: .utf8)) ?? ""
        if !rcContent.contains(guardComment) {
            let handle = try FileHandle(forWritingTo: rcFile)
            handle.seekToEndOfFile()
            handle.write(Data(sourceLine.utf8))
            handle.closeFile()
        } else {
            print("Hook already installed in \(rcFile.path)")
        }

        print("✓ Hook installed to \(hookFile.path)")
        print("✓ Source line added to \(rcFile.path)")
        print("")
        print("Restart your shell or run:")
        print("  source \(rcFile.path)")
        print("")
        print("Commands longer than \(threshold)s will trigger a notification.")
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

    private func hookScript(for shell: String, threshold: Int) -> String {
        // Read embedded hook script from Resources
        let resourceName = "hook.\(shell)"
        // Try to find the hook script relative to the binary
        let binaryDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let resourcePaths = [
            binaryDir.appendingPathComponent("../share/ding/\(resourceName)").standardized,
            binaryDir.appendingPathComponent("\(resourceName)"),
        ]
        for path in resourcePaths {
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                return content.replacingOccurrences(of: "${DING_THRESHOLD:-30}", with: "${DING_THRESHOLD:-\(threshold)}")
            }
        }
        // Fallback: inline the hook script
        return inlineHookScript(for: shell, threshold: threshold)
    }

    private func inlineHookScript(for shell: String, threshold: Int) -> String {
        if shell == "bash" {
            return """
            # ding shell hook for bash
            # Installed by: ding install-hook
            # Remove with: ding uninstall-hook

            __ding_threshold=${DING_THRESHOLD:-\(threshold)}
            __ding_cmd_start=0
            __ding_last_cmd=""

            __ding_debug() {
                if [[ "$BASH_COMMAND" != "__ding_precmd"* ]] && [[ "$BASH_COMMAND" != "PROMPT_COMMAND"* ]]; then
                    __ding_cmd_start=$(date +%s)
                    __ding_last_cmd="$BASH_COMMAND"
                fi
            }

            __ding_precmd() {
                local exit_code=$?
                local now
                now=$(date +%s)
                local elapsed=$(( now - __ding_cmd_start ))

                if [[ $__ding_cmd_start -eq 0 ]] || [[ $elapsed -lt $__ding_threshold ]]; then
                    __ding_cmd_start=0
                    return
                fi

                local status_flag="success"
                if [[ $exit_code -ne 0 ]]; then
                    status_flag="failure"
                fi

                ding notify "${__ding_last_cmd}" --status "$status_flag" --title "ding" 2>/dev/null &
                disown

                __ding_cmd_start=0
            }

            if [[ -z "${__ding_hooks_loaded:-}" ]]; then
                trap '__ding_debug' DEBUG
                PROMPT_COMMAND="__ding_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
                __ding_hooks_loaded=1
            fi
            """
        } else {
            return """
            # ding shell hook for zsh
            # Installed by: ding install-hook
            # Remove with: ding uninstall-hook

            __ding_threshold=${DING_THRESHOLD:-\(threshold)}
            __ding_cmd_start=0
            __ding_last_cmd=""

            __ding_preexec() {
                __ding_cmd_start=$(date +%s)
                __ding_last_cmd="$1"
            }

            __ding_precmd() {
                local exit_code=$?
                local now
                now=$(date +%s)
                local elapsed=$(( now - __ding_cmd_start ))

                if [[ $__ding_cmd_start -eq 0 ]] || [[ $elapsed -lt $__ding_threshold ]]; then
                    __ding_cmd_start=0
                    return
                fi

                if [[ "$__ding_last_cmd" == *"&" ]]; then
                    __ding_cmd_start=0
                    return
                fi

                local status_flag="success"
                if [[ $exit_code -ne 0 ]]; then
                    status_flag="failure"
                fi

                ding notify "${__ding_last_cmd}" --status "$status_flag" --title "ding" 2>/dev/null &
                disown

                __ding_cmd_start=0
            }

            if [[ -z "${__ding_hooks_loaded:-}" ]]; then
                autoload -Uz add-zsh-hook
                add-zsh-hook preexec __ding_preexec
                add-zsh-hook precmd __ding_precmd
                __ding_hooks_loaded=1
            fi
            """
        }
    }
}
