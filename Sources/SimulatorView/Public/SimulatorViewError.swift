import Foundation

public enum SimulatorViewError: Error, CustomStringConvertible {
    case frameworkLoadFailed(detail: String)
    case deviceNotFound(udid: String)
    case ioUnavailable
    case noFramebuffer
    case callbackRegistrationFailed

    public var description: String {
        switch self {
        case .frameworkLoadFailed(let detail):
            return "Failed to load CoreSimulator/SimulatorKit: \(detail)"
        case .deviceNotFound(let udid):
            return "No SimDevice for UDID \(udid)."
        case .ioUnavailable:
            return "Simulator has no SimDeviceIOClient (is it booted?)."
        case .noFramebuffer:
            return "Simulator exposes no framebuffer display port."
        case .callbackRegistrationFailed:
            return "Failed to register an IOSurface callback on the framebuffer descriptor."
        }
    }
}
