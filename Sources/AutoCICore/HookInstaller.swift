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
        # DO NOT EDIT — this file is managed by auto-ci and will be removed on `auto-ci uninstall`.
        # To add your own pre-push logic, edit pre-push.auto-ci-orig (it is chained automatically).
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
        // Record exactly what we installed, so uninstall can detect later edits.
        try? fm.removeItem(atPath: hookPath + ".auto-ci-installed")
        try script.write(toFile: hookPath + ".auto-ci-installed", atomically: true, encoding: .utf8)
    }

    /// Removes the managed hook safely, never destroying user changes.
    /// Returns human-readable notes about anything preserved.
    @discardableResult
    public func uninstall(repoPath: String) throws -> [String] {
        let fm = FileManager.default
        let hookPath = repoPath + "/.git/hooks/pre-push"
        let origPath = hookPath + ".auto-ci-orig"
        let installedRef = hookPath + ".auto-ci-installed"
        var notes: [String] = []

        guard fm.fileExists(atPath: hookPath) else {
            try? fm.removeItem(atPath: installedRef)
            return notes
        }
        let current = (try? String(contentsOfFile: hookPath, encoding: .utf8)) ?? ""

        // The user replaced our hook with their own — never clobber it.
        guard current.contains(marker) else {
            try? fm.removeItem(atPath: installedRef)
            notes.append("Left your pre-push hook untouched (it is no longer auto-ci managed).")
            return notes
        }

        // Our managed hook is in place. If the user edited it, preserve a copy first.
        let installed = try? String(contentsOfFile: installedRef, encoding: .utf8)
        if installed != current {
            let saved = hookPath + ".auto-ci-modified.\(Int(Date().timeIntervalSince1970))"
            try? fm.copyItem(atPath: hookPath, toPath: saved)
            notes.append("Your edits to the managed hook were saved to \((saved as NSString).lastPathComponent).")
        }

        // Restore the pre-existing original if we backed one up; otherwise just remove ours.
        try fm.removeItem(atPath: hookPath)
        if fm.fileExists(atPath: origPath) {
            try fm.moveItem(atPath: origPath, toPath: hookPath)
        }
        try? fm.removeItem(atPath: installedRef)
        return notes
    }
}
