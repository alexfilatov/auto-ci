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
            fixOutcome: { FixAttempt(outcome: .pushedToBranch("feature-x"), fixSHA: "fixsha") },
            rerunResult: { _ in [WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc")] }
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
            fixOutcome: { FixAttempt(outcome: .pushedToBranch("feature-x"), fixSHA: "fixsha") },
            rerunResult: { _ in [] } // green
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
            fixOutcome: { FixAttempt(outcome: .pushedToBranch("feature-x"), fixSHA: "fixsha") },
            rerunResult: { _ in [WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc")] }
        )
        let daemon = Daemon(maxAttempts: 3, notifier: notifier, engine: engine)
        let result = daemon.handleFailedRun(project: "demo", branch: "feature-x", sha: "abc",
                                            failedRun: WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "abc"))
        XCTAssertEqual(result, FixOutcome.gaveUp)
    }

    func testRerunUsesFixSHANotOriginalSHA() {
        let notifier = SpyNotifier()
        var rerunSHAs: [String] = []
        let engine = StubFixEngine(
            onAttempt: {},
            signatureProvider: { _ in FailureSignature(job: "t", step: "s", hash: "first") },
            fixOutcome: { FixAttempt(outcome: .pushedToBranch("feature-x"), fixSHA: "fixsha123") },
            rerunResult: { sha in rerunSHAs.append(sha); return [] }
        )
        let daemon = Daemon(maxAttempts: 3, notifier: notifier, engine: engine)
        _ = daemon.handleFailedRun(project: "demo", branch: "feature-x", sha: "originsha",
                                   failedRun: WorkflowRun(id: 1, name: "CI", status: .failed, headSha: "originsha"))
        XCTAssertEqual(rerunSHAs, ["fixsha123"], "rerun must use the fix commit SHA, not the original")
    }
}

/// Test double implementing the engine the Daemon drives.
final class StubFixEngine: FixEngine, @unchecked Sendable {
    let onAttempt: () -> Void
    let signatureProvider: (WorkflowRun) -> FailureSignature
    let fixOutcome: () -> FixAttempt
    let rerunResult: (String) -> [WorkflowRun]
    init(onAttempt: @escaping () -> Void,
         signatureProvider: @escaping (WorkflowRun) -> FailureSignature,
         fixOutcome: @escaping () -> FixAttempt,
         rerunResult: @escaping (String) -> [WorkflowRun]) {
        self.onAttempt = onAttempt; self.signatureProvider = signatureProvider
        self.fixOutcome = fixOutcome; self.rerunResult = rerunResult
    }
    func signature(of run: WorkflowRun, project: String) throws -> FailureSignature { signatureProvider(run) }
    func attemptFix(project: String, branch: String, sha: String, run: WorkflowRun) throws -> FixAttempt {
        onAttempt(); return fixOutcome()
    }
    func rerunFailures(project: String, sha: String) throws -> [WorkflowRun] { rerunResult(sha) }
    func recordOutcome(project: String, signature: FailureSignature, summary: String, succeeded: Bool) {}
}
