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
    @Published private(set) var batteryChemistry: BatteryChemistry = .unknown

    private let service: BluetoothTelemetryService
    private let store = TelemetryStore()
    private var streamTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let batteryChemistryKey = "heliopulse.batteryChemistry"

    init(service: BluetoothTelemetryService = VictronBluetoothTelemetryService()) {
        self.service = service
        self.isUsingMockData = service.isMockDataEnabled
        if let raw = defaults.string(forKey: batteryChemistryKey),
           let chemistry = BatteryChemistry(rawValue: raw) {
            self.batteryChemistry = chemistry
        }
        self.service.onConnectionStateText = { [weak self] text in
            Task { @MainActor in
                self?.connectionState = text
                self?.isConnected = text == "Bluetooth: Verbunden"
            }
        }
    }

    func start() {
        streamTask?.cancel()
        connectionState = isUsingMockData ? "Bluetooth: Demo-Modus aktiv" : "Bluetooth: Suche nach Victron Regler …"
        isConnected = false
        forecastScenarios = Self.forecast(for: snapshot)
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
        self.snapshot = calibratedSnapshot(from: snapshot)
        self.hasLiveData = true
        self.connectionState = isUsingMockData ? "Bluetooth: Demo-Modus aktiv" : "Bluetooth: Verbunden"
        self.isConnected = !isUsingMockData
        self.lastUpdatedText = Self.relativeTimestamp(from: self.snapshot.timestamp)
        await store.append(self.snapshot)
        self.trendPoints = await store.trendPoints(limit: 24)
        self.forecastScenarios = Self.forecast(for: self.snapshot)
    }

    func setBatteryChemistry(_ chemistry: BatteryChemistry) {
        batteryChemistry = chemistry
        defaults.set(chemistry.rawValue, forKey: batteryChemistryKey)

        if hasLiveData {
            snapshot = calibratedSnapshot(from: snapshot)
            forecastScenarios = Self.forecast(for: snapshot)
        }
    }

    private func calibratedSnapshot(from source: TelemetrySnapshot) -> TelemetrySnapshot {
        var modeledSOC = source.modeledSOC
        var socConfidence = source.socConfidence

        let currentMagnitude = abs(source.batteryCurrent)
        let isResting = currentMagnitude < 0.8 && source.solarPower < 20 && source.loadCurrent < 0.8

        if let typedSoc = batteryChemistry.estimateSOC(voltage: source.batteryVoltage) {
            modeledSOC = typedSoc
            socConfidence = isResting ? 0.82 : 0.58
        } else {
            socConfidence = min(socConfidence, isResting ? 0.5 : 0.35)
        }

        return TelemetrySnapshot(
            id: source.id,
            timestamp: source.timestamp,
            solarPower: source.solarPower,
            solarVoltage: source.solarVoltage,
            solarCurrent: source.solarCurrent,
            batteryVoltage: source.batteryVoltage,
            batteryCurrent: source.batteryCurrent,
            loadCurrent: source.loadCurrent,
            chargeState: source.chargeState,
            modeledSOC: max(0, min(100, modeledSOC)),
            socConfidence: max(0, min(1, socConfidence)),
            driveMode: source.driveMode,
            primarySource: source.primarySource
        )
    }

    private static func forecast(for snapshot: TelemetrySnapshot) -> [ForecastScenario] {
        let modus = snapshot.driveMode ? "Fahrtmodus" : "Geparkt"
        let baseHours = runtimeHours(for: snapshot)

        let pessimistic = scenarioRuntime(baseHours: baseHours, factor: 0.72)
        let realistic = scenarioRuntime(baseHours: baseHours, factor: 1.0)
        let optimistic = scenarioRuntime(baseHours: baseHours, factor: 1.35)

        return [
            ForecastScenario(name: "Pessimistisch", description: "Bewölkt und hoher Verbrauch · \(modus)", runtime: pessimistic, confidence: confidenceLabel(for: 0.35, snapshot: snapshot), tint: Theme.warnCoral),
            ForecastScenario(name: "Realistisch", description: "Durchschnittliches Profil · \(modus)", runtime: realistic, confidence: confidenceLabel(for: snapshot.socConfidence, snapshot: snapshot), tint: Theme.flowCyan),
            ForecastScenario(name: "Optimistisch", description: "Starke Sonne, geringer Verbrauch · \(modus)", runtime: optimistic, confidence: confidenceLabel(for: 0.88, snapshot: snapshot), tint: Theme.stateGreen)
        ]
    }

    private static func runtimeHours(for snapshot: TelemetrySnapshot) -> Double {
        let nominalBatteryWh = max(600.0, snapshot.batteryVoltage * 100.0)
        let remainingWh = nominalBatteryWh * max(0, min(1, snapshot.modeledSOC / 100.0))

        let loadPower = max(1.0, snapshot.loadCurrent * snapshot.batteryVoltage)
        let solarContribution = max(0, snapshot.solarPower)

        let netDischargePower: Double
        if solarContribution >= loadPower {
            netDischargePower = 1.0
        } else {
            netDischargePower = max(1.0, loadPower - solarContribution)
        }

        let hours = remainingWh / netDischargePower
        if snapshot.driveMode {
            return max(1.0, hours * 0.85)
        }
        return max(0.5, hours)
    }

    private static func scenarioRuntime(baseHours: Double, factor: Double) -> String {
        let hours = baseHours * factor
        if hours >= 72 {
            return "72h+"
        }
        return String(format: "%.1fh", hours)
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
