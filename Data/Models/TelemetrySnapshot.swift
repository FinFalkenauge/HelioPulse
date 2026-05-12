import Foundation

enum ChargeState: String, CaseIterable, Codable {
    case off = "Off"
    case bulk = "Bulk"
    case absorption = "Absorption"
    case float = "Float"
    case storage = "Storage"
}

enum PowerSource: String, CaseIterable, Codable {
    case solar = "Solar"
    case alternator = "Alternator"
    case load = "Load"
}

struct TelemetrySnapshot: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let solarPower: Double
    let solarVoltage: Double
    let solarCurrent: Double
    let batteryVoltage: Double
    let batteryCurrent: Double
    let loadCurrent: Double
    let chargeState: ChargeState
    let modeledSOC: Double
    let socConfidence: Double
    let driveMode: Bool
    let primarySource: PowerSource
}

struct TrendPoint: Identifiable, Codable {
    let id: UUID
    let hour: Int
    let solarPower: Double
    let loadPower: Double
    let batteryVoltage: Double

    init(hour: Int, solarPower: Double, loadPower: Double, batteryVoltage: Double) {
        self.id = UUID()
        self.hour = hour
        self.solarPower = solarPower
        self.loadPower = loadPower
        self.batteryVoltage = batteryVoltage
    }
}

extension TelemetrySnapshot {
    static let mock = TelemetrySnapshot(
        id: UUID(),
        timestamp: .now,
        solarPower: 182,
        solarVoltage: 45.57,
        solarCurrent: 4.0,
        batteryVoltage: 13.42,
        batteryCurrent: 4.6,
        loadCurrent: 4.6,
        chargeState: .absorption,
        modeledSOC: 78,
        socConfidence: 0.92,
        driveMode: false,
        primarySource: .solar
    )

    static let driveMock = TelemetrySnapshot(
        id: UUID(),
        timestamp: .now,
        solarPower: 18,
        solarVoltage: 19.8,
        solarCurrent: 0.9,
        batteryVoltage: 14.12,
        batteryCurrent: 13.6,
        loadCurrent: 4.1,
        chargeState: .float,
        modeledSOC: 91,
        socConfidence: 0.63,
        driveMode: true,
        primarySource: .alternator
    )

    static let mockTrend: [TrendPoint] = [
        .init(hour: 0, solarPower: 10, loadPower: 90, batteryVoltage: 12.9),
        .init(hour: 3, solarPower: 0, loadPower: 120, batteryVoltage: 12.5),
        .init(hour: 6, solarPower: 45, loadPower: 140, batteryVoltage: 12.8),
        .init(hour: 9, solarPower: 180, loadPower: 110, batteryVoltage: 13.4),
        .init(hour: 12, solarPower: 260, loadPower: 95, batteryVoltage: 13.8),
        .init(hour: 15, solarPower: 210, loadPower: 105, batteryVoltage: 13.7),
        .init(hour: 18, solarPower: 80, loadPower: 150, batteryVoltage: 13.0),
        .init(hour: 21, solarPower: 20, loadPower: 130, batteryVoltage: 12.7)
    ]
}
