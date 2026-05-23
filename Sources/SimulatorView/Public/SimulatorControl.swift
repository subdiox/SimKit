import Foundation

/// Lightweight wrappers around `xcrun simctl` for the actions Simulator.app exposes in its
/// Device / Features / I/O / Debug / Edit menus that don't need private framework access.
///
/// All methods take a `udid` so callers can address any simulator on the host. Methods
/// return success/failure; stderr is swallowed (consumers that need diagnostics should call
/// `xcrun simctl` themselves with `simctl spawn` etc.).
public enum SimulatorControl: Sendable {

    // MARK: - Device

    /// Wipes the simulator's contents and settings. **Destructive** — caller is responsible
    /// for showing a confirmation prompt.
    @discardableResult
    public static func erase(udid: String) async -> Bool {
        await runSimctl(["erase", udid])
    }

    /// Shuts the device down then boots it back up. Useful after toggling defaults that
    /// only re-read at launch.
    @discardableResult
    public static func restart(udid: String) async -> Bool {
        _ = await runSimctl(["shutdown", udid])
        return await runSimctl(["boot", udid])
    }

    /// Opens a URL inside the simulator (deep link / web link).
    @discardableResult
    public static func openURL(_ url: URL, udid: String) async -> Bool {
        await runSimctl(["openurl", udid, url.absoluteString])
    }

    // MARK: - Appearance

    public enum Appearance: String, Sendable, CaseIterable {
        case light, dark
    }

    /// Reads the current UIUserInterfaceStyle for the simulator. Returns nil when the
    /// command fails (older simulators, etc.).
    public static func appearance(udid: String) async -> Appearance? {
        let result = await runSimctlCapturing(["ui", udid, "appearance"])
        guard result.exitCode == 0 else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return Appearance(rawValue: trimmed)
    }

    @discardableResult
    public static func setAppearance(_ appearance: Appearance, udid: String) async -> Bool {
        await runSimctl(["ui", udid, "appearance", appearance.rawValue])
    }

    // MARK: - Pasteboard

    /// Copies the macOS host's clipboard contents *into* the simulator's pasteboard.
    @discardableResult
    public static func sendPasteboardToSimulator(udid: String) async -> Bool {
        await runSimctl(["pbcopy", udid])
    }

    /// Copies the simulator's pasteboard contents *out* to the macOS host clipboard.
    @discardableResult
    public static func getPasteboardFromSimulator(udid: String) async -> Bool {
        await runSimctl(["pbpaste", udid])
    }

    // MARK: - Notifications (memory warning, iCloud sync, etc.)

    /// Forces a UIApplicationDidReceiveMemoryWarning notification inside the simulator.
    @discardableResult
    public static func simulateMemoryWarning(udid: String) async -> Bool {
        await postDarwinNotification(udid: udid, name: "com.apple.SimulatorBridge.MemoryWarning")
    }

    /// Triggers `Features → Trigger iCloud Sync`.
    @discardableResult
    public static func triggerIcloudSync(udid: String) async -> Bool {
        await runSimctl(["icloud_sync", udid])
    }

    /// Sends a Darwin notification into the simulator. Many menu items in Simulator.app
    /// boil down to a single notification on a known key — exposed publicly so callers can
    /// add their own without forking the library.
    @discardableResult
    public static func postDarwinNotification(udid: String, name: String) async -> Bool {
        await runSimctl(["spawn", udid, "notifyutil", "-p", name])
    }

    /// Sets the integer state value of a Darwin notification inside the simulator (the
    /// mechanism used for enrollment toggles, slow-animations flag, etc.).
    @discardableResult
    public static func setDarwinNotificationState(udid: String, name: String, value: Int) async -> Bool {
        await runSimctl(["spawn", udid, "notifyutil", "-s", name, String(value)])
    }

    // MARK: - Internals

    @discardableResult
    private static func runSimctl(_ arguments: [String]) async -> Bool {
        await runSimctlCapturing(arguments).exitCode == 0
    }

    private struct CapturedResult: Sendable {
        let exitCode: Int32
        let stdout: String
    }

    private static func runSimctlCapturing(_ arguments: [String]) async -> CapturedResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/xcrun")
            process.arguments = ["simctl"] + arguments
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            do { try process.run() } catch {
                return CapturedResult(exitCode: -1, stdout: "")
            }
            process.waitUntilExit()
            let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
            return CapturedResult(
                exitCode: process.terminationStatus,
                stdout: String(data: data, encoding: .utf8) ?? ""
            )
        }.value
    }
}
