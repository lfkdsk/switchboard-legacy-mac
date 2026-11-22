import Foundation
import XCTest
@testable import Switchboard

final class MenuSupportTests: XCTestCase {
    func testAccountIdentityPrefersLiveDaemonAndFallsBackToConfig() {
        let config = AccountConfig(
            signedIn: true,
            login: "disk-user",
            machineId: nil,
            server: nil
        )

        XCTAssertEqual(
            AccountIdentityResolver.resolve(
                daemonAccount: "daemon-user",
                daemonRunning: true,
                config: config
            ),
            AccountIdentity(signedIn: true, login: "daemon-user")
        )
        XCTAssertEqual(
            AccountIdentityResolver.resolve(
                daemonAccount: "stale-daemon-user",
                daemonRunning: false,
                config: config
            ),
            AccountIdentity(signedIn: true, login: "disk-user")
        )
        XCTAssertEqual(
            AccountIdentityResolver.resolve(
                daemonAccount: nil,
                daemonRunning: true,
                config: config
            ),
            AccountIdentity(signedIn: true, login: "disk-user")
        )
    }

    func testFullDiskAccessProbeRequiresOneReadableCandidate() {
        let first = URL(fileURLWithPath: "/protected/one")
        let second = URL(fileURLWithPath: "/protected/two")
        var visited: [URL] = []

        XCTAssertTrue(FullDiskAccessProbe.isGranted(candidateURLs: [first, second]) { url in
            visited.append(url)
            return url == second
        })
        XCTAssertEqual(visited, [first, second])
        XCTAssertFalse(FullDiskAccessProbe.isGranted(candidateURLs: [first, second]) { _ in false })
    }

    func testFullDiskAccessSettingsFallsBackToLegacyURL() {
        XCTAssertEqual(
            FullDiskAccessSettings.urls(osMajorVersion: 10).map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            ]
        )
        XCTAssertEqual(
            FullDiskAccessSettings.urls(osMajorVersion: 13).map(\.absoluteString),
            [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            ]
        )
        let modern = URL(string: "test-settings:modern")!
        let legacy = URL(string: "test-settings:legacy")!
        var attempted: [URL] = []

        let opened = FullDiskAccessSettings.firstOpened(urls: [modern, legacy]) { url in
            attempted.append(url)
            return url == legacy
        }

        XCTAssertEqual(opened, legacy)
        XCTAssertEqual(attempted, [modern, legacy])
    }

    func testLaunchAgentUsesInstalledAppExecutableAndRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchboard-launch-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist = LaunchAgentManager.plistURL(homeDirectory: root)
        let executable = root.appendingPathComponent(
            "Applications/Switchboard.app/Contents/MacOS/Switchboard",
            isDirectory: false
        )

        try LaunchAgentManager.setEnabled(true, plistURL: plist, executableURL: executable)
        XCTAssertTrue(LaunchAgentManager.isEnabled(plistURL: plist, executableURL: executable))

        let data = try Data(contentsOf: plist)
        let object = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
        XCTAssertEqual(object["Label"] as? String, LaunchAgentManager.label)
        XCTAssertEqual(
            object["ProgramArguments"] as? [String],
            [executable.path, "--launch-at-login"]
        )
        XCTAssertEqual(object["RunAtLoad"] as? Bool, true)

        try LaunchAgentManager.setEnabled(false, plistURL: plist, executableURL: executable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plist.path))
    }

    func testLaunchAgentRejectsBareExecutableAndStaleAppPath() throws {
        XCTAssertNil(
            LaunchAgentManager.appExecutableURL(
                bundleURL: URL(fileURLWithPath: "/tmp/Switchboard", isDirectory: false)
            )
        )
        XCTAssertEqual(
            LaunchAgentManager.appExecutableURL(
                bundleURL: URL(fileURLWithPath: "/Applications/Switchboard.app", isDirectory: true)
            )?.path,
            "/Applications/Switchboard.app/Contents/MacOS/Switchboard"
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("switchboard-stale-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist = LaunchAgentManager.plistURL(homeDirectory: root)
        let oldExecutable = URL(fileURLWithPath: "/Old/Switchboard.app/Contents/MacOS/Switchboard")
        let newExecutable = URL(fileURLWithPath: "/Applications/Switchboard.app/Contents/MacOS/Switchboard")
        try LaunchAgentManager.setEnabled(true, plistURL: plist, executableURL: oldExecutable)
        XCTAssertFalse(LaunchAgentManager.isEnabled(plistURL: plist, executableURL: newExecutable))
    }
}
