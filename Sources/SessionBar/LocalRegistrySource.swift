import Foundation

/// One file in Claude Code's own registry of live sessions on this machine:
/// `<pid>.json` in `~/.claude/sessions/`.
struct RegistryEntry: Decodable {
    let pid: Int32
    let sessionId: String
    let name: String?
    let kind: String?
    let status: String?
    let waitingFor: String?
    let cwd: String?
    let startedAt: Double?
    /// Set once the session is connected to Remote Control.
    let bridgeSessionId: String?

    static var directory: URL {
        ClaudeCLI.configDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    /// nil when the registry itself cannot be read.
    static func all(in directory: URL = RegistryEntry.directory) -> [RegistryEntry]? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        else { return nil }
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? decoder.decode(RegistryEntry.self, from: data)
        }
    }
}

/// Sessions running on this machine, read from the registry.
struct LocalRegistrySource {
    let platform: String
    /// Session names to leave out, such as this app's own helper.
    var hiddenNames: Set<String> = []
    var directory = RegistryEntry.directory

    func fetch() async -> SourceState {
        guard let entries = RegistryEntry.all(in: directory) else {
            // No registry yet means Claude Code has not run here, which is not an error.
            if !FileManager.default.fileExists(atPath: directory.path) { return .sessions([]) }
            return .unavailable("Can't read \(directory.path)")
        }

        var sessions: [Session] = []
        for entry in entries where isAlive(entry.pid) && !hiddenNames.contains(entry.name ?? "") {
            sessions.append(Session(
                id: entry.sessionId,
                name: entry.name ?? fallbackName(entry),
                platform: platform,
                status: entry.status ?? "unknown",
                kind: entry.kind,
                cwd: entry.cwd,
                startedAt: entry.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                remoteControl: entry.bridgeSessionId != nil,
                waitingFor: entry.waitingFor
            ))
        }
        // Oldest first, so rows keep their place between refreshes.
        sessions.sort { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
        return .sessions(sessions)
    }

    /// A crashed session leaves its file behind; only list ones whose process exists.
    private func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func fallbackName(_ entry: RegistryEntry) -> String {
        let folder = entry.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "session"
        return "\(folder)-\(entry.sessionId.prefix(4))"
    }
}
