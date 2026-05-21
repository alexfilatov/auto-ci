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
