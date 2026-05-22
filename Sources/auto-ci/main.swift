// Sources/auto-ci/main.swift
import AutoCICore
import Foundation

let root = ConfigStore.defaultRoot
let store = ConfigStore(root: root)
let socketPath = root.appendingPathComponent("daemon.sock").path
let cli = CLICommand(store: store, runner: ProcessCommandRunner(),
                     hookInstaller: HookInstaller(), socketPath: socketPath, root: root)
do {
    let out = try cli.run(Array(CommandLine.arguments.dropFirst()),
                          cwd: FileManager.default.currentDirectoryPath)
    print(out)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
