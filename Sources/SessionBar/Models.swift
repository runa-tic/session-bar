import Foundation

/// One Claude Code session, wherever it runs.
struct Session: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: String
    /// Raw status word from the source: idle, busy, shell, waiting, ...
    let status: String
    /// interactive, bg, ... nil when the source does not say.
    let kind: String?
    let cwd: String?
    let startedAt: Date?
    /// nil when the source cannot tell.
    let remoteControl: Bool?
    /// What a waiting session is waiting for, such as "input needed".
    var waitingFor: String? = nil
}

enum SourceState: Equatable {
    case sessions([Session])
    case unavailable(String, fix: Fix? = nil)

    /// Something the user can do about a list that is unavailable.
    enum Fix: Equatable {
        case trustHelperFolder
    }

    var count: Int {
        if case .sessions(let list) = self { return list.count }
        return 0
    }
}
