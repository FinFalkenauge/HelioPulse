import Foundation

struct TelemetrySnapshot {
    let solarPower: Double
    let batteryVoltage: Double
    let loadCurrent: Double
    let chargeState: String
    let modeledSOC: Double
}

struct TrendPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let solarPower: Double
}

extension TelemetrySnapshot {
    static let mock = TelemetrySnapshot(
        solarPower: 182,
        batteryVoltage: 13.42,
        loadCurrent: 4.6,
        chargeState: "Absorption",
        modeledSOC: 78
    )

    static let mockTrend: [TrendPoint] = [
        .init(hour: 0, solarPower: 10),
        .init(hour: 3, solarPower: 0),
        .init(hour: 6, solarPower: 45),
        .init(hour: 9, solarPower: 180),
        .init(hour: 12, solarPower: 260),
        .init(hour: 15, solarPower: 210),
        .init(hour: 18, solarPower: 80),
        .init(hour: 21, solarPower: 20),
    ]
}
