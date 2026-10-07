import AppKit

enum HelperSetup {
    /// Claude Code asks whether to trust a folder when an interactive session starts in
    /// it, and nowhere else, so open one there in Terminal.
    static func openTrustPrompt(for folder: URL) {
        guard let claude = ClaudeCLI.locate() else { return }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Trust SessionBar helper folder.command")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(script(for: folder, claude: claude.executable).utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch {
            return
        }
        NSWorkspace.shared.open(file)
    }

    static func script(for folder: URL, claude: URL) -> String {
        let quoted = AccountRosterSource.shellQuoted
        return [
            "#!/bin/bash",
            "cd \(quoted(folder.path)) || exit 1",
            // An npm-installed claude is a node script, and node sits next to it.
            "export PATH=\(quoted(claude.deletingLastPathComponent().path)):\"$PATH\"",
            "clear",
            "echo 'SessionBar: accept the trust prompt for this folder, then type /exit.'",
            "echo 'After that, refresh the other sessions from the menu bar.'",
            "echo",
            "exec \(quoted(claude.path))",
        ].joined(separator: "\n") + "\n"
    }
}
