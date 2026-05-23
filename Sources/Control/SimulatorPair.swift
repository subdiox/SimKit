import Foundation

/// `xcrun simctl pair / unpair / pair_activate` — manage Apple Watch ↔ iPhone pairing.
/// Required for watchOS simulators that need to talk to a paired iPhone (e.g. apps that
/// fetch data from the iPhone companion app).
public enum SimulatorPair: Sendable {

  /// Pair a booted watch simulator with a booted phone simulator. Returns the pair UUID
  /// (a hex string CoreSimulator assigns) on success, or `nil` if pairing failed.
  public static func pair(watch watchUDID: String, phone phoneUDID: String) async -> String? {
    let result = await runSimctlCapturing(["pair", watchUDID, phoneUDID])
    guard result.exitCode == 0 else { return nil }
    let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Tear down a pair by its UUID.
  @discardableResult
  public static func unpair(pairUUID: String) async -> Bool {
    await runSimctl(["unpair", pairUUID])
  }

  /// Make the given pair the active one — CoreSimulator routes Watch Connectivity through
  /// it until another pair is activated.
  @discardableResult
  public static func activate(pairUUID: String) async -> Bool {
    await runSimctl(["pair_activate", pairUUID])
  }

  // MARK: - internals

  @concurrent
  @discardableResult
  private static func runSimctl(_ arguments: [String]) async -> Bool {
    await runSimctlCapturing(arguments).exitCode == 0
  }

  private struct CapturedResult: Sendable {
    let exitCode: Int32
    let stdout: String
  }

  @concurrent
  private static func runSimctlCapturing(_ arguments: [String]) async -> CapturedResult {
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
  }
}
