extension SimulatorBiometrics {
  public enum Kind: Sendable {
    case faceID
    case touchID

    var matchNotification: String {
      switch self {
      case .faceID: "com.apple.BiometricKit_Sim.pearl.match"
      case .touchID: "com.apple.BiometricKit_Sim.fingerTouch.match"
      }
    }

    var nonMatchNotification: String {
      switch self {
      case .faceID: "com.apple.BiometricKit_Sim.pearl.nomatch"
      case .touchID: "com.apple.BiometricKit_Sim.fingerTouch.nomatch"
      }
    }
  }
}
