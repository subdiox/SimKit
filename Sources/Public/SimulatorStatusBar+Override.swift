extension SimulatorStatusBar {
  public struct Override: Sendable {
    public var time: String?
    public var batteryLevel: Int?
    public var batteryState: BatteryState?
    public var dataNetwork: DataNetwork?
    public var wifiBars: Int?
    public var cellularBars: Int?
    public var operatorName: String?

    public init(
      time: String? = "9:41",
      batteryLevel: Int? = 100,
      batteryState: BatteryState? = .charged,
      dataNetwork: DataNetwork? = .wifi,
      wifiBars: Int? = 3,
      cellularBars: Int? = 4,
      operatorName: String? = ""
    ) {
      self.time = time
      self.batteryLevel = batteryLevel
      self.batteryState = batteryState
      self.dataNetwork = dataNetwork
      self.wifiBars = wifiBars
      self.cellularBars = cellularBars
      self.operatorName = operatorName
    }

    var arguments: [String] {
      var args: [String] = []
      if let time { args += ["--time", time] }
      if let batteryLevel { args += ["--batteryLevel", String(batteryLevel)] }
      if let batteryState { args += ["--batteryState", batteryState.rawValue] }
      if let dataNetwork { args += ["--dataNetwork", dataNetwork.rawValue] }
      if let wifiBars { args += ["--wifiBars", String(wifiBars)] }
      if let cellularBars { args += ["--cellularBars", String(cellularBars)] }
      if let operatorName { args += ["--operatorName", operatorName] }
      return args
    }
  }
}
