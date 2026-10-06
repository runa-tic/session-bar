import AppKit
import SwiftUI

struct SessionListView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlatformSection(title: store.localPlatform, state: store.local)
            PlatformSection(
                title: store.remotePlatform,
                state: store.remote,
                placeholder: store.remoteRefreshing ? "Asking the account…" : "Not loaded yet",
                asOf: store.remoteFetchedAt,
                refreshing: store.remoteRefreshing
            )
            Divider().padding(.top, 6)
            Footer(store: store)
        }
        .padding(.vertical, 6)
        .frame(width: 320)
        .onAppear { store.refreshRemoteIfStale() }
    }
}

private struct PlatformSection: View {
    let title: String
    let state: SourceState?
    var placeholder = ""
    var asOf: Date?
    var refreshing = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
            if let asOf {
                Text("as of \(asOf.formatted(date: .omitted, time: .shortened))")
                    .fontWeight(.regular)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if refreshing {
                ProgressView().controlSize(.mini)
            } else if case .sessions(let sessions) = state {
                Text("\(sessions.count)")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)

        switch state {
        case nil:
            Note(text: placeholder)
        case .sessions(let sessions) where sessions.isEmpty:
            Note(text: "No sessions running")
        case .sessions(let sessions):
            ForEach(sessions) { SessionRow(session: $0) }
        case .unavailable(let reason):
            Note(text: reason)
        }
    }
}

private struct Note: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }
}

private struct SessionRow: View {
    let session: Session
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button(action: copyName) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(session.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let kind = session.kind, kind != "interactive" {
                    Text(kind)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer(minLength: 8)
                Text(copied ? "copied" : trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let remoteControl = session.remoteControl {
                    Image(systemName: remoteControl
                          ? "antenna.radiowaves.left.and.right"
                          : "antenna.radiowaves.left.and.right.slash")
                        .font(.caption)
                        .foregroundStyle(remoteControl ? .secondary : .tertiary)
                        .help(remoteControl
                              ? "Remote Control on"
                              : "Remote Control off: other machines can't reach this session")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.cwd ?? "")
    }

    private var trailing: String {
        guard let startedAt = session.startedAt else { return session.status }
        return "\(session.status) · \(age(since: startedAt))"
    }

    private var statusColor: Color {
        switch session.status {
        case "busy", "running": return .orange
        case "shell": return .blue
        case "waiting": return .yellow
        case "idle": return .green
        default: return .gray
        }
    }

    /// The name is what other sessions address messages to, so a click copies it.
    private func copyName() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.name, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func age(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}

private struct Footer: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack {
            Button("Refresh \(store.remotePlatform.lowercased())") { store.refreshRemote() }
                .disabled(!store.canRefreshRemote)
                .help("Starts a short helper session to read the account's session list")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
