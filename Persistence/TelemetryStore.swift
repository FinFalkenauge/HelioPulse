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

    func trendPoints(limit: Int = 24) -> [TrendPoint] {
        let recentSnapshots = Array(snapshots.suffix(max(2, limit)))
        guard !recentSnapshots.isEmpty else { return [] }

        let calendar = Calendar.current
        var points = recentSnapshots.map { snapshot in
            TrendPoint(
                hour: calendar.component(.hour, from: snapshot.timestamp),
                solarPower: snapshot.solarPower,
                loadPower: snapshot.loadCurrent * snapshot.batteryVoltage,
                batteryVoltage: snapshot.batteryVoltage
            )
        }

        if points.count == 1, let only = points.first {
            let duplicated = TrendPoint(
                hour: (only.hour + 23) % 24,
                solarPower: only.solarPower,
                loadPower: only.loadPower,
                batteryVoltage: only.batteryVoltage
            )
            points.insert(duplicated, at: 0)
        }

        return points
    }
}
