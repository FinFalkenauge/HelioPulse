import Foundation

actor TelemetryStore {
    private(set) var snapshots: [TelemetrySnapshot] = []

    func append(_ snapshot: TelemetrySnapshot) {
        snapshots.append(snapshot)
    }

    func latest() -> TelemetrySnapshot? {
        snapshots.last
    }
}
