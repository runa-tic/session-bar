import SwiftUI

enum Sources {
    static let local = LocalRegistrySource(
        platform: "On this device", hiddenNames: [AccountRosterSource.helperName])
    // The account list never names a machine, only what is live and not here.
    static let remotePlatform = "Other sessions"
    static let remote = Bundle.main.url(forResource: "roster", withExtension: "sh")
        .map { AccountRosterSource(platform: remotePlatform, script: $0) }
}

@main
enum Main {
    static func main() {
        guard CommandLine.arguments.contains("--dump") else {
            SessionBarApp.main()
            return
        }
        // `SessionBar --dump` prints both lists once, for checking without the menu.
        Task {
            await dump(Sources.local.platform, Sources.local.fetch())
            if let remote = Sources.remote {
                await dump(remote.platform, remote.fetch())
            } else {
                print("\(Sources.remotePlatform): roster.sh is missing from the app bundle")
            }
            exit(0)
        }
        dispatchMain()
    }

    private static func dump(_ platform: String, _ state: SourceState) {
        switch state {
        case .unavailable(let reason):
            print("\(platform): \(reason)")
        case .sessions(let sessions):
            print("\(platform): \(sessions.count)")
            for session in sessions {
                let remoteControl = session.remoteControl.map { $0 ? "rc on" : "rc off" } ?? ""
                print("  \(session.name)\t\(session.status)\t\(session.kind ?? "")\t\(remoteControl)")
            }
        }
    }
}

struct SessionBarApp: App {
    @StateObject private var store = SessionStore(
        local: Sources.local, remote: Sources.remote, remotePlatform: Sources.remotePlatform)

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
