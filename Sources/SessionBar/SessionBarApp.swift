import SwiftUI

enum Sources {
    static let local = LocalRegistrySource(
        platform: "On this device", hiddenNames: [AccountRosterSource.helperName])
    // The account list never names a machine, only what is live and not here.
    static let remote = AccountRosterSource(platform: "Other sessions")
}

@main
enum Main {
    static let usage = """
        SessionBar            start the menu bar app
        SessionBar --dump     print both lists once
        SessionBar --json     the same, as JSON
        SessionBar --open-at-login on|off
                              the same switch as in the menu's settings
        SessionBar --snapshot <file.png> [--dark]
                              draw the menu with made-up sessions
        SessionBar --version
        """

    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "--dump":
            finish { await dump() }
        case "--json":
            finish { await printJSON() }
        case "--snapshot" where arguments.count >= 2:
            do {
                try Snapshot.write(to: URL(fileURLWithPath: arguments[1]),
                                   dark: arguments.contains("--dark"))
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        case "--open-at-login" where arguments.count >= 2 && ["on", "off"].contains(arguments[1]):
            do {
                try LoginItem.set(arguments[1] == "on")
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            print("Open at login: \(LoginItem.isEnabled ? "on" : "off")")
        case "--version":
            print(SessionBarApp.version)
        case "--help", "-h", "--snapshot", "--open-at-login":
            print(usage)
        default:
            SessionBarApp.main()
        }
    }

    /// Runs a command line mode to its end; the exit status says whether both lists
    /// could be read.
    private static func finish(_ work: @escaping () async -> Bool) {
        Task {
            exit(await work() ? 0 : 1)
        }
        dispatchMain()
    }

    private static func fetchBoth() async -> (local: SourceState, remote: SourceState) {
        let local = await Sources.local.fetch()
        var localNames: Set<String> = []
        if case .sessions(let sessions) = local { localNames = Set(sessions.map(\.name)) }
        return (local, await Sources.remote.fetch(localNames: localNames).state)
    }

    private static func dump() async -> Bool {
        let lists = await fetchBoth()
        var readBoth = true
        for (platform, state) in [(Sources.local.platform, lists.local),
                                  (Sources.remote.platform, lists.remote)] {
            switch state {
            case .unavailable(let reason, _):
                print("\(platform): \(reason)")
                readBoth = false
            case .sessions(let sessions):
                print("\(platform): \(sessions.count)")
                for session in sessions {
                    let remoteControl = session.remoteControl.map { $0 ? "rc on" : "rc off" } ?? ""
                    print("  \(session.name)\t\(session.status)\t\(session.kind ?? "")\t\(remoteControl)")
                }
            }
        }
        return readBoth
    }

    private static func printJSON() async -> Bool {
        struct Output: Encodable {
            struct Item: Encodable {
                let name: String
                let status: String
                let waitingFor: String?
                let kind: String?
                let cwd: String?
                let startedAt: Date?
                let remoteControl: Bool?
            }
            var onThisDevice: [Item]?
            var onThisDeviceError: String?
            var otherSessions: [Item]?
            var otherSessionsError: String?
        }
        func items(_ state: SourceState) -> ([Output.Item]?, String?) {
            switch state {
            case .unavailable(let reason, _):
                return (nil, reason)
            case .sessions(let sessions):
                return (sessions.map {
                    Output.Item(name: $0.name, status: $0.status, waitingFor: $0.waitingFor,
                                kind: $0.kind, cwd: $0.cwd, startedAt: $0.startedAt,
                                remoteControl: $0.remoteControl)
                }, nil)
            }
        }

        let lists = await fetchBoth()
        var output = Output()
        (output.onThisDevice, output.onThisDeviceError) = items(lists.local)
        (output.otherSessions, output.otherSessionsError) = items(lists.remote)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(output) else { return false }
        print(String(decoding: data, as: UTF8.self))
        return output.onThisDeviceError == nil && output.otherSessionsError == nil
    }
}

struct SessionBarApp: App {
    static let homepage = URL(string: "https://github.com/runa-tic/session-bar")!
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    @StateObject private var store = SessionStore(local: Sources.local, remote: Sources.remote)

    var body: some Scene {
        MenuBarExtra {
            SessionListView(store: store)
        } label: {
            Image(systemName: "rectangle.stack")
            Text("\(store.total)")
        }
        .menuBarExtraStyle(.window)
    }
}
