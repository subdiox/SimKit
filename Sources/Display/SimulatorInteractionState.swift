import AppKit
import Foundation
import Observation

/// Observable feedback channel published by `SimulatorScreenView` so SwiftUI overlays can
/// react to cursor motion, modifier state, and active touches without polling. Coordinates
/// are normalized (0…1) relative to the simulator's image rect, with the origin at the
/// top-left of the device screen.
@MainActor
@Observable
public final class SimulatorInteractionState {
  /// Cursor position inside the simulator image, or nil when the mouse is outside it.
  public internal(set) var cursorPosition: CGPoint?

  /// `true` while the user is holding the Option key (used to preview two-finger touches).
  public internal(set) var isOptionHeld: Bool = false

  /// Currently active touches. Contains zero (no press), one (regular drag), or two
  /// (Option-modified pinch) normalized points.
  public internal(set) var activeTouches: [CGPoint] = []

  public init() {}
}
