import SwiftUI

/// SwiftUI wrapper around `SimulatorScreenView`. Re-attaches when `deviceUDID` changes and
/// forwards all of the view's tunables (interaction state, touch indicators, surface
/// callbacks) so callers can use this view as-is without dropping down to `NSViewRepresentable`
/// themselves.
@MainActor
public struct SimulatorScreen: NSViewRepresentable {
  public let deviceUDID: String
  public var interactionState: SimulatorInteractionState?
  public var showTouchIndicators: Bool
  public var onImageSize: (@MainActor (CGSize) -> Void)?
  public var onSurfaceFrame: (@MainActor (IOSurface) -> Void)?
  public var onError: (@MainActor (SimKitError) -> Void)?
  /// Fires once each time SwiftUI builds the underlying `NSView`. Use this to stash a
  /// reference if you need to call `press`, `tap`, etc. from outside the view tree.
  public var onAttached: (@MainActor (SimulatorScreenView) -> Void)?

  public init(
    deviceUDID: String,
    interactionState: SimulatorInteractionState? = nil,
    showTouchIndicators: Bool = true,
    onImageSize: (@MainActor (CGSize) -> Void)? = nil,
    onSurfaceFrame: (@MainActor (IOSurface) -> Void)? = nil,
    onError: (@MainActor (SimKitError) -> Void)? = nil,
    onAttached: (@MainActor (SimulatorScreenView) -> Void)? = nil
  ) {
    self.deviceUDID = deviceUDID
    self.interactionState = interactionState
    self.showTouchIndicators = showTouchIndicators
    self.onImageSize = onImageSize
    self.onSurfaceFrame = onSurfaceFrame
    self.onError = onError
    self.onAttached = onAttached
  }

  public func makeNSView(context: Context) -> SimulatorScreenView {
    let view = SimulatorScreenView(frame: .zero)
    apply(to: view)
    attempt(attach: view)
    onAttached?(view)
    return view
  }

  public func updateNSView(_ view: SimulatorScreenView, context: Context) {
    apply(to: view)
    if view.attachedUDID != deviceUDID {
      attempt(attach: view)
    }
  }

  public static func dismantleNSView(_ view: SimulatorScreenView, coordinator: ()) {
    view.detach()
  }

  private func apply(to view: SimulatorScreenView) {
    view.interactionState = interactionState
    view.showTouchIndicators = showTouchIndicators
    view.onImageSizeChange = onImageSize
    view.onSurfaceFrame = onSurfaceFrame
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
