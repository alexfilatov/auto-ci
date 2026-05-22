// Tests/AutoCICoreTests/GraceGateTests.swift
import XCTest
@testable import AutoCICore

final class GraceGateTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeLeases(now: @escaping @Sendable () -> Date) -> LeaseStore {
        LeaseStore(root: root, now: now)
    }

    func testHeldLeaseDefers() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let leases = makeLeases(now: { now })
        leases.hold(project: "demo", branch: "feature", minutes: 30)
        let fake = FakeCommandRunner()
        let gate = GraceGate(git: GitClient(runner: fake), leases: leases, graceSeconds: 180,
                             sleep: { _ in }, now: { now })
        let decision = gate.evaluate(project: "demo", branch: "feature", failedSHA: "abc", cwd: "/repo")
        XCTAssertEqual(decision, .deferred("a hold is active on feature"))
    }

    func testBranchAdvancedDefers() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let leases = makeLeases(now: { now })
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["ls-remote", "origin", "refs/heads/feature"],
                  stdout: "newsha999\trefs/heads/feature\n")
        let gate = GraceGate(git: GitClient(runner: fake), leases: leases, graceSeconds: 180,
                             sleep: { _ in }, now: { now })
        let decision = gate.evaluate(project: "demo", branch: "feature", failedSHA: "abc", cwd: "/repo")
        XCTAssertEqual(decision, .deferred("feature advanced — another fix landed"))
    }

    func testSameSHAGraceZeroProceeds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let leases = makeLeases(now: { now })
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["ls-remote", "origin", "refs/heads/feature"],
                  stdout: "abc\trefs/heads/feature\n")
        let gate = GraceGate(git: GitClient(runner: fake), leases: leases, graceSeconds: 0,
                             sleep: { _ in }, now: { now })
        let decision = gate.evaluate(project: "demo", branch: "feature", failedSHA: "abc", cwd: "/repo")
        XCTAssertEqual(decision, .proceed)
    }

    func testEmptyRemoteSHAProceeds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let leases = makeLeases(now: { now })
        let fake = FakeCommandRunner()
        fake.stub(command: "git", args: ["ls-remote", "origin", "refs/heads/feature"], stdout: "")
        let gate = GraceGate(git: GitClient(runner: fake), leases: leases, graceSeconds: 0,
                             sleep: { _ in }, now: { now })
        let decision = gate.evaluate(project: "demo", branch: "feature", failedSHA: "abc", cwd: "/repo")
        XCTAssertEqual(decision, .proceed)
    }
}
