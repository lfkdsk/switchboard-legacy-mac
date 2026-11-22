import Foundation
import Combine

enum LaunchAgentError: Error {
    case appBundleRequired
}

/// Catalina-compatible login item implemented as a per-user LaunchAgent.
enum LaunchAgentManager {
    static let label = "org.lfkdsk.switchboard.legacy.login"

    static func plistURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    static func appExecutableURL(bundleURL: URL = Bundle.main.bundleURL) -> URL? {
        guard bundleURL.pathExtension == "app" else { return nil }
        return bundleURL.appendingPathComponent("Contents/MacOS/Switchboard", isDirectory: false)
    }

    static func configuration(executableURL: URL) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executableURL.path, "--launch-at-login"],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
    }

    static func isEnabled(plistURL: URL, executableURL: URL?) -> Bool {
        guard let executableURL,
              let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ),
              let dictionary = object as? [String: Any],
              dictionary["Label"] as? String == label,
              let arguments = dictionary["ProgramArguments"] as? [String],
              arguments.first == executableURL.path,
              dictionary["RunAtLoad"] as? Bool == true else { return false }
        return true
    }

    static func setEnabled(
        _ enabled: Bool,
        plistURL: URL = plistURL(),
        executableURL: URL? = appExecutableURL()
    ) throws {
        if !enabled {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return
        }

        guard let executableURL else { throw LaunchAgentError.appBundleRequired }
        let data = try PropertyListSerialization.data(
            fromPropertyList: configuration(executableURL: executableURL),
            format: .xml,
            options: 0
        )
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: plistURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: plistURL.path
        )
    }
}

/// User-facing preferences, persisted in UserDefaults, plus the login-item toggle.
@MainActor
final class Prefs: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let server = "server"
        static let shell = "shell"
        static let peer = "peer"
    }

    static let defaultServer = "https://shell.lfkdsk.org"

    @Published var server: String {
        didSet { defaults.set(server, forKey: Key.server) }
    }
    /// Empty means "let the daemon pick $SHELL".
    @Published var shell: String {
        didSet { defaults.set(shell, forKey: Key.shell) }
    }
    /// May the account's *other* machines run commands here (`switchboard exec`)?
    /// On by default, like the CLI. A GUI app inherits launchd's environment
    /// rather than your shell's, so SWITCHBOARD_PEER isn't something a user could
    /// set here — this toggle is the only way to say no.
    @Published var peer: Bool {
        didSet { defaults.set(peer, forKey: Key.peer) }
    }

    @Published var launchAtLogin: Bool = false

    init() {
        server = defaults.string(forKey: Key.server) ?? Prefs.defaultServer
        shell = defaults.string(forKey: Key.shell) ?? ""
        peer = defaults.object(forKey: Key.peer) as? Bool ?? true
        refreshLoginItem()
    }

    var normalizedServer: String {
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? Prefs.defaultServer : s
    }

    // MARK: Launch at login (Catalina LaunchAgent)

    func refreshLoginItem() {
        launchAtLogin = LaunchAgentManager.isEnabled(
            plistURL: LaunchAgentManager.plistURL(),
            executableURL: LaunchAgentManager.appExecutableURL()
        )
    }

    /// Returns false if the toggle couldn't be applied — e.g. running as a bare
    /// `swift run` binary rather than a registered .app bundle.
    @discardableResult
    func setLaunchAtLogin(_ on: Bool) -> Bool {
        do {
            try LaunchAgentManager.setEnabled(on)
            refreshLoginItem()
            return launchAtLogin == on
        } catch {
            refreshLoginItem()
            return false
        }
    }
}
