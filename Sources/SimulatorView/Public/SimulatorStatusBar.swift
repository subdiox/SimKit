import Foundation

/// `xcrun simctl status_bar override` wrapper. Lets callers force the time, battery,
/// network bars, etc. — invaluable for App Store screenshots.
public enum SimulatorStatusBar: Sendable {

    public enum DataNetwork: String, Sendable, CaseIterable {
        case wifi, hide, lte = "lte", threeG = "3g", fourG = "4g", fiveG = "5g"
    }

    public enum BatteryState: String, Sendable, CaseIterable {
        case unplugged, charging, charged
    }

    public struct Override: Sendable {
        public var time: String?
        public var batteryLevel: Int?
        public var batteryState: BatteryState?
        public var dataNetwork: DataNetwork?
        public var wifiBars: Int?
        public var cellularBars: Int?
        public var operatorName: String?

        public init(
            time: String? = "9:41",
            batteryLevel: Int? = 100,
            batteryState: BatteryState? = .charged,
            dataNetwork: DataNetwork? = .wifi,
            wifiBars: Int? = 3,
            cellularBars: Int? = 4,
            operatorName: String? = ""
        ) {
            self.time = time
            self.batteryLevel = batteryLevel
            self.batteryState = batteryState
            self.dataNetwork = dataNetwork
            self.wifiBars = wifiBars
            self.cellularBars = cellularBars
            self.operatorName = operatorName
        }

        fileprivate var arguments: [String] {
            var args: [String] = []
            if let time { args += ["--time", time] }
            if let batteryLevel { args += ["--batteryLevel", String(batteryLevel)] }
            if let batteryState { args += ["--batteryState", batteryState.rawValue] }
            if let dataNetwork { args += ["--dataNetwork", dataNetwork.rawValue] }
            if let wifiBars { args += ["--wifiBars", String(wifiBars)] }
            if let cellularBars { args += ["--cellularBars", String(cellularBars)] }
            if let operatorName { args += ["--operatorName", operatorName] }
            return args
        }
    }

    @discardableResult
    public static func apply(_ override: Override, udid: String) async -> Bool {
        await runSimctl(["status_bar", udid, "override"] + override.arguments)
    }

    @discardableResult
    public static func clear(udid: String) async -> Bool {
        await runSimctl(["status_bar", udid, "clear"])
    }

    @discardableResult
    private static func runSimctl(_ arguments: [String]) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/xcrun")
            process.arguments = ["simctl"] + arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do { try process.run() } catch { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
    }
}
