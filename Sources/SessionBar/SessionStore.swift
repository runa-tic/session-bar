import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var local: SourceState = .sessions([])
    /// nil until the first fetch.
    @Published private(set) var remote: SourceState?
    @Published private(set) var remoteNote: String?
    @Published private(set) var remoteFetchedAt: Date?
    @Published private(set) var remoteRefreshing = false

    /// Whether opening the menu may fetch the account's list by itself.
    @Published var refreshesOnOpen: Bool {
        didSet { UserDefaults.standard.set(refreshesOnOpen, forKey: Self.refreshesOnOpenKey) }
    }
    @Published private(set) var opensAtLogin = LoginItem.isEnabled
    @Published private(set) var loginItemError: String?

    let localPlatform: String
    let remotePlatform: String

    private let localSource: LocalRegistrySource?
    private let remoteSource: AccountRosterSource?
    private var timer: Timer?

    private static let refreshesOnOpenKey = "refreshesOnOpen"

    init(local: LocalRegistrySource, remote: AccountRosterSource, interval: TimeInterval = 3) {
        localSource = local
        remoteSource = remote
        localPlatform = local.platform
        remotePlatform = remote.platform
        refreshesOnOpen = UserDefaults.standard.object(forKey: Self.refreshesOnOpenKey) as? Bool ?? true
        refreshLocal()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocal() }
        }
    }

    /// A store that shows fixed lists and fetches nothing, for pictures of the menu.
    init(localPlatform: String, local: [Session], remotePlatform: String, remote: [Session],
         fetchedAt: Date) {
        localSource = nil
        remoteSource = nil
        self.localPlatform = localPlatform
        self.remotePlatform = remotePlatform
        self.local = .sessions(local)
        self.remote = .sessions(remote)
        remoteFetchedAt = fetchedAt
        refreshesOnOpen = true
    }

    var total: Int { local.count + (remote?.count ?? 0) }
    var canRefreshRemote: Bool { !remoteRefreshing }

    func refreshLocal() {
        guard let localSource else { return }
        Task {
            let next = await localSource.fetch()
            if next != local { local = next }
        }
    }

    /// Called when the menu opens. A fetch costs a model turn, so it only runs when the
    /// last good list is older than `age`.
    func refreshRemoteIfStale(olderThan age: TimeInterval = 600) {
        guard refreshesOnOpen else { return }
        if case .sessions = remote, let remoteFetchedAt,
           Date().timeIntervalSince(remoteFetchedAt) < age {
            return
        }
        refreshRemote()
    }

    func refreshRemote() {
        guard let remoteSource, !remoteRefreshing else { return }
        remoteRefreshing = true
        var localNames: Set<String> = []
        if case .sessions(let sessions) = local { localNames = Set(sessions.map(\.name)) }
        Task {
            let roster = await remoteSource.fetch(localNames: localNames)
            remote = roster.state
            remoteNote = roster.note
            remoteFetchedAt = Date()
            remoteRefreshing = false
        }
    }

    /// Opens Terminal where Claude Code will ask to trust the helper's folder.
    func fix(_ fix: SourceState.Fix) {
        guard let remoteSource else { return }
        switch fix {
        case .trustHelperFolder:
            HelperSetup.openTrustPrompt(for: remoteSource.helperFolder)
        }
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Could not change the login item: \(error.localizedDescription)"
        }
        opensAtLogin = LoginItem.isEnabled
    }
}
