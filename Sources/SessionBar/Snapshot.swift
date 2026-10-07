import AppKit
import SwiftUI

/// Draws the menu with made-up sessions into a PNG, without showing a window. The
/// picture in the README is made this way, so it holds nobody's real session names.
@MainActor
enum Snapshot {
    struct Failed: LocalizedError {
        var errorDescription: String? { "Could not draw the menu." }
    }

    static func write(to url: URL, dark: Bool) throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let view = SessionListView(store: sampleStore)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.15)))
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Give SwiftUI a moment to finish laying the rows out.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw Failed()
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failed() }
        try png.write(to: url)
    }

    private static var sampleStore: SessionStore {
        let here = "On this device", elsewhere = "Other sessions"
        func local(_ name: String, _ status: String, hours: Double, kind: String = "interactive",
                   remoteControl: Bool = true, waitingFor: String? = nil) -> Session {
            Session(id: name, name: name, platform: here, status: status, kind: kind,
                    cwd: "~/code/\(name)", startedAt: Date().addingTimeInterval(-hours * 3600),
                    remoteControl: remoteControl, waitingFor: waitingFor)
        }
        func remote(_ name: String, _ status: String) -> Session {
            Session(id: name, name: name, platform: elsewhere, status: status, kind: nil,
                    cwd: nil, startedAt: nil, remoteControl: nil)
        }
        return SessionStore(
            localPlatform: here,
            local: [
                local("api-refactor", "busy", hours: 52),
                local("release-notes", "waiting", hours: 27, waitingFor: "input needed"),
                local("docs", "idle", hours: 3.2, remoteControl: false),
                local("flaky-test-hunt", "busy", hours: 0.4, kind: "bg"),
            ],
            remotePlatform: elsewhere,
            remote: [
                remote("studio-pc-brisk-otter", "busy"),
                remote("studio-pc-quiet-harbor", "idle"),
                remote("nightly-benchmarks", "idle"),
            ],
            fetchedAt: Date())
    }
}
