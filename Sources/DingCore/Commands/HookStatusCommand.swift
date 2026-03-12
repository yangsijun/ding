import ArgumentParser
import Foundation

public struct HookStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show notification hook status"
    )

    public init() {}

    private static let green = "\u{001B}[32m"
    private static let red = "\u{001B}[31m"
    private static let reset = "\u{001B}[0m"

    public func run() async throws {
        // Shell hook status
        let shell = detectShell()
        let hookFile = hookDirectory().appendingPathComponent("hook.\(shell)")
        let shellInstalled = FileManager.default.fileExists(atPath: hookFile.path)

        let label = "Terminal".padding(toLength: 13, withPad: " ", startingAt: 0)
        if shellInstalled {
            print("\(label)\(Self.green)✓\(Self.reset) \(shell) hook installed")
        } else {
            print("\(label)\(Self.red)✗\(Self.reset) not installed")
        }

        // Agent hook status
        for agent in Agent.allCases {
            let agentLabel = agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0)

            guard agent.isDetected else {
                print("\(agentLabel)\(Self.red)✗\(Self.reset) not found")
                continue
            }

            do {
                guard let config = try AgentHookManager.readConfig(for: agent) else {
                    print("\(agentLabel)\(Self.red)✗\(Self.reset) could not read config")
                    continue
                }

                switch agent {
                case .opencode:
                    if AgentHookManager.isOpenCodePluginInstalled(in: config) {
                        print("\(agentLabel)\(Self.green)✓\(Self.reset) plugin installed")
                    } else {
                        print("\(agentLabel)\(Self.red)✗\(Self.reset) not configured")
                    }

                default:
                    let events = AgentHookManager.detectDingHookEvents(in: config)
                    if events.isEmpty {
                        print("\(agentLabel)\(Self.red)✗\(Self.reset) not configured")
                    } else {
                        print("\(agentLabel)\(Self.green)✓\(Self.reset) \(events.joined(separator: ", "))")
                    }
                }
            } catch {
                print("\(agentLabel)\(Self.red)✗\(Self.reset) \(error.localizedDescription)")
            }
        }
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
}
