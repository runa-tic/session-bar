import Foundation

/// What one fetch of the account's list produced.
struct Roster: Equatable {
    var state: SourceState
    /// Set when the account sent fewer rows than it says exist.
    var note: String? = nil
}

/// Sessions on the account that are not on this machine.
///
/// Claude Code hands the account-wide list only to a session connected to Remote
/// Control, and a headless `claude -p` is not one. So a fetch starts a short background
/// session that calls the ListAgents tool, has a PostToolUse hook save the tool's result
/// to a file, then removes the session and its transcript. That is one small model turn
/// against the subscription per fetch, so the list is fetched when the menu opens with a
/// stale one or on request, never polled.
struct AccountRosterSource {
    static let helperName = "sessionbar-roster"

    /// Background sessions only start in a folder the user has trusted in Claude Code.
    /// The helper gets a folder of its own, so trusting it trusts nothing else and its
    /// transcripts stay out of real projects.
    static var defaultHelperFolder: URL {
        if let custom = ProcessInfo.processInfo.environment["SESSIONBAR_HELPER_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SessionBar/helper", isDirectory: true)
    }

    let platform: String
    var helperFolder = AccountRosterSource.defaultHelperFolder
    var timeout: TimeInterval = 60

    private static let prompt = "Call the ListAgents tool. If its output has no row marked Remote Control, call it again, up to 5 times in total. Then reply with the single word done."
    // Stands in for Claude Code's own system prompt, which the helper has no use for and
    // which would be most of what a fetch costs.
    private static let systemPrompt = "You are a helper that a script starts to read the session list. Do exactly what the user message says and nothing else."
    /// How long after Remote Control connects a list is taken to cover the account.
    private static let settleTime: TimeInterval = 3

    func fetch(localNames: Set<String> = []) async -> Roster {
        await Task.detached { fetchBlocking(localNames: localNames) }.value
    }

    // MARK: Reading the tool's result

    /// One row of the list, from either form the tool returns it in.
    struct Row: Equatable {
        let name: String
        let ref: String?
        /// remote_control, interactive, ...
        let type: String
        let status: String
    }

    /// The hook's input: the ListAgents call as Claude Code saw it.
    struct Capture: Equatable {
        let rows: [Row]
        /// How many sessions the account says exist; `rows` can be fewer.
        let total: Int?
        /// The helper's own session, which is how its transcript is found.
        let sessionID: String?
    }

    static func decode(_ data: Data) -> Capture? {
        struct Payload: Decodable {
            struct Response: Decodable {
                struct Section: Decodable {
                    struct Item: Decodable {
                        let name: String
                        let ref: String?
                        let type: String
                        let status: String
                    }
                    let total: Int?
                    let rows: [Item]
                }
                let sections: [Section]?
                let listing: String?

                enum CodingKeys: CodingKey { case sections, listing }

                // Either form may change shape; one that no longer decodes is skipped
                // so the other can still be used.
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    sections = try? container.decode([Section].self, forKey: .sections)
                    listing = try? container.decode(String.self, forKey: .listing)
                }
            }
            let tool_response: Response
            let session_id: String?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        if let sections = payload.tool_response.sections {
            let rows = sections.flatMap(\.rows).map {
                Row(name: $0.name, ref: $0.ref, type: $0.type, status: $0.status)
            }
            let totals = sections.compactMap(\.total)
            return Capture(rows: rows, total: totals.isEmpty ? nil : totals.reduce(0, +),
                           sessionID: payload.session_id)
        }
        guard let listing = payload.tool_response.listing else { return nil }
        return Capture(rows: rows(fromText: listing), total: nil, sessionID: payload.session_id)
    }

    /// The text form, for a Claude Code that sends no structured rows:
    /// `  name [ab12cd]  ·  Remote Control  ·  idle`.
    static func rows(fromText listing: String) -> [Row] {
        listing.split(separator: "\n").compactMap { line in
            let fields = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "  ·  ")
            guard line.hasPrefix("  "), fields.count >= 3 else { return nil }

            var name = fields[0]
            var ref: String?
            if let range = name.range(of: #" \[[0-9a-f]{6}\]$"#, options: .regularExpression) {
                ref = String(name[range].dropFirst(2).dropLast())
                name.removeSubrange(range)
            }
            let type = fields[1].lowercased().replacingOccurrences(of: " ", with: "_")
            return Row(name: name, ref: ref, type: type, status: fields[2])
        }
    }

    /// The registry's and `claude agents`' words for a session on this machine.
    private static let localTypes: Set<String> = ["interactive", "bg", "background"]

    /// The rows that are live somewhere else. A Remote Control row always is. A type this
    /// app does not know is shown under its own label, unless a local session has that
    /// name, so a new kind of remote session is not silently dropped.
    static func sessions(from rows: [Row], platform: String, localNames: Set<String>) -> [Session] {
        rows.enumerated().compactMap { index, row in
            guard row.status != "offline", row.name != helperName else { return nil }
            let remoteControl = row.type == "remote_control"
            if !remoteControl, localTypes.contains(row.type) || localNames.contains(row.name) {
                return nil
            }
            return Session(
                // Not every row has a ref, and names repeat.
                id: row.ref ?? "\(row.name)#\(index)",
                name: row.name, platform: platform, status: row.status,
                kind: remoteControl ? nil : row.type.replacingOccurrences(of: "_", with: " "),
                cwd: nil, startedAt: nil, remoteControl: nil)
        }
    }

    enum Verdict: Equatable {
        case wait
        case complete
        case failed(String)
    }

    /// Whether a captured list covers the whole account. The helper's first call can land
    /// before Remote Control has connected and list only this machine. A list with a
    /// Remote Control row is past that. One without is only believed once the helper has
    /// stopped retrying, and only if its last call came well after the connection.
    static func verdict(hasRemoteRows: Bool, helperFinished: Bool,
                        connectedFor: TimeInterval?) -> Verdict {
        if hasRemoteRows { return .complete }
        guard helperFinished else { return .wait }
        guard let connectedFor else {
            return .failed("Remote Control did not connect for the helper session. Check that Remote Control works in Claude Code on this Mac.")
        }
        guard connectedFor >= settleTime else {
            return .failed("Remote Control connected too late to read the account's list. Try again.")
        }
        return .complete
    }

    /// `claude --bg` prints `backgrounded · 1a2b3c4d · sessionbar-roster`.
    static func helperID(in output: String) -> String? {
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ")
            if fields.count >= 3, fields[0] == "backgrounded" { return String(fields[2]) }
        }
        return nil
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Running the helper

    private func fetchBlocking(localNames: Set<String>) -> Roster {
        guard let claude = ClaudeCLI.locate() else {
            return Roster(state: .unavailable("Claude Code was not found. Install it, then refresh."))
        }
        let fileManager = FileManager.default
        let cache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SessionBar", isDirectory: true)
        do {
            try fileManager.createDirectory(at: helperFolder, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        } catch {
            return Roster(state: .unavailable(error.localizedDescription))
        }

        // A fetch that was killed can leave its helper behind; clear any before
        // starting another.
        for stale in helpers(claude) { remove(stale.id, sessionID: stale.sessionID, claude) }

        let captureFile = cache.appendingPathComponent("capture-\(UUID().uuidString).json")
        let partFile = captureFile.appendingPathExtension("part")
        defer {
            try? fileManager.removeItem(at: captureFile)
            try? fileManager.removeItem(at: partFile)
        }

        // User and project settings are left out, so the user's own hooks and plugins
        // don't run for the helper; Remote Control is switched on here instead.
        let launch = claude.run([
            "--bg", Self.prompt, "--name", Self.helperName, "--model", "haiku",
            "--tools", "ListAgents", "--allowedTools", "ListAgents",
            "--system-prompt", Self.systemPrompt,
            "--setting-sources", "local",
            "--settings", settings(savingTo: captureFile, through: partFile),
        ], in: helperFolder)
        guard let id = Self.helperID(in: launch.text) else {
            if launch.text.contains("not trusted") {
                return Roster(state: .unavailable(
                    "Claude Code has to trust SessionBar's helper folder once before it will start the helper session there.",
                    fix: .trustHelperFolder))
            }
            return Roster(state: .unavailable("Could not start the helper session: \(launch.text)"))
        }
        var sessionID: String?
        defer { remove(id, sessionID: sessionID, claude) }

        let deadline = Date().addingTimeInterval(timeout)
        var connectedAt: Date?
        var sawBusy = false
        while Date() < deadline {
            let entry = RegistryEntry.all()?.first { $0.sessionId.hasPrefix(id) }
            if let entry {
                sessionID = entry.sessionId
                if entry.status == "busy" { sawBusy = true }
                if connectedAt == nil, entry.bridgeSessionId != nil { connectedAt = Date() }
            }
            // The turn is over when the session goes idle, or is gone.
            let finished = sawBusy && (entry == nil || entry?.status == "idle")

            if let data = try? Data(contentsOf: captureFile), let capture = Self.decode(data) {
                sessionID = capture.sessionID ?? sessionID
                let attributes = try? fileManager.attributesOfItem(atPath: captureFile.path)
                let capturedAt = attributes?[.modificationDate] as? Date ?? Date()
                switch Self.verdict(
                    hasRemoteRows: capture.rows.contains { $0.type == "remote_control" },
                    helperFinished: finished,
                    connectedFor: connectedAt.map { capturedAt.timeIntervalSince($0) }
                ) {
                case .wait:
                    break
                case .complete:
                    return roster(from: capture, localNames: localNames)
                case .failed(let reason):
                    return Roster(state: .unavailable(reason))
                }
            } else if finished {
                return Roster(state: .unavailable("The helper session ended without reading the session list."))
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return Roster(state: .unavailable("The helper session returned nothing within \(Int(timeout)) seconds."))
    }

    private func roster(from capture: Capture, localNames: Set<String>) -> Roster {
        let sessions = Self.sessions(from: capture.rows, platform: platform, localNames: localNames)
        var note: String?
        if let total = capture.total, total > capture.rows.count {
            note = "The account lists \(total) sessions and sent the first \(capture.rows.count), so a live one further down would be missing."
        }
        return Roster(state: .sessions(sessions), note: note)
    }

    private func settings(savingTo file: URL, through part: URL) -> String {
        let part = Self.shellQuoted(part.path), file = Self.shellQuoted(file.path)
        // The hook gets the tool call on stdin. Written whole, then moved, so a reader
        // never sees half of it.
        let hook = ["type": "command", "command": "cat > \(part) && mv -f \(part) \(file)"]
        let settings: [String: Any] = [
            "remoteControlAtStartup": true,
            "hooks": ["PostToolUse": [["matcher": "ListAgents", "hooks": [hook]]]],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: settings)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func helpers(_ claude: ClaudeCLI) -> [(id: String, sessionID: String?)] {
        struct Agent: Decodable {
            let id: String?
            let name: String?
            let sessionId: String?
        }
        let listed = claude.run(["agents", "--json", "--all"])
        guard let agents = try? JSONDecoder().decode([Agent].self, from: listed.stdout) else { return [] }
        return agents.filter { $0.name == Self.helperName }.compactMap { agent in
            agent.id.map { ($0, agent.sessionId) }
        }
    }

    /// `claude rm` takes the session off the account's list but keeps its transcript,
    /// and one per fetch adds up, so that is deleted too.
    private func remove(_ id: String, sessionID: String?, _ claude: ClaudeCLI) {
        _ = claude.run(["stop", id])
        _ = claude.run(["rm", id])
        guard let sessionID, sessionID.hasPrefix(id) else { return }

        let fileManager = FileManager.default
        let projects = ClaudeCLI.configDirectory.appendingPathComponent("projects", isDirectory: true)
        let folders = (try? fileManager.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let transcript = folder.appendingPathComponent("\(sessionID).jsonl")
            guard fileManager.fileExists(atPath: transcript.path) else { continue }
            try? fileManager.removeItem(at: transcript)
            try? fileManager.removeItem(at: folder.appendingPathComponent(sessionID, isDirectory: true))
        }
    }
}
