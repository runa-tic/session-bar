import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var local: SourceState = .sessions([])
    /// nil until the first fetch.
    @Published private(set) var remote: SourceState?
    @Published private(set) var remoteFetchedAt: Date?
    @Published private(set) var remoteRefreshing = false

    let localPlatform: String
    let remotePlatform: String

    private let localSource: LocalRegistrySource
    private let remoteSource: AccountRosterSource?
    private var timer: Timer?

    init(local: LocalRegistrySource, remote: AccountRosterSource?,
         remotePlatform: String, interval: TimeInterval = 3) {
        localSource = local
        remoteSource = remote
        localPlatform = local.platform
        self.remotePlatform = remotePlatform
        if remote == nil {
            self.remote = .unavailable("roster.sh is missing from the app bundle")
        }
        refreshLocal()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocal() }
        }
    }

    var total: Int { local.count + (remote?.count ?? 0) }
    var canRefreshRemote: Bool { remoteSource != nil && !remoteRefreshing }

    func refreshLocal() {
        Task {
            let next = await localSource.fetch()
            if next != local { local = next }
        }
    }

    /// Called when the menu opens. A fetch costs a model turn and leaves a transcript,
    /// so it only runs when the last good list is older than `age`.
    func refreshRemoteIfStale(olderThan age: TimeInterval = 600) {
        if case .sessions = remote, let remoteFetchedAt,
           Date().timeIntervalSince(remoteFetchedAt) < age {
            return
        }
        refreshRemote()
    }

    func refreshRemote() {
        guard let remoteSource, !remoteRefreshing else { return }
        remoteRefreshing = true
        Task {
            remote = await remoteSource.fetch()
            remoteFetchedAt = Date()
            remoteRefreshing = false
        }
    }
}
