// Sources/AutoCICore/ClonePool.swift
import Foundation

public struct ClonePool: Sendable {
    private let root: URL
    private let git: GitClient
    public init(root: URL, git: GitClient) { self.root = root; self.git = git }

    public func cloneDir(project: String) -> String {
        root.appendingPathComponent("repos").appendingPathComponent(project).path
    }

    @discardableResult
    public func prepare(project: String, remoteURL: String, sha: String) throws -> String {
        let dir = cloneDir(project: project)
        try FileManager.default.createDirectory(
            atPath: root.appendingPathComponent("repos").path, withIntermediateDirectories: true)
        try git.cloneOrFetch(remoteURL: remoteURL, into: dir)
        guard git.shaExists(sha, cwd: dir) else { throw AppError.shaGone(sha) }
        try git.checkout(sha: sha, cwd: dir)
        return dir
    }
}
