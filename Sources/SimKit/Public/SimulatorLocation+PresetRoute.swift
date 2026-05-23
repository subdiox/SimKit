extension SimulatorLocation {
  public enum PresetRoute: String, Sendable, CaseIterable {
    case cityRun = "city_run"
    case cityBicycleRide = "city_bicycle"
    case freewayDrive = "freeway_drive"
    case appleHQ = "apple"
  }
}
