import AppKit
import Combine
import Foundation

extension ConnState {
    var title: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .connecting: return "Connecting…"
        case .online: return "Online"
        case .reconnecting: return "Reconnecting…"
        case .fatal(let reason): return reason.headline
        }
    }

    var statusColor: NSColor {
        switch self {
        case .online: return .systemGreen
        case .starting, .connecting, .reconnecting: return .systemOrange
        case .fatal: return .systemRed
        case .stopped: return .secondaryLabelColor
        }
    }
}

/// Native AppKit status item and NSMenu. No SwiftUI API is used, so this path
/// is available on the full macOS 10.15 deployment target.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let supervisor: DaemonSupervisor
    private let prefs: Prefs
    private let updater: DaemonUpdater
    private let accountStore: AccountStore
    private let fullDiskAccess: FullDiskAccessStore
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var subscriptions = Set<AnyCancellable>()

    init(
        supervisor: DaemonSupervisor,
        prefs: Prefs,
        updater: DaemonUpdater,
        accountStore: AccountStore,
        fullDiskAccess: FullDiskAccessStore
    ) {
        self.supervisor = supervisor
        self.prefs = prefs
        self.updater = updater
        self.accountStore = accountStore
        self.fullDiskAccess = fullDiskAccess
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            button.toolTip = "Switchboard"
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        }

        supervisor.$state
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &subscriptions)
        supervisor.$peerOnline
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &subscriptions)
        updater.$status
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &subscriptions)
        refreshStatusItem()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        accountStore.refresh()
        fullDiskAccess.refresh()
        prefs.refreshLoginItem()
        updater.refresh()
        rebuildMenu()
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if case .failed = updater.status {
            symbol = "!"
        } else {
            switch supervisor.state {
            case .fatal: symbol = "!"
            default: symbol = "●"
            }
        }
        button.attributedTitle = NSAttributedString(
            string: symbol,
            attributes: [
                .foregroundColor: supervisor.state.statusColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
        let viewer = supervisor.peerOnline ? " — viewer connected" : ""
        button.toolTip = "Switchboard: \(supervisor.state.title)\(viewer)"
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let machine = supervisor.machineName ?? Host.current().localizedName ?? "This Mac"
        var header = "\(supervisor.state.title) — \(machine)"
        if let mode = supervisor.mode { header += " · \(mode)" }
        if supervisor.peerOnline { header += " · viewer active" }
        addInformation(header)

        if case .fatal(let reason) = supervisor.state {
            addInformation(reason.hint)
        } else if supervisor.state == .online {
            let rtt = supervisor.rtt.map { "\(Int($0)) ms" } ?? "—"
            let cpu = supervisor.cpu.map { "\(Int($0 * 100))%" } ?? "—"
            addInformation("RTT \(rtt) · CPU \(cpu) · Memory \(memoryText)")
        }
        if supervisor.runtimeMissing {
            addInformation("Embedded Node runtime is missing.")
        }

        if accountStore.signedIn {
            addInformation("Signed in as \(accountStore.login ?? "unknown")")
        } else {
            addInformation("Not signed in")
        }
        menu.addItem(.separator())

        addAction(
            "Open Dashboard",
            action: #selector(openDashboard),
            enabled: (supervisor.dashboardURL ?? supervisor.shareURL) != nil
        )
        if supervisor.mode == "token", supervisor.shareURL != nil {
            addAction("Copy Share URL", action: #selector(copyShareURL))
        }
        menu.addItem(.separator())

        if supervisor.isRunning {
            addAction("Stop", action: #selector(stopDaemon))
            addAction("Restart", action: #selector(restartDaemon))
        } else {
            addAction("Start", action: #selector(startDaemon))
        }
        if accountStore.signedIn {
            addAction("Sign Out", action: #selector(signOut))
        } else {
            addAction("Sign In…", action: #selector(signIn))
        }
        menu.addItem(.separator())

        let active = updater.activeVersion ?? updater.bundledVersion ?? "unknown"
        let source = updater.hotUpdateActive ? "hot update" : "bundled"
        addInformation("CLI \(active) (\(source))")
        if let line = updater.status.line { addInformation(line) }
        addAction(
            "Check for CLI Updates…",
            action: #selector(checkForCLIUpdates),
            enabled: updater.status != .checking
        )
        menu.addItem(.separator())

        let peerItem = addAction(
            "Let Other Machines Run Commands Here",
            action: #selector(togglePeer)
        )
        peerItem.state = prefs.peer ? .on : .off

        let loginItem = addAction("Launch at Login", action: #selector(toggleLaunchAtLogin))
        loginItem.state = prefs.launchAtLogin ? .on : .off

        addAction("Connection Settings…", action: #selector(openConnectionSettings))
        if fullDiskAccess.isGranted {
            let access = addInformation("Full Disk Access Granted")
            access.state = .on
        } else {
            addAction(
                "Open Full Disk Access Settings…",
                action: #selector(openFullDiskAccessSettings)
            )
        }
        menu.addItem(.separator())

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "dev"
        addInformation("Switchboard Legacy \(version) · Catalina x64")
        let quit = addAction("Quit Switchboard", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
    }

    @discardableResult
    private func addInformation(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    @discardableResult
    private func addAction(
        _ title: String,
        action: Selector,
        enabled: Bool = true,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    private var memoryText: String {
        guard let used = supervisor.memUsed, let total = supervisor.memTotal, total > 0 else {
            return "—"
        }
        return "\(Int(used / total * 100))%"
    }

    @objc private func openDashboard() { supervisor.openDashboard() }
    @objc private func copyShareURL() { supervisor.copyShareURL() }
    @objc private func startDaemon() { supervisor.start() }
    @objc private func stopDaemon() { supervisor.stop() }
    @objc private func restartDaemon() { supervisor.restart() }
    @objc private func signIn() { supervisor.signIn() }
    @objc private func signOut() { supervisor.signOut() }

    @objc private func checkForCLIUpdates() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updater.checkAndApply()
        }
    }

    @objc private func togglePeer() {
        prefs.peer.toggle()
        if supervisor.isRunning { supervisor.restart() }
    }

    @objc private func toggleLaunchAtLogin() {
        let next = !prefs.launchAtLogin
        guard prefs.setLaunchAtLogin(next) else {
            showError(
                title: "Could Not Change Launch at Login",
                message: "Move Switchboard.app to /Applications, then try again."
            )
            return
        }
    }

    @objc private func openConnectionSettings() {
        let alert = NSAlert()
        alert.messageText = "Connection Settings"
        alert.informativeText = "Changes restart the daemon so they take effect immediately."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 78))
        let serverLabel = NSTextField(labelWithString: "Server")
        serverLabel.frame = NSRect(x: 0, y: 50, width: 70, height: 20)
        let serverField = NSTextField(frame: NSRect(x: 75, y: 46, width: 315, height: 24))
        serverField.stringValue = prefs.server
        serverField.placeholderString = Prefs.defaultServer
        let shellLabel = NSTextField(labelWithString: "Shell")
        shellLabel.frame = NSRect(x: 0, y: 14, width: 70, height: 20)
        let shellField = NSTextField(frame: NSRect(x: 75, y: 10, width: 315, height: 24))
        shellField.stringValue = prefs.shell
        shellField.placeholderString = "Use $SHELL"
        accessory.addSubview(serverLabel)
        accessory.addSubview(serverField)
        accessory.addSubview(shellLabel)
        accessory.addSubview(shellField)
        alert.accessoryView = accessory

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let changed = prefs.server != serverField.stringValue || prefs.shell != shellField.stringValue
        prefs.server = serverField.stringValue
        prefs.shell = shellField.stringValue
        if changed, supervisor.isRunning { supervisor.restart() }
    }

    @objc private func openFullDiskAccessSettings() {
        fullDiskAccess.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
