import SwiftUI

/// SwiftUI wrapper around `SimulatorScreenView`. Re-attaches when `deviceUDID` changes.
@MainActor
public struct SimulatorScreen: NSViewRepresentable {
  public let deviceUDID: String
  public var onError: (@MainActor (SimKitError) -> Void)?

  public init(
    deviceUDID: String,
    onError: (@MainActor (SimKitError) -> Void)? = nil
  ) {
    self.deviceUDID = deviceUDID
    self.onError = onError
  }

  public func makeNSView(context: Context) -> SimulatorScreenView {
    let view = SimulatorScreenView(frame: .zero)
    attempt(attach: view)
    return view
  }

  public func updateNSView(_ view: SimulatorScreenView, context: Context) {
    if view.attachedUDID != deviceUDID {
      attempt(attach: view)
    }
  }

  public static func dismantleNSView(_ view: SimulatorScreenView, coordinator: ()) {
    view.detach()
  }

  private func attempt(attach view: SimulatorScreenView) {
    do {
      try view.attach(deviceUDID: deviceUDID)
    } catch let error as SimKitError {
      onError?(error)
    } catch {
      onError?(.frameworkLoadFailed(detail: String(describing: error)))
    }
  }
}
