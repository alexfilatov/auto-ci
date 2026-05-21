// Tests/AutoCICoreTests/FakeCommandRunner.swift
import Foundation
@testable import AutoCICore

final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call { let command: String; let args: [String]; let cwd: String?; let stdin: String? }
    struct Stub { let command: String; let argsPrefix: [String]; let result: CommandResult }
    private(set) var calls: [Call] = []
    private var stubs: [Stub] = []

    func stub(command: String, args: [String], stdout: String = "", stderr: String = "", exit: Int32 = 0) {
        stubs.append(Stub(command: command, argsPrefix: args,
                          result: CommandResult(exitCode: exit, stdout: stdout, stderr: stderr)))
    }

    func run(_ command: String, _ args: [String], cwd: String?, stdin: String?, env: [String: String]?) throws -> CommandResult {
        calls.append(Call(command: command, args: args, cwd: cwd, stdin: stdin))
        for stub in stubs where stub.command == command && args.starts(with: stub.argsPrefix) {
            return stub.result
        }
        return CommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}
