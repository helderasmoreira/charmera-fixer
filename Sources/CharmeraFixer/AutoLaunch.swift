import Foundation

enum AutoLaunch {
    static let cameraVolume = "/Volumes/Untitled"
    private static let label = "io.github.helderasmoreira.charmera-fixer.autolaunch"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let launchctl = URL(fileURLWithPath: "/bin/launchctl")
        let domain = "gui/\(getuid())"
        _ = try? Shell.run(launchctl, ["bootout", "\(domain)/\(label)"])

        guard enabled else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.helderasmoreira.charmera-fixer"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/bin/sh", "-c",
                "[ -d '\(cameraVolume)/DCIM' ] && /usr/bin/open -b \(bundleID) || true",
            ],
            "WatchPaths": [cameraVolume],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: plistURL)
        try Shell.check(launchctl, ["bootstrap", domain, plistURL.path])
    }
}
