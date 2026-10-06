import Foundation

/// Sessions running on this machine, read from Claude Code's own registry:
/// one `<pid>.json` per live session in `~/.claude/sessions/`.
struct LocalRegistrySource {
    let platform: String
    /// Session names to leave out, such as this app's own helper.
    var hiddenNames: Set<String> = []
    var directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions", isDirectory: true)

    private struct Entry: Decodable {
        let pid: Int32
        let sessionId: String
        let name: String?
        let kind: String?
        let status: String?
        let cwd: String?
        let startedAt: Double?
        let bridgeSessionId: String?
    }

    func fetch() async -> SourceState {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        } catch {
            return .unavailable("can't read \(directory.path)")
        }

        let decoder = JSONDecoder()
        var sessions: [Session] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(Entry.self, from: data),
                  isAlive(entry.pid),
                  !hiddenNames.contains(entry.name ?? "")
            else { continue }

            sessions.append(Session(
                id: entry.sessionId,
                name: entry.name ?? fallbackName(entry),
                platform: platform,
                status: entry.status ?? "unknown",
                kind: entry.kind,
                cwd: entry.cwd,
                startedAt: entry.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                remoteControl: entry.bridgeSessionId != nil
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

    private func fallbackName(_ entry: Entry) -> String {
        let folder = entry.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "session"
        return "\(folder)-\(entry.sessionId.prefix(4))"
    }
}
