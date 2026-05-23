import Foundation
import ObjectiveC

/// Loads `CoreSimulator.framework` and `SimulatorKit.framework` at runtime. They are not
/// linked at build time because their location depends on the user's active Xcode (which
/// `xcode-select -p` may or may not point at).
///
/// Derived from baguette (Apache 2.0).
struct CoreSimulatorRuntime: Sendable {
  enum LoadError: Error, CustomStringConvertible {
    case coreSimulatorMissing(detail: String)
    case simulatorKitMissing(detail: String)

    var description: String {
      switch self {
      case .coreSimulatorMissing(let detail):
        "CoreSimulator.framework load failed: \(detail)"
      case .simulatorKitMissing(let detail):
        "SimulatorKit.framework load failed: \(detail)"
      }
    }
  }

  let developerDir: String

  init(developerDir: String? = nil) {
    self.developerDir = developerDir ?? Self.resolveDeveloperDir()
  }

  /// Idempotent: subsequent dlopens just bump the refcount.
  func load() throws {
    let coreSim = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
    if dlopen(coreSim, RTLD_NOW | RTLD_GLOBAL) == nil {
      throw LoadError.coreSimulatorMissing(detail: dlerrorString())
    }
    let simKit = (developerDir as NSString)
      .appendingPathComponent("Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit")
    if dlopen(simKit, RTLD_NOW | RTLD_GLOBAL) == nil {
      throw LoadError.simulatorKitMissing(detail: dlerrorString())
    }
  }

  /// `xcode-select -p` is the first choice but commonly points at `CommandLineTools` (no
  /// SimulatorKit). In that case scan `/Applications` for any `Xcode*.app` whose
  /// `Contents/Developer` has SimulatorKit.
  private static func resolveDeveloperDir() -> String {
    if let dir = xcodeSelectDir(), hasSimulatorKit(at: dir) { return dir }
    if let dir = scanApplications() { return dir }
    return xcodeSelectDir() ?? "/Applications/Xcode.app/Contents/Developer"
  }

  private static func xcodeSelectDir() -> String? {
    let pipe = Pipe()
    let task = Process()
    task.executableURL = URL(filePath: "/usr/bin/xcode-select")
    task.arguments = ["-p"]
    task.standardOutput = pipe
    do { try task.run() } catch { return nil }
    task.waitUntilExit()
    let out =
      String(
        data: pipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return out.isEmpty ? nil : out
  }

  private static func hasSimulatorKit(at developerDir: String) -> Bool {
    let path = (developerDir as NSString)
      .appendingPathComponent("Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit")
    return FileManager.default.fileExists(atPath: path)
  }

  private static func scanApplications() -> String? {
    let canonical = "/Applications/Xcode.app/Contents/Developer"
    if hasSimulatorKit(at: canonical) { return canonical }
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
    for app in entries.sorted()
    where app.hasPrefix("Xcode") && app.hasSuffix(".app") && app != "Xcode.app" {
      let dir = "/Applications/\(app)/Contents/Developer"
      if hasSimulatorKit(at: dir) { return dir }
    }
    return nil
  }
}
