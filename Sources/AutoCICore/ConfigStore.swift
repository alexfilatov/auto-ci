// Sources/AutoCICore/ConfigStore.swift
import Foundation

public final class ConfigStore: @unchecked Sendable {
    private let root: URL
    private let configURL: URL
    private var registry: [ProjectConfig]

    public init(root: URL) {
        self.root = root
        self.configURL = root.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.registry = []
        reload()
    }

    /// Re-read the registry from disk — picks up changes made by other processes
    /// (e.g. `auto-ci init` run from the CLI while the menubar app is running).
    public func reload() {
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode([ProjectConfig].self, from: data) {
            registry = decoded
        } else {
            registry = []
        }
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".auto-ci")
    }

    public func projects() -> [ProjectConfig] { registry }
    public func project(named name: String) -> ProjectConfig? { registry.first { $0.name == name } }
    public func project(forPath path: String) -> ProjectConfig? {
        let norm = (path as NSString).standardizingPath
        return registry.first { ($0.path as NSString).standardizingPath == norm }
    }

    public func upsert(_ project: ProjectConfig) throws {
        registry.removeAll { $0.name == project.name }
        registry.append(project)
        try persist()
    }

    public func remove(named name: String) throws {
        registry.removeAll { $0.name == name }
        try persist()
    }

    private func persist() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(registry).write(to: configURL)
    }
}
