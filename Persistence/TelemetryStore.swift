import Foundation

actor TelemetryStore {
    private(set) var snapshots: [TelemetrySnapshot] = []

    func append(_ snapshot: TelemetrySnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > 360 {
            snapshots.removeFirst(snapshots.count - 360)
        }
    }

    func latest() -> TelemetrySnapshot? {
        snapshots.last
    }

    func recent(limit: Int = 36) -> [TelemetrySnapshot] {
        Array(snapshots.suffix(limit))
    }

    func trendPoints() -> [TrendPoint] {
        snapshots.enumerated().map { index, snapshot in
            TrendPoint(
                hour: index,
                solarPower: snapshot.solarPower,
                loadPower: snapshot.loadCurrent * snapshot.batteryVoltage,
                batteryVoltage: snapshot.batteryVoltage
            )
        }
    }
}
