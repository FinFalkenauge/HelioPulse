import Foundation
import Observation

@MainActor
final class HelioPulseDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: TelemetrySnapshot = .empty
    @Published private(set) var trendPoints: [TrendPoint] = []
    @Published private(set) var forecastScenarios: [ForecastScenario] = []
    @Published private(set) var connectionState: String = "Bluetooth: Nicht verbunden"
    @Published private(set) var lastUpdatedText: String = "-"
    @Published private(set) var hasLiveData: Bool = false
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isUsingMockData: Bool = false

    private let service: BluetoothTelemetryService
    private let store = TelemetryStore()
    private var streamTask: Task<Void, Never>?

    init(service: BluetoothTelemetryService = VictronBluetoothTelemetryService()) {
        self.service = service
        self.isUsingMockData = service.isMockDataEnabled
        self.service.onConnectionStateText = { [weak self] text in
            Task { @MainActor in
                self?.connectionState = text
                self?.isConnected = text.contains("Verbunden")
            }
        }
    }

    func start() {
        streamTask?.cancel()
        connectionState = isUsingMockData ? "Bluetooth: Demo-Modus aktiv" : "Bluetooth: Suche nach Victron Regler …"
        isConnected = false
        streamTask = Task {
            await service.startScanning()
            let stream = service.telemetryStream()
            for await value in stream {
                await update(with: value)
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        Task {
            await service.stopScanning()
        }
    }

    private func update(with snapshot: TelemetrySnapshot) async {
        self.snapshot = snapshot
        self.hasLiveData = true
        self.connectionState = isUsingMockData ? "Bluetooth: Demo-Modus aktiv" : "Bluetooth: Verbunden"
        self.isConnected = !isUsingMockData
        self.lastUpdatedText = Self.relativeTimestamp(from: snapshot.timestamp)
        await store.append(snapshot)
        self.trendPoints = await store.trendPoints()
        self.forecastScenarios = Self.forecast(for: snapshot)
    }

    private static func forecast(for snapshot: TelemetrySnapshot) -> [ForecastScenario] {
        let modus = snapshot.driveMode ? "Fahrtmodus" : "Geparkt"
        return [
            ForecastScenario(name: "Pessimistisch", description: "Bewölkt und hoher Verbrauch · \(modus)", runtime: driveAdjusted(hours: 12, snapshot: snapshot), confidence: confidenceLabel(for: 0.35, snapshot: snapshot), tint: Theme.warnCoral),
            ForecastScenario(name: "Realistisch", description: "Durchschnittliches Profil · \(modus)", runtime: driveAdjusted(hours: 17, snapshot: snapshot), confidence: confidenceLabel(for: snapshot.socConfidence, snapshot: snapshot), tint: Theme.flowCyan),
            ForecastScenario(name: "Optimistisch", description: "Starke Sonne, geringer Verbrauch · \(modus)", runtime: driveAdjusted(hours: 23, snapshot: snapshot), confidence: confidenceLabel(for: 0.88, snapshot: snapshot), tint: Theme.stateGreen)
        ]
    }

    private static func driveAdjusted(hours: Int, snapshot: TelemetrySnapshot) -> String {
        let adjustedHours = snapshot.driveMode ? max(1, hours - 2) : hours
        return "\(adjustedHours)h"
    }

    private static func confidenceLabel(for value: Double, snapshot: TelemetrySnapshot) -> String {
        let effective = snapshot.driveMode ? max(0.25, value - 0.2) : value
        switch effective {
        case 0..<0.45:
            return "Niedrig"
        case 0.45..<0.75:
            return "Mittel"
        default:
            return "Hoch"
        }
    }

    private static func relativeTimestamp(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
