import Foundation
import OpenUsageCore

/// Puts the `openusage` command on the user's `PATH` by linking `/usr/local/bin/openusage` to the
/// helper inside the app, so an in-place app update updates the command too.
///
/// Writing to `/usr/local/bin` needs administrator rights, which the standard macOS password prompt
/// grants (through `osascript`); nothing runs with them but one `ln` or `rm`.
struct CommandLineInstaller: Sendable {
    enum Status: Equatable, Sendable {
        /// Not running from an app bundle that carries the command (a `swift run` build).
        case unavailable
        case notInstalled
        case installed
        /// `openusage` is a link to somewhere else: another copy of the app, or one that has moved.
        case linkedElsewhere(String)
        /// A real file, not a link, sits where the link would go; the app never replaces those.
        case occupied
    }

    enum InstallError: Error, Equatable, LocalizedError {
        case unavailable
        case notOurs
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "The command isn't part of this build of the app."
            case .notOurs: "The existing openusage isn't a link to this app, so it was left alone."
            case .failed(let message): message
            }
        }
    }

    static let linkPath = "/usr/local/bin/openusage"
    static let helperName = "openusage-cli"

    var helper: URL
    var linkPath = Self.linkPath
    /// Runs a shell command as administrator and returns its failure message, or `nil` on success.
    var runPrivileged: @Sendable (String) async -> String? = Self.runWithAdministratorPrompt

    /// The helper in the running app's bundle.
    static func forRunningApp() -> CommandLineInstaller {
        CommandLineInstaller(helper: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(helperName)"))
    }

    func status() -> Status {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: helper.path) else { return .unavailable }
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkPath) {
            return Self.samePath(destination, helper.path) ? .installed : .linkedElsewhere(destination)
        }
        return fileManager.fileExists(atPath: linkPath) ? .occupied : .notInstalled
    }

    /// Links the command, replacing a link to another copy of the app but never a real file.
    func install() async throws {
        switch status() {
        case .unavailable: throw InstallError.unavailable
        case .occupied: throw InstallError.notOurs
        case .installed: return
        case .notInstalled, .linkedElsewhere: break
        }
        let directory = (linkPath as NSString).deletingLastPathComponent
        try await run("mkdir -p \(Self.shellQuoted(directory)) && ln -sfn \(Self.shellQuoted(helper.path)) \(Self.shellQuoted(linkPath))")
    }

    /// Removes the link, but only when it is the one this app made.
    func uninstall() async throws {
        guard status() == .installed else { throw InstallError.notOurs }
        try await run("rm \(Self.shellQuoted(linkPath))")
    }

    private func run(_ command: String) async throws {
        if let message = await runPrivileged(command) { throw InstallError.failed(message) }
    }

    // MARK: - Quoting

    /// A single-quoted shell word.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The AppleScript that runs `command` as administrator. The command sits in a string literal, so
    /// backslashes and double quotes are escaped.
    static func administratorScript(for command: String) -> String {
        let literal = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(literal)\" with administrator privileges"
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        URL(fileURLWithPath: lhs).standardizedFileURL.path == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }

    private static let runWithAdministratorPrompt: @Sendable (String) async -> String? = { command in
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", administratorScript(for: command)]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return error.localizedDescription
            }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus != 0 else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            // osascript reports a dismissed password prompt as error -128.
            return text.contains("-128") ? "Canceled." : "Couldn't set up the command."
        }.value
    }
}
