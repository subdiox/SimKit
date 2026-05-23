import CoreLocation
import Foundation

/// `xcrun simctl location` wrappers. Mirrors Simulator.app's `Features → Location` menu.
public enum SimulatorLocation: Sendable {

  /// Clears any host-side location override; the simulator falls back to whatever
  /// CoreLocation would normally produce (typically nothing).
  @discardableResult
  public static func clear(udid: String) async -> Bool {
    await runSimctl(["location", udid, "clear"])
  }

  /// Pins the simulator to a fixed coordinate.
  @discardableResult
  public static func set(_ coordinate: CLLocationCoordinate2D, udid: String) async -> Bool {
    let value = "\(coordinate.latitude),\(coordinate.longitude)"
    return await runSimctl(["location", udid, "set", value])
  }

  /// Plays back one of simctl's built-in routes (city run, freeway drive, etc.). The
  /// playback loops until `clear(udid:)` is called.
  @discardableResult
  public static func run(_ route: PresetRoute, udid: String) async -> Bool {
    await runSimctl(["location", udid, "run", route.rawValue])
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
