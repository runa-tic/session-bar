import Foundation

/// Sessions on the account that are not on this machine, taken from the list Claude
/// Code hands a session connected to Remote Control. `roster.sh` does the fetching:
/// it costs one small model turn per call, so this is fetched when the menu opens
/// with a stale list or on request, never polled.
struct AccountRosterSource {
    static let helperName = "sessionbar-roster"

    let platform: String
    let script: URL

    private struct Capture: Decodable {
        struct Response: Decodable { let listing: String }
        let tool_response: Response
    }

    func fetch() async -> SourceState {
        let result = await run()
        guard result.status == 0 else {
            let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .unavailable(reason.isEmpty ? "roster.sh failed" : reason)
        }
        guard let capture = try? JSONDecoder().decode(Capture.self, from: result.stdout) else {
            return .unavailable("unexpected output from roster.sh")
        }
        return .sessions(Self.parse(capture.tool_response.listing, platform: platform))
    }

    /// Rows look like `  name [ab12cd]  ·  Remote Control  ·  idle`. Sessions on this
    /// machine are listed under another kind and come from the local registry instead,
    /// so every live Remote Control row is a session somewhere else.
    static func parse(_ listing: String, platform: String) -> [Session] {
        listing.split(separator: "\n").compactMap { line in
            let fields = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "  ·  ")
            guard line.hasPrefix("  "), fields.count >= 3,
                  fields[1] == "Remote Control", fields[2] != "offline"
            else { return nil }

            var name = fields[0]
            var id = name
            if let ref = name.range(of: #" \[[0-9a-f]{6}\]$"#, options: .regularExpression) {
                id = String(name[ref].dropFirst(2).dropLast())
                name.removeSubrange(ref)
            }
            return Session(id: id, name: name, platform: platform, status: fields[2],
                           kind: nil, cwd: nil, startedAt: nil, remoteControl: nil)
        }
    }

    private func run() async -> (status: Int32, stdout: Data, stderr: String) {
        let script = script
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            var environment = ProcessInfo.processInfo.environment
            environment["ROSTER_NAME"] = Self.helperName
            process.environment = environment
            let out = Pipe(), err = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out
            process.standardError = err
            do {
                try process.run()
            } catch {
                return (1, Data(), error.localizedDescription)
            }
            let stdout = out.fileHandleForReading.readDataToEndOfFile()
            let stderr = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, stdout, String(decoding: stderr, as: UTF8.self))
        }.value
    }
}
