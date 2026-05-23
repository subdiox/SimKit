import Foundation

public enum SimKitError: Error, LocalizedError {
  case frameworkLoadFailed(detail: String)
  case deviceNotFound(udid: String)
  case ioUnavailable
  case noFramebuffer
  case callbackRegistrationFailed

  public var errorDescription: String? {
    switch self {
    case .frameworkLoadFailed(let detail):
      "Failed to load CoreSimulator/SimulatorKit: \(detail)"
    case .deviceNotFound(let udid):
      "No SimDevice for UDID \(udid)."
    case .ioUnavailable:
      "Simulator has no SimDeviceIOClient (is it booted?)."
    case .noFramebuffer:
      "Simulator exposes no framebuffer display port."
    case .callbackRegistrationFailed:
      "Failed to register an IOSurface callback on the framebuffer descriptor."
    }
  }
}
