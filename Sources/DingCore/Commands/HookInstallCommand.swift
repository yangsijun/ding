import ArgumentParser
import Foundation

public struct HookInstallCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install notification hooks",
        discussion: """
        Without arguments: installs shell hook (auto-notify on long-running commands).
        With agent name: installs hook into AI coding tool config.

        Examples:
          ding hook install              # shell hook (threshold: 30s)
          ding hook install -t 10        # shell hook (threshold: 10s)
          ding hook install claude       # Claude Code hook
          ding hook install gemini       # Gemini CLI hook
          ding hook install opencode     # OpenCode plugin
        """
    )

    @Argument(help: "AI coding tool to configure (claude, gemini, opencode). Omit for shell hook.")
    var agent: Agent?

    @Option(name: .shortAndLong, help: "Shell hook: seconds before triggering notification (default: 30)")
    var threshold: Int = 30

    public init() {}

    public func run() async throws {
        if let agent {
            try await installAgentHook(agent)
        } else {
            try await installShellHook()
        }
    }

    // MARK: - Agent Hook

    private func installAgentHook(_ agent: Agent) async throws {
        guard agent.isDetected else {
            print("✗ \(agent.displayName) — not found (\(agent.configFilePath.path) missing)")
            return
        }

        guard var config = try AgentHookManager.readConfig(for: agent) else {
            print("✗ \(agent.displayName) — could not read config")
            return
        }

        switch agent {
        case .opencode:
            let hadPlugin = AgentHookManager.isOpenCodePluginInstalled(in: config)
            config = try AgentHookManager.installOpenCodePlugin(into: config)
            try AgentHookManager.writeConfig(config, for: agent)

            let pluginDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/opencode/plugins/opencode-ding")
            try AgentHookManager.installOpenCodePluginFiles(to: pluginDir)

            print("✓ \(agent.displayName) — plugin \(hadPlugin ? "updated" : "installed")")

        default:
            let hadDingHooks = !AgentHookManager.detectDingHookEvents(in: config).isEmpty
            config = try AgentHookManager.installHooks(into: config, for: agent)
            try AgentHookManager.writeConfig(config, for: agent)

            let events = agent.hookDefinitions.map(\.event).joined(separator: ", ")
            let verb = hadDingHooks ? "updated" : "installed"
            print("✓ \(agent.displayName) — hooks \(verb) (\(events))")
        }
    }

    // MARK: - Shell Hook

    private func installShellHook() async throws {
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

        // Update or append source line in RC file
        let guardComment = "# Added by ding"
        let sourceBlock = "\n# Added by ding\nexport DING_THRESHOLD=\(threshold)\nsource \"\(hookFile.path)\"\n"

        let rcContent = (try? String(contentsOf: rcFile, encoding: .utf8)) ?? ""
        if rcContent.contains(guardComment) {
            let lines = rcContent.components(separatedBy: "\n")
            var newLines: [String] = []
            var i = 0
            while i < lines.count {
                if lines[i].contains(guardComment) {
                    newLines.append(lines[i])
                    i += 1
                    if i < lines.count && lines[i].hasPrefix("export DING_THRESHOLD=") {
                        newLines.append("export DING_THRESHOLD=\(threshold)")
                        i += 1
                    }
                    if i < lines.count && lines[i].hasPrefix("source ") {
                        newLines.append(lines[i])
                        i += 1
                    }
                } else {
                    newLines.append(lines[i])
                    i += 1
                }
            }
            try newLines.joined(separator: "\n").write(to: rcFile, atomically: true, encoding: .utf8)
            print("✓ Shell hook updated (threshold: \(threshold)s)")
        } else {
            let handle = try FileHandle(forWritingTo: rcFile)
            handle.seekToEndOfFile()
            handle.write(Data(sourceBlock.utf8))
            handle.closeFile()
            print("✓ Shell hook installed (threshold: \(threshold)s)")
        }

        print("✓ Hook script: \(hookFile.path)")
        print("")
        print("Restart your shell or run:")
        print("  source \(rcFile.path)")
    }

    // MARK: - Shell Helpers

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
        let resourceName = "hook.\(shell)"
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
        return inlineHookScript(for: shell, threshold: threshold)
    }

    private func inlineHookScript(for shell: String, threshold: Int) -> String {
        if shell == "bash" {
            return """
            # ding shell hook for bash
            # Installed by: ding hook install
            # Remove with: ding hook uninstall

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
                local short_pwd="$PWD"
                [[ "$short_pwd" = "$HOME"/* ]] && short_pwd="~${short_pwd#"$HOME"}"
                local body=$(printf '%s\\n%s' "$short_pwd" "${__ding_last_cmd}")

                (ding notify "$body" --status "$status_flag" --title "ding · Terminal" >/dev/null 2>&1 &)

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
            # Installed by: ding hook install
            # Remove with: ding hook uninstall

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
                local short_pwd="$PWD"
                [[ "$short_pwd" = "$HOME"/* ]] && short_pwd="~${short_pwd#"$HOME"}"
                local body=$(printf '%s\\n%s' "$short_pwd" "${__ding_last_cmd}")

                (ding notify "$body" --status "$status_flag" --title "ding · Terminal" >/dev/null 2>&1 &)

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
