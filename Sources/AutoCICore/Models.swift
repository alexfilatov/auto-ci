// Sources/AutoCICore/Models.swift
import Foundation

public struct ProjectConfig: Codable, Equatable, Sendable {
    public var name: String
    public var path: String
    public var remote: String
    public var protectedBranches: [String]
    public var protectTests: Bool
    public var testPathPatterns: [String]

    public static let defaultTestPathPatterns = ["tests/", "_test", ".test.", "spec", "/test"]

    public init(name: String, path: String, remote: String,
                protectedBranches: [String] = ["main", "master"],
                protectTests: Bool = true,
                testPathPatterns: [String] = ProjectConfig.defaultTestPathPatterns) {
        self.name = name; self.path = path; self.remote = remote
        self.protectedBranches = protectedBranches
        self.protectTests = protectTests
        self.testPathPatterns = testPathPatterns
    }

    private enum CodingKeys: String, CodingKey {
        case name, path, remote, protectedBranches, protectTests, testPathPatterns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.path = try c.decode(String.self, forKey: .path)
        self.remote = try c.decode(String.self, forKey: .remote)
        self.protectedBranches = try c.decodeIfPresent([String].self, forKey: .protectedBranches) ?? ["main", "master"]
        self.protectTests = try c.decodeIfPresent(Bool.self, forKey: .protectTests) ?? true
        self.testPathPatterns = try c.decodeIfPresent([String].self, forKey: .testPathPatterns) ?? ProjectConfig.defaultTestPathPatterns
    }
}

public struct PushEvent: Codable, Equatable, Sendable {
    public let project: String
    public let branch: String
    public let sha: String
    public let remote: String
    public init(project: String, branch: String, sha: String, remote: String) {
        self.project = project; self.branch = branch; self.sha = sha; self.remote = remote
    }
}

public enum RunStatus: String, Codable, Sendable {
    case queued, inProgress, succeeded, failed, cancelled, unknown
    public var isTerminal: Bool {
        switch self { case .succeeded, .failed, .cancelled: return true; default: return false }
    }
}

public struct WorkflowRun: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let status: RunStatus
    public let headSha: String
    public init(id: Int, name: String, status: RunStatus, headSha: String) {
        self.id = id; self.name = name; self.status = status; self.headSha = headSha
    }
}

public struct FailureSignature: Codable, Equatable, Hashable, Sendable {
    public let job: String
    public let step: String
    public let hash: String
    public init(job: String, step: String, hash: String) {
        self.job = job; self.step = step; self.hash = hash
    }
}

public struct FixContext: Sendable {
    public let runId: Int
    public let job: String
    public let step: String
    public let logs: String
    public let workflowYAML: String
    public let commitDiff: String
    public let changedFiles: [String]
    public let pastFixes: [FixRecord]
    public init(runId: Int, job: String, step: String, logs: String, workflowYAML: String,
                commitDiff: String, changedFiles: [String], pastFixes: [FixRecord]) {
        self.runId = runId; self.job = job; self.step = step; self.logs = logs
        self.workflowYAML = workflowYAML; self.commitDiff = commitDiff
        self.changedFiles = changedFiles; self.pastFixes = pastFixes
    }
}

public struct FixRecord: Codable, Equatable, Sendable {
    public let signature: FailureSignature
    public let summary: String
    public let succeeded: Bool
    public let timestamp: Date
    public init(signature: FailureSignature, summary: String, succeeded: Bool, timestamp: Date) {
        self.signature = signature; self.summary = summary; self.succeeded = succeeded; self.timestamp = timestamp
    }
}

public enum AppError: Error, Equatable, Sendable {
    case commandFailed(String, Int32)
    case projectNotFound(String)
    case noChanges
    case shaGone(String)
    case timedOut
    case testsModified([String])
}
