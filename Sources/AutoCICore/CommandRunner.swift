// Sources/AutoCICore/CommandRunner.swift
import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public protocol CommandRunner: Sendable {
    func run(_ command: String, _ args: [String], cwd: String?, stdin: String?, env: [String: String]?) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}
    public func run(_ command: String, _ args: [String], cwd: String?, stdin: String?, env: [String: String]?) throws -> CommandResult {
        let process = Process()
        if command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        // A GUI/menu-bar app launched by LaunchServices or a login item inherits a
        // stripped PATH (often just /usr/bin:/bin), so tools like gh (/opt/homebrew/bin)
        // and claude (~/.local/bin) won't be found. Augment PATH with the common
        // locations so subprocesses resolve regardless of how the app was launched.
        var environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        let toolDirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin",
                        "\(home)/.bun/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existingPath = environment["PATH"].map { [$0] } ?? []
        environment["PATH"] = (toolDirs + existingPath).joined(separator: ":")
        if let env { environment.merge(env) { _, new in new } }
        process.environment = environment
        let out = Pipe(); let err = Pipe(); let inp = Pipe()
        process.standardOutput = out; process.standardError = err; process.standardInput = inp
        try process.run()
        if let stdin { inp.fileHandleForWriting.write(stdin.data(using: .utf8)!) }
        inp.fileHandleForWriting.closeFile()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
