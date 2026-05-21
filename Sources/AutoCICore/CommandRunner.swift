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
        if let env { process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }
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
