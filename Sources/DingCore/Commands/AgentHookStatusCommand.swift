import ArgumentParser
import Foundation

public struct AgentHookStatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show ding hook status for AI coding tools"
    )

    public init() {}

    // ANSI helpers
    private static let green = "\u{001B}[32m"
    private static let red = "\u{001B}[31m"
    private static let reset = "\u{001B}[0m"

    public func run() async throws {
        for agent in Agent.allCases {
            guard agent.isDetected else {
                print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) not found")
                continue
            }

            do {
                guard let config = try AgentHookManager.readConfig(for: agent) else {
                    print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) could not read config")
                    continue
                }

                let events = AgentHookManager.detectDingHookEvents(in: config)
                if events.isEmpty {
                    print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) not configured")
                } else {
                    print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.green)✓\(Self.reset) \(events.joined(separator: ", "))")
                }
            } catch {
                print("\(agent.displayName.padding(toLength: 13, withPad: " ", startingAt: 0))\(Self.red)✗\(Self.reset) \(error.localizedDescription)")
            }
        }
    }
}
