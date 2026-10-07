import Foundation
import Testing
@testable import SessionBar

private typealias Account = AccountRosterSource
private typealias Row = AccountRosterSource.Row

/// The hook's input for a ListAgents call, cut down to the fields that are read.
private func payload(sections: String?, listing: String?) -> Data {
    var response: [String] = []
    if let listing {
        let encoded = String(decoding: try! JSONEncoder().encode(listing), as: UTF8.self)
        response.append("\"listing\": \(encoded)")
    }
    if let sections { response.append("\"sections\": \(sections)") }
    return Data("""
        {"session_id": "1a2b3c4d-0000-4000-8000-000000000000", "tool_name": "ListAgents",
         "tool_response": {\(response.joined(separator: ", ")), "notes": []}}
        """.utf8)
}

private let listing = """
    This session is sessionbar-roster [f6f6f6] — the name other sessions use to message it.

    Peer sessions (5):
      api [a1a1a1]  ·  interactive  ·  busy  ·  started 5m ago
      @notes  ·  interactive  ·  shell  ·  started 1d ago
      studio-pc-brisk-otter [b2b2b2]  ·  Remote Control  ·  idle
      Fix [draft] parser [c3c3c3]  ·  Remote Control  ·  busy
      old one [d4d4d4]  ·  Remote Control  ·  offline
      (… 8 more not shown)
    """

private let sections = """
    [{"kind": "sessions", "total": 113, "rows": [
        {"name": "api", "ref": "a1a1a1", "type": "interactive", "status": "busy"},
        {"name": "@notes", "type": "interactive", "status": "shell"},
        {"name": "studio-pc-brisk-otter", "ref": "b2b2b2", "type": "remote_control", "status": "idle"},
        {"name": "old one", "ref": "d4d4d4", "type": "remote_control", "status": "offline"}
    ]}]
    """

@Suite struct Decoding {
    @Test func structuredRowsAreUsedWhenPresent() throws {
        let capture = try #require(Account.decode(payload(sections: sections, listing: listing)))
        #expect(capture.rows.count == 4)
        #expect(capture.rows[2] == Row(name: "studio-pc-brisk-otter", ref: "b2b2b2",
                                       type: "remote_control", status: "idle"))
        #expect(capture.rows[1].ref == nil)
        #expect(capture.total == 113)
        #expect(capture.sessionID == "1a2b3c4d-0000-4000-8000-000000000000")
    }

    @Test func textIsUsedWhenThereAreNoStructuredRows() throws {
        let capture = try #require(Account.decode(payload(sections: nil, listing: listing)))
        #expect(capture.rows.map(\.name) == [
            "api", "@notes", "studio-pc-brisk-otter", "Fix [draft] parser", "old one",
        ])
        #expect(capture.total == nil)
    }

    @Test func textIsUsedWhenTheStructuredRowsChangeShape() throws {
        let changed = #"[{"kind": "sessions", "rows": [{"title": "api"}]}]"#
        let capture = try #require(Account.decode(payload(sections: changed, listing: listing)))
        #expect(capture.rows.count == 5)
    }

    @Test func somethingElseIsNotAList() {
        #expect(Account.decode(Data("not json".utf8)) == nil)
        #expect(Account.decode(Data(#"{"tool_response": {"notes": []}}"#.utf8)) == nil)
    }

    @Test func textRowsCarryRefTypeAndStatus() {
        let rows = Account.rows(fromText: listing)
        #expect(rows[0] == Row(name: "api", ref: "a1a1a1", type: "interactive", status: "busy"))
        #expect(rows[1] == Row(name: "@notes", ref: nil, type: "interactive", status: "shell"))
        #expect(rows[3] == Row(name: "Fix [draft] parser", ref: "c3c3c3",
                               type: "remote_control", status: "busy"))
    }
}

@Suite struct Filtering {
    private func names(_ rows: [Row], localNames: Set<String> = []) -> [String] {
        Account.sessions(from: rows, platform: "Other sessions", localNames: localNames).map(\.name)
    }

    @Test func onlyLiveSessionsElsewhereAreKept() {
        let rows = [
            Row(name: "api", ref: "a1a1a1", type: "interactive", status: "busy"),
            Row(name: "worker", ref: "a7a7a7", type: "bg", status: "busy"),
            Row(name: "studio-pc-brisk-otter", ref: "b2b2b2", type: "remote_control", status: "idle"),
            Row(name: "old one", ref: "d4d4d4", type: "remote_control", status: "offline"),
        ]
        #expect(names(rows) == ["studio-pc-brisk-otter"])
    }

    @Test func anotherMachinesHelperIsLeftOut() {
        let rows = [Row(name: Account.helperName, ref: "f6f6f6", type: "remote_control", status: "busy")]
        #expect(names(rows).isEmpty)
    }

    @Test func aRemoteSessionMayShareALocalName() {
        let rows = [Row(name: "api", ref: "e5e5e5", type: "remote_control", status: "idle")]
        #expect(names(rows, localNames: ["api"]) == ["api"])
    }

    @Test func anUnknownTypeIsShownUnderItsLabelUnlessItIsLocal() {
        let rows = [
            Row(name: "nightly", ref: "c1c1c1", type: "cloud_session", status: "running"),
            Row(name: "api", ref: "d2d2d2", type: "cloud_session", status: "running"),
        ]
        let sessions = Account.sessions(from: rows, platform: "Other sessions", localNames: ["api"])
        #expect(sessions.map(\.name) == ["nightly"])
        #expect(sessions[0].kind == "cloud session")
    }

    @Test func rowsWithoutARefStillGetDistinctIDs() {
        let rows = [
            Row(name: "twin", ref: nil, type: "remote_control", status: "idle"),
            Row(name: "twin", ref: nil, type: "remote_control", status: "busy"),
        ]
        let ids = Account.sessions(from: rows, platform: "Other sessions", localNames: []).map(\.id)
        #expect(Set(ids).count == 2)
    }
}

@Suite struct Verdicts {
    @Test func aRemoteRowSettlesIt() {
        #expect(Account.verdict(hasRemoteRows: true, helperFinished: false, connectedFor: nil) == .complete)
    }

    @Test func aLocalOnlyListWaitsForTheHelperToFinish() {
        #expect(Account.verdict(hasRemoteRows: false, helperFinished: false, connectedFor: 10) == .wait)
    }

    @Test func aLocalOnlyListIsBelievedWellAfterTheConnection() {
        #expect(Account.verdict(hasRemoteRows: false, helperFinished: true, connectedFor: 8) == .complete)
    }

    @Test func aLocalOnlyListIsRefusedWithoutAConnection() {
        guard case .failed = Account.verdict(hasRemoteRows: false, helperFinished: true, connectedFor: nil)
        else { Issue.record("expected a failure"); return }
    }

    @Test func aLocalOnlyListIsRefusedRightAfterTheConnection() {
        guard case .failed = Account.verdict(hasRemoteRows: false, helperFinished: true, connectedFor: 0.5)
        else { Issue.record("expected a failure"); return }
        // A list captured before the connection is no better.
        guard case .failed = Account.verdict(hasRemoteRows: false, helperFinished: true, connectedFor: -2)
        else { Issue.record("expected a failure"); return }
    }
}

@Suite struct Launching {
    @Test func theHelpersIDIsReadFromWhatClaudePrints() {
        let printed = """
            Starting background service…
            backgrounded · 1a2b3c4d · sessionbar-roster
              claude agents             list sessions
              claude stop 1a2b3c4d      stop this session
            """
        #expect(Account.helperID(in: printed) == "1a2b3c4d")
        #expect(Account.helperID(in: "Workspace not trusted. Run `claude` in /tmp/x once.") == nil)
    }

    @Test func pathsSurviveTheShell() {
        #expect(Account.shellQuoted("/Users/a b/c") == "'/Users/a b/c'")
        #expect(Account.shellQuoted("/Users/o'neil/c") == #"'/Users/o'\''neil/c'"#)
    }

    /// The trust script is run as written, in a folder whose path has a space and may
    /// have a quote: run it with stand-ins and see where it ends up.
    @Test func theTrustScriptStartsClaudeInTheHelperFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionbar-tests-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("App Support/o'neil/helper")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let claude = root.appendingPathComponent("bin dir/claude")
        try FileManager.default.createDirectory(
            at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho \"ran in $(pwd) with ${PATH%%:*}\"\n".utf8).write(to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

        let script = root.appendingPathComponent("trust.command")
        try Data(HelperSetup.script(for: folder, claude: claude).utf8).write(to: script)
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        let result = runCommand(URL(fileURLWithPath: "/bin/bash"), [script.path],
                                environment: environment, timeout: 10)

        #expect(result.status == 0)
        let expected = "ran in \(folder.path) with \(claude.deletingLastPathComponent().path)"
        #expect(String(decoding: result.stdout, as: UTF8.self).contains(expected))
    }
}

@Suite struct LocatingClaude {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionbar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func command(_ path: String) throws -> String {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func locate(_ environment: [String: String]) -> String? {
        ClaudeCLI.locate(environment: environment, home: root.appendingPathComponent("home"),
                         askShell: false)?.executable.path
    }

    @Test func theNamedBinaryWinsThenThePathThenTheUsualPlaces() throws {
        let usual = try command("home/.local/bin/claude")
        #expect(locate(["PATH": "/usr/bin:/bin"]) == usual)

        let onPath = try command("tools/claude")
        let path = "/usr/bin:\(root.path)/tools"
        #expect(locate(["PATH": path]) == onPath)

        let named = try command("elsewhere/claude-nightly")
        #expect(locate(["PATH": path, "CLAUDE_BIN": named]) == named)
    }

    @Test func aFolderNamedClaudeIsNotTheCommand() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tools/claude"), withIntermediateDirectories: true)
        #expect(locate(["PATH": "\(root.path)/tools"]) != "\(root.path)/tools/claude")
    }
}
