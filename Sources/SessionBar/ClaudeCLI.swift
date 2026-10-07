import Foundation

/// The `claude` command, and where Claude Code keeps its state.
struct ClaudeCLI {
    let executable: URL

    /// `~/.claude`, or wherever CLAUDE_CONFIG_DIR points.
    static var configDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
    }

    /// An app started from Finder or at login gets a bare PATH, so the usual install
    /// locations are tried before the user's own shell is asked.
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        askShell: Bool = true
    ) -> ClaudeCLI? {
        var candidates: [String] = []
        if let named = environment["CLAUDE_BIN"], !named.isEmpty { candidates.append(named) }
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/claude" }
        candidates += [
            home.appendingPathComponent(".local/bin/claude").path,
            home.appendingPathComponent(".claude/local/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let found = candidates.first(where: isCommand) {
            return ClaudeCLI(executable: URL(fileURLWithPath: found))
        }
        // An npm install under nvm, volta and the like is only on the shell's PATH.
        guard askShell, let found = pathFromShell(environment), isCommand(found) else { return nil }
        return ClaudeCLI(executable: URL(fileURLWithPath: found))
    }

    func run(_ arguments: [String], in directory: URL? = nil,
             timeout: TimeInterval = 30) -> CommandResult {
        // An npm-installed claude is a node script, and node sits next to it.
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):\(path)"
        return runCommand(executable, arguments, in: directory,
                          environment: environment, timeout: timeout)
    }

    private static func isCommand(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    private static func pathFromShell(_ environment: [String: String]) -> String? {
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let result = runCommand(URL(fileURLWithPath: shell), ["-ilc", "command -v claude"],
                                environment: environment, timeout: 5)
        // An interactive shell can print a banner first; the answer is the last path.
        return String(decoding: result.stdout, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
    }
}

struct CommandResult {
    /// The exit status, or -1 when the command could not be started or was stopped at
    /// the timeout.
    let status: Int32
    let stdout: Data
    let stderr: String

    /// Both streams as text, for error messages.
    var text: String {
        (String(decoding: stdout, as: UTF8.self) + stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Runs a command to its end and returns what it printed. Output goes to files, not
/// pipes: `claude --bg` can start a background service that outlives the command, and
/// reading a pipe to its end would then depend on that service closing its copy.
func runCommand(_ executable: URL, _ arguments: [String], in directory: URL? = nil,
                environment: [String: String]? = nil, timeout: TimeInterval) -> CommandResult {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory
        .appendingPathComponent("sessionbar-\(UUID().uuidString)")
    let outFile = base.appendingPathExtension("out"), errFile = base.appendingPathExtension("err")
    defer {
        try? fileManager.removeItem(at: outFile)
        try? fileManager.removeItem(at: errFile)
    }
    guard fileManager.createFile(atPath: outFile.path, contents: nil),
          fileManager.createFile(atPath: errFile.path, contents: nil),
          let out = FileHandle(forWritingAtPath: outFile.path),
          let err = FileHandle(forWritingAtPath: errFile.path)
    else { return CommandResult(status: -1, stdout: Data(), stderr: "can't write to \(base.path)") }
    defer {
        try? out.close()
        try? err.close()
    }

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    if let environment { process.environment = environment }
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = out
    process.standardError = err
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    do {
        try process.run()
    } catch {
        return CommandResult(status: -1, stdout: Data(), stderr: error.localizedDescription)
    }

    var timedOut = false
    if exited.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        process.terminate()
        if exited.wait(timeout: .now() + 2) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            exited.wait()
        }
    }
    let stdout = (try? Data(contentsOf: outFile)) ?? Data()
    let stderr = String(decoding: (try? Data(contentsOf: errFile)) ?? Data(), as: UTF8.self)
    if timedOut {
        return CommandResult(status: -1, stdout: stdout,
                             stderr: stderr + "\nstopped after \(Int(timeout))s")
    }
    return CommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
}
