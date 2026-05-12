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
    @Published private(set) var socCalibrationOffset: Double = 0

    private let service: BluetoothTelemetryService
    private let store = TelemetryStore()
    private var streamTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let batteryChemistryKey = "heliopulse.batteryChemistry"
    private let socCalibrationOffsetPrefix = "heliopulse.socOffset."

    init(service: BluetoothTelemetryService = VictronBluetoothTelemetryService()) {
        self.service = service
        self.isUsingMockData = service.isMockDataEnabled
        if let raw = defaults.string(forKey: batteryChemistryKey),
           let chemistry = BatteryChemistry(rawValue: raw) {
            self.batteryChemistry = chemistry
        }
        self.socCalibrationOffset = loadSocCalibrationOffset(for: batteryChemistry)
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
        self.trendPoints = await store.trendPoints()
        self.forecastScenarios = Self.forecast(for: self.snapshot)
    }

    func setBatteryChemistry(_ chemistry: BatteryChemistry) {
        batteryChemistry = chemistry
        defaults.set(chemistry.rawValue, forKey: batteryChemistryKey)
        socCalibrationOffset = loadSocCalibrationOffset(for: chemistry)

        if hasLiveData {
            snapshot = calibratedSnapshot(from: snapshot)
            forecastScenarios = Self.forecast(for: snapshot)
        }
    }

    func applySocCalibration(knownSOC: Double) {
        guard batteryChemistry != .unknown else { return }
        guard let baseSoc = batteryChemistry.estimateSOC(voltage: snapshot.batteryVoltage) else { return }

        let offset = max(-35, min(35, knownSOC - baseSoc))
        socCalibrationOffset = offset
        saveSocCalibrationOffset(offset, for: batteryChemistry)

        if hasLiveData {
            snapshot = calibratedSnapshot(from: snapshot)
            forecastScenarios = Self.forecast(for: snapshot)
        }
    }

    func resetSocCalibration() {
        socCalibrationOffset = 0
        saveSocCalibrationOffset(0, for: batteryChemistry)

        if hasLiveData {
            snapshot = calibratedSnapshot(from: snapshot)
            forecastScenarios = Self.forecast(for: snapshot)
        }
    }

    var isRestingForCalibration: Bool {
        let currentMagnitude = abs(snapshot.batteryCurrent)
        return currentMagnitude < 0.8 && snapshot.solarPower < 20 && snapshot.loadCurrent < 0.8
    }

    private func calibratedSnapshot(from source: TelemetrySnapshot) -> TelemetrySnapshot {
        var modeledSOC = source.modeledSOC
        var socConfidence = source.socConfidence

        let currentMagnitude = abs(source.batteryCurrent)
        let isResting = currentMagnitude < 0.8 && source.solarPower < 20 && source.loadCurrent < 0.8

        if let typedSoc = batteryChemistry.estimateSOC(voltage: source.batteryVoltage) {
            modeledSOC = typedSoc + socCalibrationOffset
            let calibrationBonus = abs(socCalibrationOffset) <= 5 ? 0.05 : 0.02
            socConfidence = isResting ? 0.84 + calibrationBonus : 0.62
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

    private func socCalibrationOffsetKey(for chemistry: BatteryChemistry) -> String {
        socCalibrationOffsetPrefix + chemistry.rawValue
    }

    private func loadSocCalibrationOffset(for chemistry: BatteryChemistry) -> Double {
        defaults.double(forKey: socCalibrationOffsetKey(for: chemistry))
    }

    private func saveSocCalibrationOffset(_ offset: Double, for chemistry: BatteryChemistry) {
        defaults.set(offset, forKey: socCalibrationOffsetKey(for: chemistry))
    }
}
