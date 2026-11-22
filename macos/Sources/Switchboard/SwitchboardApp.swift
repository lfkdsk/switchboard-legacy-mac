import AppKit
import Foundation

/// AppKit entry point with headless verification paths for CI.
@main
enum EntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }
        if CommandLine.arguments.contains("--update-check") {
            UpdateCheckCLI.run()
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

/// Headless `--update-check`: one registry check + stage, result on stderr.
/// Exercises the exact code path the menu button uses.
enum UpdateCheckCLI {
    static func run() {
        DispatchQueue.main.async {
            Task { @MainActor in
                let updater = DaemonUpdater()
                await updater.checkAndApply()
                let line = updater.status.line ?? "no status"
                FileHandle.standardError.write(Data("[update-check] \(line)\n".utf8))
                if case .failed = updater.status { exit(1) }
                exit(0)
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(120))
        exit(2) // watchdog: never came back from the check
    }
}

/// Makes the process a menu-bar accessory (no Dock icon, no ⌘-Tab entry) even
/// when run as a bare SwiftPM binary, and auto-starts the daemon if a saved
/// login exists. The bundled .app additionally sets LSUIElement in Info.plist.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var supervisor: DaemonSupervisor?
    private var menuController: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let prefs = Prefs()
        let supervisor = DaemonSupervisor(prefs: prefs)
        let updater = DaemonUpdater()
        let accountStore = AccountStore(supervisor: supervisor)
        let fullDiskAccess = FullDiskAccessStore()
        updater.supervisor = supervisor

        self.supervisor = supervisor
        menuController = MenuController(
            supervisor: supervisor,
            prefs: prefs,
            updater: updater,
            accountStore: accountStore,
            fullDiskAccess: fullDiskAccess
        )
        updater.startAutoChecks()

        // Auto-start only when signed in. Anonymous token mode waits for Start.
        if ConfigReader.read().signedIn {
            supervisor.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        supervisor?.stop()
    }
}
