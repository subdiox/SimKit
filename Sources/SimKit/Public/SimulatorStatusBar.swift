import Foundation

/// `xcrun simctl status_bar override` wrapper. Lets callers force the time, battery,
/// network bars, etc. — invaluable for App Store screenshots.
public enum SimulatorStatusBar: Sendable {

  @discardableResult
  public static func apply(_ override: Override, udid: String) async -> Bool {
    await runSimctl(["status_bar", udid, "override"] + override.arguments)
  }

  @discardableResult
  public static func clear(udid: String) async -> Bool {
    await runSimctl(["status_bar", udid, "clear"])
  }

  @concurrent
  @discardableResult
  private static func runSimctl(_ arguments: [String]) async -> Bool {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/xcrun")
    process.arguments = ["simctl"] + arguments
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do { try process.run() } catch { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
  }
}
