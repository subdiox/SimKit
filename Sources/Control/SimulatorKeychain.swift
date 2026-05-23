import Foundation

/// `xcrun simctl keychain` wrappers — manipulate a booted simulator's keychain. The most
/// common use is `reset(udid:)` to clear stored credentials between test runs (e.g. to
/// re-trigger biometric or "remember me" flows).
public enum SimulatorKeychain: Sendable {

  /// Erase every entry from the device's keychain.
  @discardableResult
  public static func reset(udid: String) async -> Bool {
    await runSimctl(["keychain", udid, "reset"])
  }

  /// Add a certificate (PEM/DER) to the device's standard keychain.
  @discardableResult
  public static func addCertificate(at path: String, udid: String) async -> Bool {
    await runSimctl(["keychain", udid, "add-cert", path])
  }

  /// Add a certificate to the trusted root store (so server TLS certs signed by it are
  /// trusted by URLSession etc.).
  @discardableResult
  public static func addRootCertificate(at path: String, udid: String) async -> Bool {
    await runSimctl(["keychain", udid, "add-root-cert", path])
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
