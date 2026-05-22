// Sources/AutoCICore/GitHubClient.swift
import Foundation

public struct GitHubClient: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    private func gh(_ args: [String], cwd: String?) throws -> String {
        let r = try runner.run("gh", args, cwd: cwd, stdin: nil, env: nil)
        guard r.exitCode == 0 else { throw AppError.commandFailed("gh " + args.joined(separator: " "), r.exitCode) }
        return r.stdout
    }

    private struct RawRun: Decodable {
        let databaseId: Int; let name: String; let status: String
        let conclusion: String?; let headSha: String; let url: String?
    }

    public func runs(forSha sha: String, cwd: String) throws -> [WorkflowRun] {
        let out = try gh(["run", "list", "--commit", sha,
                          "--json", "databaseId,name,status,conclusion,headSha,url",
                          "--limit", "20"], cwd: cwd)
        let raws = try JSONDecoder().decode([RawRun].self, from: Data(out.utf8))
        return raws.map { raw in
            WorkflowRun(id: raw.databaseId, name: raw.name,
                        status: mapStatus(status: raw.status, conclusion: raw.conclusion),
                        headSha: raw.headSha, url: raw.url ?? "")
        }
    }

    private func mapStatus(status: String, conclusion: String?) -> RunStatus {
        if status != "completed" {
            return status == "queued" ? .queued : .inProgress
        }
        switch conclusion {
        case "success": return .succeeded
        case "failure", "timed_out", "startup_failure": return .failed
        case "cancelled": return .cancelled
        default: return .unknown
        }
    }

    public func failedLog(runId: Int, cwd: String) throws -> String {
        try gh(["run", "view", String(runId), "--log-failed"], cwd: cwd)
    }

    public func createDraftPR(head: String, base: String, title: String, body: String, cwd: String) throws -> String {
        try gh(["pr", "create", "--draft", "--head", head, "--base", base,
                "--title", title, "--body", body], cwd: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
