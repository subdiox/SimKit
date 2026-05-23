import Foundation

/// Triggers biometric events on a specific booted simulator the way Simulator.app's
/// `Features → Face ID / Touch ID` menu does. iOS inside the simulator listens for Darwin
/// notifications on its own notification domain, distinct from the macOS host's — so we
/// post via `xcrun simctl spawn <udid> notifyutil ...` which runs `notifyutil` *inside*
/// the simulator.
///
/// Apple's internal codename for Face ID is "pearl"; Touch ID is "fingerTouch". The
/// enrollment flag rides on `com.apple.BiometricKit.enrollmentChanged` (without `_Sim`) as
/// a Darwin notification state — iOS BiometricKit reads it via `notify_get_state()`.
public enum SimulatorBiometrics: Sendable {
    public enum Kind: Sendable {
        case faceID
        case touchID

        fileprivate var matchNotification: String {
            switch self {
            case .faceID: return "com.apple.BiometricKit_Sim.pearl.match"
            case .touchID: return "com.apple.BiometricKit_Sim.fingerTouch.match"
            }
        }

        fileprivate var nonMatchNotification: String {
            switch self {
            case .faceID: return "com.apple.BiometricKit_Sim.pearl.nomatch"
            case .touchID: return "com.apple.BiometricKit_Sim.fingerTouch.nomatch"
            }
        }
    }

    private static let enrollmentKey = "com.apple.BiometricKit.enrollmentChanged"

    @discardableResult
    public static func match(_ kind: Kind, udid: String) -> Bool {
        post(udid: udid, name: kind.matchNotification)
    }

    @discardableResult
    public static func nonMatch(_ kind: Kind, udid: String) -> Bool {
        post(udid: udid, name: kind.nonMatchNotification)
    }

    /// Reads the current enrolled state from the simulator's Darwin notification store.
    public static func isEnrolled(udid: String) async -> Bool {
        let result = await spawn(udid: udid, command: "notifyutil", args: ["-g", enrollmentKey])
        let stdout = result.stdout?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // `notifyutil -g` prints `<key> <value>`.
        if let last = stdout.split(separator: " ").last {
            return Int(last) == 1
        }
        return false
    }

    /// Sets the enrolled state. Internally calls `notifyutil -s` which both stores the
    /// state and posts the notification, so BiometricKit picks up the change immediately.
    @discardableResult
    public static func setEnrolled(_ enrolled: Bool, udid: String) async -> Bool {
        let result = await spawn(
            udid: udid,
            command: "notifyutil",
            args: ["-s", enrollmentKey, enrolled ? "1" : "0"]
        )
        return result.exitCode == 0
    }

    @discardableResult
    private static func post(udid: String, name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "spawn", udid, "notifyutil", "-p", name]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private struct SpawnResult: Sendable {
        let exitCode: Int32
        let stdout: String?
    }

    private static func spawn(udid: String, command: String, args: [String]) async -> SpawnResult {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "spawn", udid, command] + args
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            do { try process.run() } catch {
                return SpawnResult(exitCode: -1, stdout: nil)
            }
            process.waitUntilExit()
            let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
            return SpawnResult(exitCode: process.terminationStatus, stdout: String(data: data, encoding: .utf8))
        }.value
    }
}
