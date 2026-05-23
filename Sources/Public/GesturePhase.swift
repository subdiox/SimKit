/// Phase of a streaming touch gesture.
public enum GesturePhase: String, Sendable, Equatable, CaseIterable {
  case down
  case move
  case up
}
