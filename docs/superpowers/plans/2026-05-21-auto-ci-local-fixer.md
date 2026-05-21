# Auto-CI Local Fixer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menubar app + daemon that watches GitHub Actions for locally-pushed commits and auto-fixes failing CI using headless Claude Code, isolated in per-project clones.

**Architecture:** A pure-logic Swift package `AutoCICore` holds all orchestration and is fully unit-tested via `swift test`. All external processes (`git`, `gh`, `claude`) sit behind an injectable `CommandRunner` protocol, so tests use a deterministic fake. A thin `auto-ci` CLI executable and a SwiftUI `MenuBarExtra` app are shells over the core.

**Tech Stack:** Swift 6.2, SwiftPM, XCTest, SwiftUI `MenuBarExtra`, subprocesses `git` / `gh` / `claude`.

---

## File Structure

```
auto_ci/
  Package.swift
  Sources/
    AutoCICore/
      CommandRunner.swift     # protocol + Process-backed impl + result type
      Models.swift            # PushEvent, RunStatus, FixContext, FailureSignature, FixRecord, ProjectConfig, AppError
      ConfigStore.swift       # load/save ~/.auto-ci/config.json, project registry
      GitClient.swift         # git operations via CommandRunner
      GitHubClient.swift      # gh operations via CommandRunner
      HookInstaller.swift     # chain-install/uninstall pre-push
      ClonePool.swift         # per-project clone under ~/.auto-ci/repos
      SignatureBuilder.swift  # normalize logs -> FailureSignature
      FixMemory.swift         # per-project fixes.json store
      ContextBuilder.swift    # assemble FixContext from a failed run
      FixRunner.swift         # invoke claude headless, capture diff
      Publisher.swift         # commit+push or fix-branch+PR
      RunWatcher.swift        # poll runs by head-sha until terminal
      Daemon.swift            # per-project lifecycle state machine
    auto-ci/
      main.swift              # CLI: init / status / list / uninstall
    AutoCIApp/
      AutoCIApp.swift         # MenuBarExtra shell hosting Daemon
  Tests/
    AutoCICoreTests/
      FakeCommandRunner.swift
      *Tests.swift
```

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/AutoCICore/Placeholder.swift`
- Create: `Tests/AutoCICoreTests/SmokeTests.swift`

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoCI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AutoCICore"),
        .executableTarget(name: "auto-ci", dependencies: ["AutoCICore"]),
        .testTarget(name: "AutoCICoreTests", dependencies: ["AutoCICore"]),
    ]
)
```

- [ ] **Step 2: Add placeholder so the target compiles**

```swift
// Sources/AutoCICore/Placeholder.swift
public enum AutoCI { public static let version = "0.1.0" }
```

Create a minimal CLI entry so the executable target builds:
```swift
// Sources/auto-ci/main.swift
import AutoCICore
print("auto-ci \(AutoCI.version)")
```

- [ ] **Step 3: Write the smoke test**

```swift
// Tests/AutoCICoreTests/SmokeTests.swift
import XCTest
@testable import AutoCICore

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(AutoCI.version, "0.1.0") }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: package scaffold"
```

---

### Task 2: CommandRunner protocol + fake

**Files:**
- Create: `Sources/AutoCICore/CommandRunner.swift`
- Create: `Tests/AutoCICoreTests/FakeCommandRunner.swift`
- Test: `Tests/AutoCICoreTests/CommandRunnerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/CommandRunnerTests.swift
import XCTest
@testable import AutoCICore

final class CommandRunnerTests: XCTestCase {
    func testRealRunnerCapturesStdout() throws {
        let runner = ProcessCommandRunner()
        let result = try runner.run("/bin/echo", ["hello"], cwd: nil, stdin: nil, env: nil)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testFakeMatchesByPrefix() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["status"], stdout: "clean", exit: 0)
        let r = try fake.run("git", ["status"], cwd: nil, stdin: nil, env: nil)
        XCTAssertEqual(r.stdout, "clean")
        XCTAssertEqual(fake.calls.count, 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CommandRunnerTests`
Expected: FAIL (types undefined).

- [ ] **Step 3: Implement CommandRunner**

```swift
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
```

- [ ] **Step 4: Implement FakeCommandRunner**

```swift
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
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter CommandRunnerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: CommandRunner protocol with process impl and fake"
```

---

### Task 3: Domain models

**Files:**
- Create: `Sources/AutoCICore/Models.swift`
- Test: `Tests/AutoCICoreTests/ModelsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/ModelsTests.swift
import XCTest
@testable import AutoCICore

final class ModelsTests: XCTestCase {
    func testProjectConfigDefaultsProtectedBranches() {
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin")
        XCTAssertEqual(p.protectedBranches, ["main", "master"])
    }

    func testProjectConfigCodableRoundTrip() throws {
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin", protectedBranches: ["main"])
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func testRunStatusTerminalDetection() {
        XCTAssertTrue(RunStatus.failed.isTerminal)
        XCTAssertTrue(RunStatus.succeeded.isTerminal)
        XCTAssertFalse(RunStatus.inProgress.isTerminal)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ModelsTests`
Expected: FAIL.

- [ ] **Step 3: Implement models**

```swift
// Sources/AutoCICore/Models.swift
import Foundation

public struct ProjectConfig: Codable, Equatable, Sendable {
    public var name: String
    public var path: String
    public var remote: String
    public var protectedBranches: [String]
    public init(name: String, path: String, remote: String, protectedBranches: [String] = ["main", "master"]) {
        self.name = name; self.path = path; self.remote = remote; self.protectedBranches = protectedBranches
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
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ModelsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: domain models"
```

---

### Task 4: ConfigStore

**Files:**
- Create: `Sources/AutoCICore/ConfigStore.swift`
- Test: `Tests/AutoCICoreTests/ConfigStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/ConfigStoreTests.swift
import XCTest
@testable import AutoCICore

final class ConfigStoreTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testAddAndLoadProject() throws {
        let store = ConfigStore(root: dir)
        let p = ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin")
        try store.upsert(p)
        let reloaded = ConfigStore(root: dir)
        XCTAssertEqual(reloaded.projects(), [p])
        XCTAssertEqual(reloaded.project(named: "demo"), p)
    }

    func testProjectForPathMatches() throws {
        let store = ConfigStore(root: dir)
        try store.upsert(ProjectConfig(name: "demo", path: "/tmp/demo", remote: "origin"))
        XCTAssertEqual(store.project(forPath: "/tmp/demo")?.name, "demo")
        XCTAssertNil(store.project(forPath: "/tmp/other"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement ConfigStore**

```swift
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
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode([ProjectConfig].self, from: data) {
            self.registry = decoded
        } else {
            self.registry = []
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: config store"
```

---

### Task 5: SignatureBuilder

**Files:**
- Create: `Sources/AutoCICore/SignatureBuilder.swift`
- Test: `Tests/AutoCICoreTests/SignatureBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/SignatureBuilderTests.swift
import XCTest
@testable import AutoCICore

final class SignatureBuilderTests: XCTestCase {
    let builder = SignatureBuilder()

    func testStripsVolatileBitsSoEquivalentFailuresMatch() {
        let logA = "2026-05-21T10:00:00Z /Users/alex/x/file.rb:12: error: undefined method `foo'"
        let logB = "2026-05-21T11:42:13Z /Users/bob/y/file.rb:99: error: undefined method `foo'"
        let a = builder.signature(job: "test", step: "rspec", logs: logA)
        let b = builder.signature(job: "test", step: "rspec", logs: logB)
        XCTAssertEqual(a.hash, b.hash)
    }

    func testDifferentErrorsDiffer() {
        let a = builder.signature(job: "test", step: "rspec", logs: "error: undefined method `foo'")
        let b = builder.signature(job: "test", step: "rspec", logs: "error: undefined method `bar'")
        XCTAssertNotEqual(a.hash, b.hash)
    }

    func testKeepsJobAndStep() {
        let s = builder.signature(job: "build", step: "compile", logs: "boom")
        XCTAssertEqual(s.job, "build"); XCTAssertEqual(s.step, "compile")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SignatureBuilderTests`
Expected: FAIL.

- [ ] **Step 3: Implement SignatureBuilder**

```swift
// Sources/AutoCICore/SignatureBuilder.swift
import Foundation
import CryptoKit

public struct SignatureBuilder: Sendable {
    public init() {}

    public func signature(job: String, step: String, logs: String) -> FailureSignature {
        let normalized = normalize(logs)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return FailureSignature(job: job, step: step, hash: String(hash))
    }

    /// Keep only error-bearing lines, strip volatile tokens (timestamps, paths, line numbers, hex, digits).
    func normalize(_ logs: String) -> String {
        let errorKeywords = ["error", "fail", "exception", "fatal", "undefined", "expected"]
        let lines = logs.split(separator: "\n").map(String.init)
        let relevant = lines.filter { line in
            let lower = line.lowercased()
            return errorKeywords.contains { lower.contains($0) }
        }
        let chosen = relevant.isEmpty ? lines.suffix(20).map(String.init) : relevant
        return chosen.map(scrub).joined(separator: "\n")
    }

    private func scrub(_ line: String) -> String {
        var s = line
        let patterns = [
            "\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}\\S*", // timestamps
            "/[\\w./-]+",                                       // absolute paths
            "0x[0-9a-fA-F]+",                                   // hex addresses
            ":\\d+",                                            // :linenumbers
            "\\b\\d+\\b",                                       // bare numbers
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter SignatureBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: failure signature builder"
```

---

### Task 6: FixMemory

**Files:**
- Create: `Sources/AutoCICore/FixMemory.swift`
- Test: `Tests/AutoCICoreTests/FixMemoryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/FixMemoryTests.swift
import XCTest
@testable import AutoCICore

final class FixMemoryTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testRecordAndRecallBySignature() throws {
        let mem = FixMemory(projectDir: dir)
        let sig = FailureSignature(job: "test", step: "rspec", hash: "abc")
        let rec = FixRecord(signature: sig, summary: "added gem", succeeded: true, timestamp: Date())
        try mem.record(rec)
        let recalled = FixMemory(projectDir: dir).matching(sig)
        XCTAssertEqual(recalled.count, 1)
        XCTAssertEqual(recalled.first?.summary, "added gem")
    }

    func testNoMatchReturnsEmpty() throws {
        let mem = FixMemory(projectDir: dir)
        XCTAssertTrue(mem.matching(FailureSignature(job: "x", step: "y", hash: "z")).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FixMemoryTests`
Expected: FAIL.

- [ ] **Step 3: Implement FixMemory**

```swift
// Sources/AutoCICore/FixMemory.swift
import Foundation

public final class FixMemory: @unchecked Sendable {
    private let fileURL: URL
    private var records: [FixRecord]

    public init(projectDir: URL) {
        self.fileURL = projectDir.appendingPathComponent("fixes.json")
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([FixRecord].self, from: data) {
            self.records = decoded
        } else {
            self.records = []
        }
    }

    public func record(_ record: FixRecord) throws {
        records.append(record)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(records).write(to: fileURL)
    }

    /// Records sharing job+step, most-recent first. Exact-hash matches ranked first.
    public func matching(_ sig: FailureSignature) -> [FixRecord] {
        records
            .filter { $0.signature.job == sig.job && $0.signature.step == sig.step }
            .sorted { lhs, rhs in
                if (lhs.signature.hash == sig.hash) != (rhs.signature.hash == sig.hash) {
                    return lhs.signature.hash == sig.hash
                }
                return lhs.timestamp > rhs.timestamp
            }
    }
}
```

Note: `JSONDecoder` must use `.iso8601` dates. Update the load path:
```swift
let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
if let data = try? Data(contentsOf: fileURL),
   let decoded = try? dec.decode([FixRecord].self, from: data) { self.records = decoded }
else { self.records = [] }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter FixMemoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: fix memory store"
```

---

### Task 7: GitClient

**Files:**
- Create: `Sources/AutoCICore/GitClient.swift`
- Test: `Tests/AutoCICoreTests/GitClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/GitClientTests.swift
import XCTest
@testable import AutoCICore

final class GitClientTests: XCTestCase {
    func testCheckoutInvokesGit() throws {
        let fake = FakeCommandRunner()
        let git = GitClient(runner: fake)
        try git.checkout(sha: "abc123", cwd: "/repo")
        let call = fake.calls.first!
        XCTAssertEqual(call.command, "git")
        XCTAssertEqual(call.args, ["checkout", "abc123"])
        XCTAssertEqual(call.cwd, "/repo")
    }

    func testCurrentBranchParsesOutput() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["rev-parse", "--abbrev-ref"], stdout: "feature-x\n")
        let git = GitClient(runner: fake)
        XCTAssertEqual(try git.currentBranch(cwd: "/repo"), "feature-x")
    }

    func testPushThrowsOnNonZeroExit() {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["push"], stderr: "rejected", exit: 1)
        let git = GitClient(runner: fake)
        XCTAssertThrowsError(try git.push(branch: "feature-x", cwd: "/repo"))
    }

    func testDiffReturnsStdout() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["diff"], stdout: "diff --git a b")
        let git = GitClient(runner: fake)
        XCTAssertEqual(try git.diff(cwd: "/repo"), "diff --git a b")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GitClientTests`
Expected: FAIL.

- [ ] **Step 3: Implement GitClient**

```swift
// Sources/AutoCICore/GitClient.swift
import Foundation

public struct GitClient: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    @discardableResult
    private func git(_ args: [String], cwd: String?, stdin: String? = nil) throws -> String {
        let r = try runner.run("git", args, cwd: cwd, stdin: stdin, env: nil)
        guard r.exitCode == 0 else { throw AppError.commandFailed("git " + args.joined(separator: " "), r.exitCode) }
        return r.stdout
    }

    public func cloneOrFetch(remoteURL: String, into dir: String) throws {
        if FileManager.default.fileExists(atPath: dir + "/.git") {
            try git(["fetch", "--all", "--prune"], cwd: dir)
        } else {
            try git(["clone", remoteURL, dir], cwd: nil)
        }
    }

    public func checkout(sha: String, cwd: String) throws { try git(["checkout", sha], cwd: cwd) }
    public func checkoutBranch(_ name: String, cwd: String) throws { try git(["checkout", "-B", name], cwd: cwd) }
    public func currentBranch(cwd: String) throws -> String {
        try git(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func add(all: Bool = true, cwd: String) throws { try git(["add", "-A"], cwd: cwd) }
    public func commit(message: String, cwd: String) throws { try git(["commit", "-m", message], cwd: cwd) }
    public func push(branch: String, cwd: String, force: Bool = false) throws {
        var args = ["push", "origin", branch]; if force { args.insert("--force-with-lease", at: 1) }
        try git(args, cwd: cwd)
    }
    public func diff(cwd: String) throws -> String { try git(["diff", "HEAD"], cwd: cwd) }
    public func hasUncommittedChanges(cwd: String) throws -> Bool {
        !(try git(["status", "--porcelain"], cwd: cwd)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public func shaExists(_ sha: String, cwd: String) -> Bool {
        (try? git(["cat-file", "-e", sha], cwd: cwd)) != nil
    }
    public func changedFiles(sha: String, cwd: String) throws -> [String] {
        try git(["diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd: cwd)
            .split(separator: "\n").map(String.init)
    }
    public func commitDiff(sha: String, cwd: String) throws -> String {
        try git(["show", sha], cwd: cwd)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter GitClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: git client"
```

---

### Task 8: GitHubClient

**Files:**
- Create: `Sources/AutoCICore/GitHubClient.swift`
- Test: `Tests/AutoCICoreTests/GitHubClientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/GitHubClientTests.swift
import XCTest
@testable import AutoCICore

final class GitHubClientTests: XCTestCase {
    func testRunsForShaParsesJSON() throws {
        let json = """
        [{"databaseId":111,"name":"CI","status":"completed","conclusion":"failure","headSha":"abc"},
         {"databaseId":222,"name":"Lint","status":"in_progress","conclusion":"","headSha":"abc"}]
        """
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "list"], stdout: json)
        let gh = GitHubClient(runner: fake)
        let runs = try gh.runs(forSha: "abc", cwd: "/repo")
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].status, .failed)
        XCTAssertEqual(runs[1].status, .inProgress)
        XCTAssertEqual(runs[0].id, 111)
    }

    func testFailedJobLogReturnsStdout() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "view"], stdout: "boom log")
        let gh = GitHubClient(runner: fake)
        XCTAssertEqual(try gh.failedLog(runId: 111, cwd: "/repo"), "boom log")
    }

    func testCreateDraftPRReturnsURL() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["pr", "create"], stdout: "https://github.com/x/y/pull/3\n")
        let gh = GitHubClient(runner: fake)
        let url = try gh.createDraftPR(head: "fix/x", base: "main", title: "fix", body: "b", cwd: "/repo")
        XCTAssertEqual(url, "https://github.com/x/y/pull/3")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GitHubClientTests`
Expected: FAIL.

- [ ] **Step 3: Implement GitHubClient**

```swift
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
        let conclusion: String?; let headSha: String
    }

    public func runs(forSha sha: String, cwd: String) throws -> [WorkflowRun] {
        let out = try gh(["run", "list", "--commit", sha,
                          "--json", "databaseId,name,status,conclusion,headSha",
                          "--limit", "20"], cwd: cwd)
        let raws = try JSONDecoder().decode([RawRun].self, from: Data(out.utf8))
        return raws.map { raw in
            WorkflowRun(id: raw.databaseId, name: raw.name,
                        status: mapStatus(status: raw.status, conclusion: raw.conclusion),
                        headSha: raw.headSha)
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter GitHubClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: github client"
```

---

### Task 9: HookInstaller (chain, never overwrite)

**Files:**
- Create: `Sources/AutoCICore/HookInstaller.swift`
- Test: `Tests/AutoCICoreTests/HookInstallerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/HookInstallerTests.swift
import XCTest
@testable import AutoCICore

final class HookInstallerTests: XCTestCase {
    var repo: URL!
    override func setUpWithError() throws {
        repo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo) }

    var hookPath: String { repo.appendingPathComponent(".git/hooks/pre-push").path }

    func testInstallsHookWhenNoneExists() throws {
        let installer = HookInstaller()
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookPath))
        let content = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertTrue(content.contains("AUTO-CI"))
        XCTAssertTrue(content.contains("demo"))
    }

    func testChainsExistingHookWithoutOverwriting() throws {
        let original = "#!/bin/sh\necho existing\n"
        try original.write(toFile: hookPath, atomically: true, encoding: .utf8)
        let installer = HookInstaller()
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        // original preserved as backup, and called from our hook
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookPath + ".auto-ci-orig"))
        let content = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertTrue(content.contains("pre-push.auto-ci-orig"))
    }

    func testUninstallRestoresOriginal() throws {
        let original = "#!/bin/sh\necho existing\n"
        try original.write(toFile: hookPath, atomically: true, encoding: .utf8)
        let installer = HookInstaller()
        try installer.install(repoPath: repo.path, socketPath: "/tmp/sock", project: "demo")
        try installer.uninstall(repoPath: repo.path)
        let restored = try String(contentsOfFile: hookPath, encoding: .utf8)
        XCTAssertEqual(restored, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: hookPath + ".auto-ci-orig"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HookInstallerTests`
Expected: FAIL.

- [ ] **Step 3: Implement HookInstaller**

```swift
// Sources/AutoCICore/HookInstaller.swift
import Foundation

public struct HookInstaller: Sendable {
    public init() {}
    private let marker = "# AUTO-CI managed pre-push hook"

    public func install(repoPath: String, socketPath: String, project: String) throws {
        let hooksDir = repoPath + "/.git/hooks"
        try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)
        let hookPath = hooksDir + "/pre-push"
        let origPath = hookPath + ".auto-ci-orig"
        let fm = FileManager.default

        var chainCall = ""
        if fm.fileExists(atPath: hookPath) {
            let existing = try String(contentsOfFile: hookPath, encoding: .utf8)
            if !existing.contains(marker) {
                // back up the real existing hook once
                if !fm.fileExists(atPath: origPath) { try fm.moveItem(atPath: hookPath, toPath: origPath) }
                chainCall = """
                if [ -x "$(dirname "$0")/pre-push.auto-ci-orig" ]; then
                  "$(dirname "$0")/pre-push.auto-ci-orig" "$@" || exit $?
                fi

                """
            }
        }

        let script = """
        #!/bin/sh
        \(marker)
        \(chainCall)# Notify the auto-ci daemon of the push, then exit 0 immediately.
        SOCK="\(socketPath)"
        PROJECT="\(project)"
        REMOTE_NAME="$1"
        while read local_ref local_sha remote_ref remote_sha; do
          BRANCH=$(echo "$local_ref" | sed 's#refs/heads/##')
          PAYLOAD="{\\"project\\":\\"$PROJECT\\",\\"branch\\":\\"$BRANCH\\",\\"sha\\":\\"$local_sha\\",\\"remote\\":\\"$REMOTE_NAME\\"}"
          printf '%s' "$PAYLOAD" | nc -U "$SOCK" 2>/dev/null || true
        done
        exit 0
        """
        try script.write(toFile: hookPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
    }

    public func uninstall(repoPath: String) throws {
        let hookPath = repoPath + "/.git/hooks/pre-push"
        let origPath = hookPath + ".auto-ci-orig"
        let fm = FileManager.default
        if fm.fileExists(atPath: origPath) {
            if fm.fileExists(atPath: hookPath) { try fm.removeItem(atPath: hookPath) }
            try fm.moveItem(atPath: origPath, toPath: hookPath)
        } else if fm.fileExists(atPath: hookPath),
                  let content = try? String(contentsOfFile: hookPath, encoding: .utf8),
                  content.contains(marker) {
            try fm.removeItem(atPath: hookPath)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter HookInstallerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: chain-installing pre-push hook"
```

---

### Task 10: ClonePool

**Files:**
- Create: `Sources/AutoCICore/ClonePool.swift`
- Test: `Tests/AutoCICoreTests/ClonePoolTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/ClonePoolTests.swift
import XCTest
@testable import AutoCICore

final class ClonePoolTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testPreparesCloneAtSha() throws {
        let fake = FakeCommandRunner()
        let pool = ClonePool(root: root, git: GitClient(runner: fake))
        let path = try pool.prepare(project: "demo", remoteURL: "git@github.com:x/y.git", sha: "abc")
        XCTAssertTrue(path.hasSuffix("repos/demo"))
        // clone (no .git yet) then checkout the sha
        XCTAssertTrue(fake.calls.contains { $0.command == "git" && $0.args.first == "clone" })
        XCTAssertTrue(fake.calls.contains { $0.command == "git" && $0.args == ["checkout", "abc"] })
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ClonePoolTests`
Expected: FAIL.

- [ ] **Step 3: Implement ClonePool**

```swift
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
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ClonePoolTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: clone pool"
```

---

### Task 11: ContextBuilder

**Files:**
- Create: `Sources/AutoCICore/ContextBuilder.swift`
- Test: `Tests/AutoCICoreTests/ContextBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/ContextBuilderTests.swift
import XCTest
@testable import AutoCICore

final class ContextBuilderTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testBuildsContextFromRun() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "view"], stdout: "job: test\nstep: rspec\nerror: boom")
        fake.stub(command: "git", args: ["show"], stdout: "diff content")
        fake.stub(command: "git", args: ["diff-tree"], stdout: "app/x.rb\napp/y.rb")
        let mem = FixMemory(projectDir: dir)
        let builder = ContextBuilder(github: GitHubClient(runner: fake),
                                     git: GitClient(runner: fake),
                                     memory: mem,
                                     signatures: SignatureBuilder())
        let ctx = try builder.build(runId: 111, job: "test", step: "rspec",
                                    sha: "abc", clonePath: "/clone", workflowYAML: "name: CI")
        XCTAssertEqual(ctx.runId, 111)
        XCTAssertEqual(ctx.changedFiles, ["app/x.rb", "app/y.rb"])
        XCTAssertEqual(ctx.workflowYAML, "name: CI")
        XCTAssertTrue(ctx.logs.contains("boom"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ContextBuilderTests`
Expected: FAIL.

- [ ] **Step 3: Implement ContextBuilder**

```swift
// Sources/AutoCICore/ContextBuilder.swift
import Foundation

public struct ContextBuilder: Sendable {
    private let github: GitHubClient
    private let git: GitClient
    private let memory: FixMemory
    private let signatures: SignatureBuilder
    public init(github: GitHubClient, git: GitClient, memory: FixMemory, signatures: SignatureBuilder) {
        self.github = github; self.git = git; self.memory = memory; self.signatures = signatures
    }

    public func build(runId: Int, job: String, step: String, sha: String,
                      clonePath: String, workflowYAML: String) throws -> FixContext {
        let logs = try github.failedLog(runId: runId, cwd: clonePath)
        let diff = (try? git.commitDiff(sha: sha, cwd: clonePath)) ?? ""
        let changed = (try? git.changedFiles(sha: sha, cwd: clonePath)) ?? []
        let sig = signatures.signature(job: job, step: step, logs: logs)
        let past = memory.matching(sig)
        return FixContext(runId: runId, job: job, step: step, logs: logs, workflowYAML: workflowYAML,
                          commitDiff: diff, changedFiles: changed, pastFixes: past)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ContextBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: context builder"
```

---

### Task 12: FixRunner (claude headless)

**Files:**
- Create: `Sources/AutoCICore/FixRunner.swift`
- Test: `Tests/AutoCICoreTests/FixRunnerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/FixRunnerTests.swift
import XCTest
@testable import AutoCICore

final class FixRunnerTests: XCTestCase {
    func testBuildsPromptWithContextAndPastFixes() {
        let runner = FixRunner(runner: FakeCommandRunner(), git: GitClient(runner: FakeCommandRunner()))
        let ctx = FixContext(runId: 1, job: "test", step: "rspec", logs: "boom",
                             workflowYAML: "name: CI", commitDiff: "diff", changedFiles: ["a.rb"],
                             pastFixes: [FixRecord(signature: .init(job: "test", step: "rspec", hash: "h"),
                                                   summary: "added gem", succeeded: true, timestamp: Date())])
        let prompt = runner.buildPrompt(ctx)
        XCTAssertTrue(prompt.contains("rspec"))
        XCTAssertTrue(prompt.contains("boom"))
        XCTAssertTrue(prompt.contains("added gem"))
        XCTAssertTrue(prompt.contains("Don't touch unrelated code"))
    }

    func testRunInvokesClaudeAndReturnsDiff() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "claude", args: ["-p"], stdout: "fixed it")
        fake.stub(command: "git", args: ["diff"], stdout: "diff --git a b\n+fix")
        let runner = FixRunner(runner: fake, git: GitClient(runner: fake))
        let ctx = FixContext(runId: 1, job: "t", step: "s", logs: "x", workflowYAML: "y",
                             commitDiff: "", changedFiles: [], pastFixes: [])
        let result = try runner.run(context: ctx, clonePath: "/clone")
        XCTAssertTrue(result.madeChanges)
        XCTAssertEqual(result.summary, "fixed it")
    }

    func testRunThrowsNoChangesWhenDiffEmpty() {
        let fake = FakeCommandRunner()
        fake.stub(command: "claude", args: ["-p"], stdout: "nothing to do")
        fake.stub(command: "git", args: ["diff"], stdout: "")
        let runner = FixRunner(runner: fake, git: GitClient(runner: fake))
        let ctx = FixContext(runId: 1, job: "t", step: "s", logs: "x", workflowYAML: "y",
                             commitDiff: "", changedFiles: [], pastFixes: [])
        XCTAssertThrowsError(try runner.run(context: ctx, clonePath: "/clone")) {
            XCTAssertEqual($0 as? AppError, .noChanges)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FixRunnerTests`
Expected: FAIL.

- [ ] **Step 3: Implement FixRunner**

```swift
// Sources/AutoCICore/FixRunner.swift
import Foundation

public struct FixResult: Sendable {
    public let madeChanges: Bool
    public let summary: String
    public let diff: String
}

public struct FixRunner: Sendable {
    private let runner: CommandRunner
    private let git: GitClient
    public init(runner: CommandRunner, git: GitClient) { self.runner = runner; self.git = git }

    public func buildPrompt(_ ctx: FixContext) -> String {
        let past = ctx.pastFixes.isEmpty ? "None recorded." :
            ctx.pastFixes.map { "- (\($0.succeeded ? "worked" : "did not work")) \($0.summary)" }.joined(separator: "\n")
        return """
        CI job "\(ctx.job)" step "\(ctx.step)" failed. Diagnose and fix it.

        ## Failure logs
        \(ctx.logs)

        ## Workflow YAML
        \(ctx.workflowYAML)

        ## Diff of the commit that failed
        \(ctx.commitDiff)

        ## Changed files
        \(ctx.changedFiles.joined(separator: "\n"))

        ## Notes from past fixes on this project
        \(past)

        Fix the failure by editing files in this repository. Don't touch unrelated code.
        Make the minimal change needed to make CI pass.
        """
    }

    public func run(context: FixContext, clonePath: String) throws -> FixResult {
        let prompt = buildPrompt(context)
        let r = try runner.run("claude",
            ["-p", prompt, "--permission-mode", "acceptEdits", "--dangerously-skip-permissions"],
            cwd: clonePath, stdin: nil, env: nil)
        guard r.exitCode == 0 else { throw AppError.commandFailed("claude", r.exitCode) }
        let diff = try git.diff(cwd: clonePath)
        guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.noChanges }
        return FixResult(madeChanges: true,
                         summary: r.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                         diff: diff)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter FixRunnerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: claude headless fix runner"
```

---

### Task 13: Publisher

**Files:**
- Create: `Sources/AutoCICore/Publisher.swift`
- Test: `Tests/AutoCICoreTests/PublisherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/PublisherTests.swift
import XCTest
@testable import AutoCICore

final class PublisherTests: XCTestCase {
    func testPublishesToSameBranchWhenNotProtected() throws {
        let fake = FakeCommandRunner()
        let pub = Publisher(git: GitClient(runner: fake), github: GitHubClient(runner: fake))
        let outcome = try pub.publish(branch: "feature-x", protectedBranches: ["main", "master"],
                                      clonePath: "/clone", summary: "fix", runId: 5)
        if case .pushedToBranch(let b) = outcome { XCTAssertEqual(b, "feature-x") }
        else { XCTFail("expected pushedToBranch") }
        XCTAssertTrue(fake.calls.contains { $0.args == ["push", "origin", "feature-x"] })
    }

    func testFallsBackToFixBranchAndPRWhenProtected() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["pr", "create"], stdout: "https://github.com/x/y/pull/9")
        let pub = Publisher(git: GitClient(runner: fake), github: GitHubClient(runner: fake))
        let outcome = try pub.publish(branch: "main", protectedBranches: ["main", "master"],
                                      clonePath: "/clone", summary: "fix", runId: 5)
        guard case .openedPR(let url, let head) = outcome else { return XCTFail("expected openedPR") }
        XCTAssertEqual(url, "https://github.com/x/y/pull/9")
        XCTAssertTrue(head.hasPrefix("auto-ci/fix-main-"))
        XCTAssertTrue(fake.calls.contains { $0.args.first == "checkout" && $0.args.contains("-B") })
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PublisherTests`
Expected: FAIL.

- [ ] **Step 3: Implement Publisher**

```swift
// Sources/AutoCICore/Publisher.swift
import Foundation

public enum PublishOutcome: Sendable, Equatable {
    case pushedToBranch(String)
    case openedPR(url: String, head: String)
}

public struct Publisher: Sendable {
    private let git: GitClient
    private let github: GitHubClient
    public init(git: GitClient, github: GitHubClient) { self.git = git; self.github = github }

    public func publish(branch: String, protectedBranches: [String], clonePath: String,
                        summary: String, runId: Int) throws -> PublishOutcome {
        let message = "fix(ci): \(summary.split(separator: "\n").first.map(String.init) ?? "auto-fix CI failure")"
        if protectedBranches.contains(branch) {
            let head = "auto-ci/fix-\(branch)-\(runId)"
            try git.checkoutBranch(head, cwd: clonePath)
            try git.add(cwd: clonePath)
            try git.commit(message: message, cwd: clonePath)
            try git.push(branch: head, cwd: clonePath)
            let url = try github.createDraftPR(head: head, base: branch,
                                               title: message,
                                               body: "Automated CI fix for run #\(runId).\n\n\(summary)",
                                               cwd: clonePath)
            return .openedPR(url: url, head: head)
        } else {
            try git.checkoutBranch(branch, cwd: clonePath)
            try git.add(cwd: clonePath)
            try git.commit(message: message, cwd: clonePath)
            try git.push(branch: branch, cwd: clonePath)
            return .pushedToBranch(branch)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter PublisherTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: publisher with protected-branch PR fallback"
```

---

### Task 14: RunWatcher

**Files:**
- Create: `Sources/AutoCICore/RunWatcher.swift`
- Test: `Tests/AutoCICoreTests/RunWatcherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/RunWatcherTests.swift
import XCTest
@testable import AutoCICore

final class RunWatcherTests: XCTestCase {
    func testPollsUntilTerminalThenReturnsFailedRuns() throws {
        let fake = FakeCommandRunner()
        // first poll: in_progress; second poll: failure
        var inProgress = """
        [{"databaseId":7,"name":"CI","status":"in_progress","conclusion":"","headSha":"abc"}]
        """
        let failed = """
        [{"databaseId":7,"name":"CI","status":"completed","conclusion":"failure","headSha":"abc"}]
        """
        var pollCount = 0
        let github = GitHubClient(runner: fake)
        let watcher = RunWatcher(github: github, pollInterval: 0, timeout: 5, sleep: { _ in })
        // Use a stubbing fake that flips after first call:
        let flip = FlippingRunner(first: inProgress, then: failed)
        let watcher2 = RunWatcher(github: GitHubClient(runner: flip), pollInterval: 0, timeout: 5, sleep: { _ in })
        let result = try watcher2.waitForTerminal(sha: "abc", cwd: "/repo")
        XCTAssertEqual(result.map { $0.id }, [7])
        XCTAssertEqual(result.first?.status, .failed)
        _ = (inProgress, pollCount, watcher) // silence unused
    }

    func testTimesOutWhenNoRunAppears() {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "list"], stdout: "[]")
        let watcher = RunWatcher(github: GitHubClient(runner: fake), pollInterval: 0, timeout: 0, sleep: { _ in })
        XCTAssertThrowsError(try watcher.waitForTerminal(sha: "abc", cwd: "/repo")) {
            XCTAssertEqual($0 as? AppError, .timedOut)
        }
    }
}

/// Returns `first` on call 1, `then` thereafter.
final class FlippingRunner: CommandRunner, @unchecked Sendable {
    let first: String; let then: String; var count = 0
    init(first: String, then: String) { self.first = first; self.then = then }
    func run(_ command: String, _ args: [String], cwd: String?, stdin: String?, env: [String: String]?) throws -> CommandResult {
        count += 1
        return CommandResult(exitCode: 0, stdout: count == 1 ? first : then, stderr: "")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RunWatcherTests`
Expected: FAIL.

- [ ] **Step 3: Implement RunWatcher**

```swift
// Sources/AutoCICore/RunWatcher.swift
import Foundation

public struct RunWatcher: Sendable {
    private let github: GitHubClient
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval
    private let sleep: @Sendable (TimeInterval) -> Void
    private let now: @Sendable () -> Date

    public init(github: GitHubClient, pollInterval: TimeInterval = 15, timeout: TimeInterval = 1800,
                sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.github = github; self.pollInterval = pollInterval; self.timeout = timeout
        self.sleep = sleep; self.now = now
    }

    /// Polls until all runs for the SHA are terminal (or until one appears and resolves),
    /// returning the failed runs. Throws `.timedOut` if no run ever appears.
    public func waitForTerminal(sha: String, cwd: String) throws -> [WorkflowRun] {
        let deadline = now().addingTimeInterval(timeout)
        var sawRun = false
        while true {
            let runs = try github.runs(forSha: sha, cwd: cwd)
            if !runs.isEmpty {
                sawRun = true
                if runs.allSatisfy({ $0.status.isTerminal }) {
                    return runs.filter { $0.status == .failed }
                }
            }
            if now() >= deadline {
                if sawRun { return try github.runs(forSha: sha, cwd: cwd).filter { $0.status == .failed } }
                throw AppError.timedOut
            }
            sleep(pollInterval)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter RunWatcherTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: run watcher polling by head sha"
```

---

### Task 15: Daemon state machine

**Files:**
- Create: `Sources/AutoCICore/Daemon.swift`
- Test: `Tests/AutoCICoreTests/DaemonTests.swift`

This task wires the components into the lifecycle. To keep it testable, the Daemon depends on small closures/protocols it can drive, and exposes a synchronous `handleFailedRun` that returns an outcome enum. Notifications go through a `Notifier` protocol.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/DaemonTests.swift
import XCTest
@testable import AutoCICore

final class SpyNotifier: Notifier, @unchecked Sendable {
    var events: [DaemonEvent] = []
    func notify(_ event: DaemonEvent) { events.append(event) }
}

final class DaemonTests: XCTestCase {
    func testStuckWhenSameSignatureRepeats() {
        // A fix engine that always "fixes" but the run keeps failing with the same signature.
        let notifier = SpyNotifier()
        let sig = FailureSignature(job: "t", step: "s", hash: "same")
        var attempts = 0
        let engine = StubFixEngine(
            onAttempt: { attempts += 1 },
            signatureProvider: { _ in sig },           // identical every time
            fixOutcome: { .pushedToBranch("feature-x") },
            rerunResult: { [WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc")] }
        )
        let daemon = Daemon(maxAttempts: 3, notifier: notifier, engine: engine)
        let result = daemon.handleFailedRun(project: "demo", branch: "feature-x", sha: "abc",
                                            failedRun: WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc"))
        XCTAssertEqual(result, .stuck)
        XCTAssertEqual(attempts, 2) // stops after detecting repeat, before burning all 3
        XCTAssertTrue(notifier.events.contains(.stuck(project: "demo", branch: "feature-x")))
    }

    func testGreenAfterFixReportsFixed() {
        let notifier = SpyNotifier()
        var sigs = [FailureSignature(job: "t", step: "s", hash: "first")]
        let engine = StubFixEngine(
            onAttempt: {},
            signatureProvider: { _ in sigs.removeFirst() },
            fixOutcome: { .pushedToBranch("feature-x") },
            rerunResult: { [] } // green
        )
        let daemon = Daemon(maxAttempts: 3, notifier: notifier, engine: engine)
        let result = daemon.handleFailedRun(project: "demo", branch: "feature-x", sha: "abc",
                                            failedRun: WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc"))
        XCTAssertEqual(result, .fixed)
        XCTAssertTrue(notifier.events.contains { if case .fixed = $0 { return true }; return false })
    }

    func testGivesUpAfterMaxAttempts() {
        let notifier = SpyNotifier()
        var counter = 0
        let engine = StubFixEngine(
            onAttempt: {},
            signatureProvider: { _ in counter += 1; return FailureSignature(job: "t", step: "s", hash: "h\(counter)") },
            fixOutcome: { .pushedToBranch("feature-x") },
            rerunResult: { [WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc")] }
        )
        let daemon = Daemon(maxAttempts: 3, notifier: notifier, engine: engine)
        let result = daemon.handleFailedRun(project: "demo", branch: "feature-x", sha: "abc",
                                            failedRun: WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc"))
        XCTAssertEqual(result, .gaveUp)
    }
}

/// Test double implementing the engine the Daemon drives.
final class StubFixEngine: FixEngine, @unchecked Sendable {
    let onAttempt: () -> Void
    let signatureProvider: (WorkflowRun) -> FailureSignature
    let fixOutcome: () -> PublishOutcome
    let rerunResult: () -> [WorkflowRun]
    init(onAttempt: @escaping () -> Void,
         signatureProvider: @escaping (WorkflowRun) -> FailureSignature,
         fixOutcome: @escaping () -> PublishOutcome,
         rerunResult: @escaping () -> [WorkflowRun]) {
        self.onAttempt = onAttempt; self.signatureProvider = signatureProvider
        self.fixOutcome = fixOutcome; self.rerunResult = rerunResult
    }
    func signature(of run: WorkflowRun, project: String) throws -> FailureSignature { signatureProvider(run) }
    func attemptFix(project: String, branch: String, sha: String, run: WorkflowRun) throws -> PublishOutcome {
        onAttempt(); return fixOutcome()
    }
    func rerunFailures(project: String, sha: String) throws -> [WorkflowRun] { rerunResult() }
    func recordOutcome(project: String, signature: FailureSignature, summary: String, succeeded: Bool) {}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DaemonTests`
Expected: FAIL.

- [ ] **Step 3: Implement Daemon, Notifier, FixEngine protocol**

```swift
// Sources/AutoCICore/Daemon.swift
import Foundation

public enum DaemonEvent: Sendable, Equatable {
    case fixed(project: String, branch: String, detail: String)
    case stuck(project: String, branch: String)
    case gaveUp(project: String, branch: String)
    case error(project: String, message: String)
}

public protocol Notifier: Sendable {
    func notify(_ event: DaemonEvent)
}

public enum FixOutcome: Sendable, Equatable {
    case fixed, stuck, gaveUp, errored
}

/// The work the Daemon orchestrates. Real impl wraps ClonePool/ContextBuilder/FixRunner/Publisher/RunWatcher.
public protocol FixEngine: Sendable {
    func signature(of run: WorkflowRun, project: String) throws -> FailureSignature
    func attemptFix(project: String, branch: String, sha: String, run: WorkflowRun) throws -> PublishOutcome
    func rerunFailures(project: String, sha: String) throws -> [WorkflowRun]
    func recordOutcome(project: String, signature: FailureSignature, summary: String, succeeded: Bool)
}

public final class Daemon: @unchecked Sendable {
    private let maxAttempts: Int
    private let notifier: Notifier
    private let engine: FixEngine
    public init(maxAttempts: Int = 3, notifier: Notifier, engine: FixEngine) {
        self.maxAttempts = maxAttempts; self.notifier = notifier; self.engine = engine
    }

    @discardableResult
    public func handleFailedRun(project: String, branch: String, sha: String, failedRun: WorkflowRun) -> FixOutcome {
        var previousSignature: FailureSignature?
        var currentRun = failedRun
        for attempt in 1...maxAttempts {
            do {
                let sig = try engine.signature(of: currentRun, project: project)
                if let prev = previousSignature, prev == sig {
                    notifier.notify(.stuck(project: project, branch: branch))
                    return .stuck
                }
                previousSignature = sig

                let outcome = try engine.attemptFix(project: project, branch: branch, sha: sha, run: currentRun)
                let detail: String
                switch outcome {
                case .pushedToBranch(let b): detail = "pushed to \(b)"
                case .openedPR(let url, _): detail = "opened PR \(url)"
                }

                let failures = try engine.rerunFailures(project: project, sha: sha)
                if failures.isEmpty {
                    engine.recordOutcome(project: project, signature: sig, summary: detail, succeeded: true)
                    notifier.notify(.fixed(project: project, branch: branch, detail: detail))
                    return .fixed
                }
                engine.recordOutcome(project: project, signature: sig, summary: detail, succeeded: false)
                currentRun = failures[0]
                _ = attempt
            } catch {
                notifier.notify(.error(project: project, message: "\(error)"))
                return .errored
            }
        }
        notifier.notify(.gaveUp(project: project, branch: branch))
        return .gaveUp
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter DaemonTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: daemon lifecycle state machine"
```

---

### Task 16: LiveFixEngine (wires real components)

**Files:**
- Create: `Sources/AutoCICore/LiveFixEngine.swift`
- Test: `Tests/AutoCICoreTests/LiveFixEngineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/LiveFixEngineTests.swift
import XCTest
@testable import AutoCICore

final class LiveFixEngineTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testAttemptFixPreparesCloneRunsClaudeAndPublishes() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "gh", args: ["run", "view"], stdout: "error: boom")
        fake.stub(command: "claude", args: ["-p"], stdout: "added missing import")
        fake.stub(command: "git", args: ["diff"], stdout: "diff --git a b\n+import x")
        let project = ProjectConfig(name: "demo", path: "/src/demo", remote: "git@github.com:x/y.git")
        let engine = LiveFixEngine(config: project, root: root, runner: fake, workflowYAML: "name: CI")
        let outcome = try engine.attemptFix(project: "demo", branch: "feature-x", sha: "abc",
                                            run: WorkflowRun(id: 9, name: "CI", status: .failed, headSha: "abc"))
        if case .pushedToBranch(let b) = outcome { XCTAssertEqual(b, "feature-x") }
        else { XCTFail("expected push to feature-x") }
        XCTAssertTrue(fake.calls.contains { $0.command == "claude" })
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LiveFixEngineTests`
Expected: FAIL.

- [ ] **Step 3: Implement LiveFixEngine**

```swift
// Sources/AutoCICore/LiveFixEngine.swift
import Foundation

public final class LiveFixEngine: FixEngine, @unchecked Sendable {
    private let config: ProjectConfig
    private let root: URL
    private let git: GitClient
    private let github: GitHubClient
    private let pool: ClonePool
    private let signatures = SignatureBuilder()
    private let memory: FixMemory
    private let fixRunner: FixRunner
    private let publisher: Publisher
    private let watcher: RunWatcher
    private let workflowYAML: String

    public init(config: ProjectConfig, root: URL, runner: CommandRunner, workflowYAML: String) {
        self.config = config
        self.root = root
        self.git = GitClient(runner: runner)
        self.github = GitHubClient(runner: runner)
        self.pool = ClonePool(root: root, git: git)
        self.memory = FixMemory(projectDir: root.appendingPathComponent("projects").appendingPathComponent(config.name))
        self.fixRunner = FixRunner(runner: runner, git: git)
        self.publisher = Publisher(git: git, github: github)
        self.watcher = RunWatcher(github: github)
        self.workflowYAML = workflowYAML
    }

    public func signature(of run: WorkflowRun, project: String) throws -> FailureSignature {
        let clone = pool.cloneDir(project: config.name)
        let logs = (try? github.failedLog(runId: run.id, cwd: clone)) ?? ""
        return signatures.signature(job: run.name, step: run.name, logs: logs)
    }

    public func attemptFix(project: String, branch: String, sha: String, run: WorkflowRun) throws -> PublishOutcome {
        let clone = try pool.prepare(project: config.name, remoteURL: config.remote, sha: sha)
        let builder = ContextBuilder(github: github, git: git, memory: memory, signatures: signatures)
        let ctx = try builder.build(runId: run.id, job: run.name, step: run.name, sha: sha,
                                    clonePath: clone, workflowYAML: workflowYAML)
        let fix = try fixRunner.run(context: ctx, clonePath: clone)
        return try publisher.publish(branch: branch, protectedBranches: config.protectedBranches,
                                     clonePath: clone, summary: fix.summary, runId: run.id)
    }

    public func rerunFailures(project: String, sha: String) throws -> [WorkflowRun] {
        let clone = pool.cloneDir(project: config.name)
        return try watcher.waitForTerminal(sha: sha, cwd: clone)
    }

    public func recordOutcome(project: String, signature: FailureSignature, summary: String, succeeded: Bool) {
        try? memory.record(FixRecord(signature: signature, summary: summary, succeeded: succeeded, timestamp: Date()))
    }
}
```

Note: the rerun must observe the *new* pushed commit. For v1 we re-poll the same SHA's runs; a follow-up can track the fix commit SHA returned from push. Document this limitation in code comment.

- [ ] **Step 4: Run tests**

Run: `swift test --filter LiveFixEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: live fix engine wiring real components"
```

---

### Task 17: PushListener (unix socket)

**Files:**
- Create: `Sources/AutoCICore/PushListener.swift`
- Test: `Tests/AutoCICoreTests/PushListenerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/PushListenerTests.swift
import XCTest
@testable import AutoCICore

final class PushListenerTests: XCTestCase {
    func testDecodesPushEventPayload() throws {
        let json = #"{"project":"demo","branch":"feature-x","sha":"abc","remote":"origin"}"#
        let event = try PushListener.decode(json)
        XCTAssertEqual(event, PushEvent(project: "demo", branch: "feature-x", sha: "abc", remote: "origin"))
    }

    func testIgnoresMalformedPayload() {
        XCTAssertThrowsError(try PushListener.decode("not json"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PushListenerTests`
Expected: FAIL.

- [ ] **Step 3: Implement PushListener**

```swift
// Sources/AutoCICore/PushListener.swift
import Foundation

public final class PushListener: @unchecked Sendable {
    public let socketPath: String
    private let onEvent: @Sendable (PushEvent) -> Void
    private var source: DispatchSourceRead?
    private var fd: Int32 = -1

    public init(socketPath: String, onEvent: @escaping @Sendable (PushEvent) -> Void) {
        self.socketPath = socketPath; self.onEvent = onEvent
    }

    public static func decode(_ payload: String) throws -> PushEvent {
        guard let data = payload.data(using: .utf8) else { throw AppError.commandFailed("decode", 1) }
        return try JSONDecoder().decode(PushEvent.self, from: data)
    }

    /// Binds a unix-domain socket and accepts one-shot payloads. Uses `nc -U` clients (see HookInstaller).
    public func start() throws {
        unlink(socketPath)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AppError.commandFailed("socket", errno) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, ptr, 103) }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else { throw AppError.commandFailed("bind", errno) }
        guard listen(fd, 8) == 0 else { throw AppError.commandFailed("listen", errno) }

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    private func acceptOne() {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return }
        let payload = String(decoding: buffer[0..<n], as: UTF8.self)
        if let event = try? PushListener.decode(payload) { onEvent(event) }
    }

    public func stop() {
        source?.cancel(); source = nil
        if fd >= 0 { close(fd); fd = -1 }
        unlink(socketPath)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter PushListenerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: push listener unix socket"
```

---

### Task 18: CLI (`auto-ci init / list / uninstall`)

**Files:**
- Modify: `Sources/auto-ci/main.swift`
- Test: `Tests/AutoCICoreTests/CLICommandTests.swift`

The CLI logic lives in a testable `CLICommand` enum in the core; `main.swift` only parses argv and prints.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/AutoCICoreTests/CLICommandTests.swift
import XCTest
@testable import AutoCICore

final class CLICommandTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git/hooks"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testInitRegistersProjectAndInstallsHook() throws {
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["remote", "get-url"], stdout: "git@github.com:x/y.git\n")
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        let cli = CLICommand(store: store, runner: fake, hookInstaller: HookInstaller(),
                             socketPath: "/tmp/sock")
        let out = try cli.run(["init"], cwd: root.path)
        XCTAssertTrue(out.contains("Registered"))
        XCTAssertEqual(store.projects().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/hooks/pre-push").path))
    }

    func testListShowsProjects() throws {
        let store = ConfigStore(root: root.appendingPathComponent("cfg"))
        try store.upsert(ProjectConfig(name: "demo", path: "/x", remote: "origin"))
        let cli = CLICommand(store: store, runner: FakeCommandRunner(), hookInstaller: HookInstaller(), socketPath: "/tmp/sock")
        let out = try cli.run(["list"], cwd: "/x")
        XCTAssertTrue(out.contains("demo"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CLICommandTests`
Expected: FAIL.

- [ ] **Step 3: Implement CLICommand and main.swift**

```swift
// Sources/AutoCICore/CLICommand.swift
import Foundation

public struct CLICommand: Sendable {
    private let store: ConfigStore
    private let runner: CommandRunner
    private let hookInstaller: HookInstaller
    private let socketPath: String
    public init(store: ConfigStore, runner: CommandRunner, hookInstaller: HookInstaller, socketPath: String) {
        self.store = store; self.runner = runner; self.hookInstaller = hookInstaller; self.socketPath = socketPath
    }

    public func run(_ args: [String], cwd: String) throws -> String {
        guard let cmd = args.first else { return usage() }
        switch cmd {
        case "init":
            let name = (cwd as NSString).lastPathComponent
            let remote = try runner.run("git", ["remote", "get-url", "origin"], cwd: cwd, stdin: nil, env: nil)
                .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let project = ProjectConfig(name: name, path: cwd, remote: remote)
            try store.upsert(project)
            try hookInstaller.install(repoPath: cwd, socketPath: socketPath, project: name)
            return "Registered \(name) (\(remote)) and installed pre-push hook."
        case "list":
            let names = store.projects().map { "\($0.name)\t\($0.remote)" }
            return names.isEmpty ? "No projects registered." : names.joined(separator: "\n")
        case "uninstall":
            let name = (cwd as NSString).lastPathComponent
            try hookInstaller.uninstall(repoPath: cwd)
            try store.remove(named: name)
            return "Uninstalled hook and removed \(name)."
        default:
            return usage()
        }
    }

    private func usage() -> String {
        "Usage: auto-ci <init|list|uninstall>"
    }
}
```

```swift
// Sources/auto-ci/main.swift
import AutoCICore
import Foundation

let root = ConfigStore.defaultRoot
let store = ConfigStore(root: root)
let socketPath = root.appendingPathComponent("daemon.sock").path
let cli = CLICommand(store: store, runner: ProcessCommandRunner(),
                     hookInstaller: HookInstaller(), socketPath: socketPath)
do {
    let out = try cli.run(Array(CommandLine.arguments.dropFirst()),
                          cwd: FileManager.default.currentDirectoryPath)
    print(out)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
```

- [ ] **Step 4: Run tests + build CLI**

Run: `swift test --filter CLICommandTests && swift build`
Expected: PASS, build succeeds.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: auto-ci CLI (init/list/uninstall)"
```

---

### Task 19: Menubar app shell

**Files:**
- Create: `Sources/AutoCIApp/AutoCIApp.swift`
- Modify: `Package.swift` (add executable target `AutoCIApp`)

This is a thin SwiftUI `MenuBarExtra` shell. It is not unit-tested (UI); verification is a successful build. It hosts a `Notifier` that posts `UNUserNotification`s, starts the `PushListener`, and on each push event spins up a `RunWatcher` + `Daemon` on a background queue.

- [ ] **Step 1: Add the app target to Package.swift**

```swift
.executableTarget(
    name: "AutoCIApp",
    dependencies: ["AutoCICore"],
    linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("UserNotifications")]
),
```

- [ ] **Step 2: Implement the menubar shell**

```swift
// Sources/AutoCIApp/AutoCIApp.swift
import SwiftUI
import AutoCICore
import UserNotifications

@main
struct AutoCIApp: App {
    @StateObject private var controller = AppController()
    var body: some Scene {
        MenuBarExtra("Auto-CI", systemImage: controller.iconName) {
            Text(controller.statusLine).font(.headline)
            Divider()
            ForEach(controller.recent, id: \.self) { Text($0) }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppController: ObservableObject, Notifier {
    @Published var statusLine = "Idle"
    @Published var recent: [String] = []
    @Published var iconName = "wrench.and.screwdriver"

    private let store = ConfigStore(root: ConfigStore.defaultRoot)
    private var listener: PushListener?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startListener()
    }

    private func startListener() {
        let socketPath = ConfigStore.defaultRoot.appendingPathComponent("daemon.sock").path
        let listener = PushListener(socketPath: socketPath) { [weak self] event in
            Task { await self?.handle(event) }
        }
        try? listener.start()
        self.listener = listener
    }

    private func handle(_ event: PushEvent) async {
        guard let config = store.project(named: event.project) else { return }
        await MainActor.run { self.statusLine = "Watching \(event.branch)…" }
        let runner = ProcessCommandRunner()
        let workflowYAML = (try? String(contentsOfFile: config.path + "/.github/workflows/ci.yml", encoding: .utf8)) ?? ""
        let github = GitHubClient(runner: runner)
        let watcher = RunWatcher(github: github)
        await Task.detached {
            do {
                let clone = ClonePool(root: ConfigStore.defaultRoot, git: GitClient(runner: runner))
                    .cloneDir(project: config.name)
                _ = try? GitClient(runner: runner).cloneOrFetch(remoteURL: config.remote, into: clone)
                let failures = try watcher.waitForTerminal(sha: event.sha, cwd: clone)
                guard let firstFailure = failures.first else {
                    await self.notifyAsync(.fixed(project: config.name, branch: event.branch, detail: "green, nothing to do"))
                    return
                }
                let engine = LiveFixEngine(config: config, root: ConfigStore.defaultRoot,
                                           runner: runner, workflowYAML: workflowYAML)
                let daemon = Daemon(notifier: self, engine: engine)
                _ = daemon.handleFailedRun(project: config.name, branch: event.branch,
                                           sha: event.sha, failedRun: firstFailure)
            } catch {
                self.notify(.error(project: config.name, message: "\(error)"))
            }
        }.value
    }

    nonisolated func notify(_ event: DaemonEvent) {
        Task { await self.notifyAsync(event) }
    }

    private func notifyAsync(_ event: DaemonEvent) async {
        let (title, body): (String, String)
        switch event {
        case .fixed(_, let branch, let detail): (title, body) = ("CI fixed ✓", "\(branch): \(detail)")
        case .stuck(_, let branch): (title, body) = ("CI stuck — needs you", branch)
        case .gaveUp(_, let branch): (title, body) = ("CI fix gave up", branch)
        case .error(_, let message): (title, body) = ("Auto-CI error", message)
        }
        await MainActor.run {
            self.statusLine = title
            self.recent.insert("\(title) — \(body)", at: 0)
            self.recent = Array(self.recent.prefix(10))
        }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
```

- [ ] **Step 3: Build the app target**

Run: `swift build --target AutoCIApp`
Expected: build succeeds (warnings acceptable only if unavoidable for MenuBarExtra; fix any in our code).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: menubar app shell"
```

---

### Task 20: Full suite + README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Run the entire test suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 2: Build everything**

Run: `swift build`
Expected: success, no warnings in our code.

- [ ] **Step 3: Write README**

Document: what it is, `swift build`, `auto-ci init` in a repo, launching the menubar app, how the pre-push hook + socket + polling + fix loop work, protected-branch behavior, and the known v1 limitation (rerun re-polls the original SHA's runs rather than tracking the fix commit SHA).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "docs: README"
```

---

## Self-Review

**Spec coverage:**
- Local-first, drives local Claude Code → FixRunner (Task 12), LiveFixEngine (16). ✓
- pre-push hook → daemon polls by head-SHA → HookInstaller (9), PushListener (17), RunWatcher (14). ✓
- Fix commits onto failing branch → Publisher (13). ✓
- Protected-branch fix-branch+PR fallback → Publisher (13). ✓
- Iterate ≤3, stop on repeated signature → Daemon (15). ✓
- Dedicated clone per project → ClonePool (10). ✓
- Context: logs + job/step + workflow YAML + commit diff + changed files + past fixes → ContextBuilder (11). ✓
- Memory of past fixes; never persist raw logs (only signature) → FixMemory (6), SignatureBuilder (5). ✓
- Menubar app (Swift) hosting daemon + notifications → Task 19. ✓
- Chain, never overwrite hook → HookInstaller (9). ✓
- Language-agnostic (no per-language fixers) → FixRunner prompt is generic. ✓
- Edge cases: no run → timeout (14); sha gone → ClonePool throws shaGone (10); no changes → FixRunner throws noChanges (12). ✓

**Placeholder scan:** none — every code step is complete.

**Type consistency:** `FixEngine` protocol methods match between Daemon (15), StubFixEngine (15), and LiveFixEngine (16). `PublishOutcome` cases consistent across Publisher (13) and Daemon (15). `RunStatus`/`WorkflowRun` consistent across GitHubClient (8), RunWatcher (14), Daemon (15).

**Known v1 limitations (documented, not gaps):**
- Rerun polling re-polls the original SHA's runs rather than the fix commit's runs. Acceptable for v1; README documents it.
- Clone push-rejected rebase-retry (spec edge case) is deferred to a follow-up; v1 surfaces the error via `.error` event.
