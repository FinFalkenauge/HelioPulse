import Foundation
import Observation

@MainActor
final class HelioPulseDashboardViewModel: ObservableObject {
    private static let maxForecastHours = 24 * 30

    @Published private(set) var snapshot: TelemetrySnapshot = .empty
    @Published private(set) var trendPoints: [TrendPoint] = []
    @Published private(set) var trendRange: TrendRange = .day24
    @Published private(set) var forecastScenarios: [ForecastScenario] = []
    @Published private(set) var connectionState: String = "Bluetooth: Nicht verbunden"
    @Published private(set) var lastUpdatedText: String = "-"
    @Published private(set) var hasLiveData: Bool = false
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isUsingMockData: Bool = false
    @Published private(set) var batteryChemistry: BatteryChemistry = .unknown
    @Published private(set) var batteryProfile: BatteryProfile = .custom
    @Published private(set) var batteryCapacityAh: Double = 100
    @Published private(set) var todayYieldWh: Double = 0
    @Published private(set) var forecastContextText: String = "Forecast: Nur Live-Telemetrie"

    private let service: BluetoothTelemetryService
    private let environmentService = ForecastEnvironmentService()
    private let store = TelemetryStore()
    private var streamTask: Task<Void, Never>?
    private var forecastContext: ForecastEnvironmentContext?
    private let defaults = UserDefaults.standard
    private let batteryChemistryKey = "heliopulse.batteryChemistry"
    private let batteryProfileKey = "heliopulse.batteryProfile"
    private let batteryCapacityAhKey = "heliopulse.batteryCapacityAh"
    private var lastYieldSampleTimestamp: Date?
    private var historyTodayYieldWh: Double?
    private var historyTodayYieldDayStart: Date?

    init(service: BluetoothTelemetryService = VictronBluetoothTelemetryService()) {
        self.service = service
        self.isUsingMockData = service.isMockDataEnabled
        if let raw = defaults.string(forKey: batteryChemistryKey),
           let chemistry = BatteryChemistry(rawValue: raw) {
            self.batteryChemistry = chemistry
        }
        if let raw = defaults.string(forKey: batteryProfileKey),
           let profile = BatteryProfile(rawValue: raw) {
            self.batteryProfile = profile
            if profile != .custom {
                self.batteryChemistry = profile.chemistry
                self.batteryCapacityAh = profile.capacityAh ?? 100
            }
        }
        let storedAh = defaults.double(forKey: batteryCapacityAhKey)
        if storedAh > 0 {
            self.batteryCapacityAh = storedAh
        }
        self.service.onConnectionStateText = { [weak self] text in
            Task { @MainActor in
                self?.connectionState = text
                self?.isConnected = text == "Bluetooth: Verbunden"
            }
        }

        self.service.onHistoryPayload = { [weak self] payload in
            guard let self else { return }
            Task { @MainActor in
                await self.store.importVictronHistory(payload)
                self.historyTodayYieldWh = payload.todayYieldWh
                self.historyTodayYieldDayStart = payload.todayYieldWh.map { _ in Calendar.current.startOfDay(for: .now) }
                if let todayYieldWh = self.historyTodayYieldWh {
                    self.todayYieldWh = todayYieldWh
                    self.lastYieldSampleTimestamp = nil
                }
                self.trendPoints = await self.store.trendPoints(range: self.trendRange)
            }
        }

        self.environmentService.onUpdate = { [weak self] context in
            guard let self else { return }
            self.forecastContext = context
            if context.hasWeather && context.hasTerrain {
                self.forecastContextText = String(format: "Forecast: GPS %.3f, %.3f · Wetter+Terrain aktiv", context.latitude, context.longitude)
            } else if context.hasWeather {
                self.forecastContextText = String(format: "Forecast: GPS %.3f, %.3f · Wetter aktiv", context.latitude, context.longitude)
            } else {
                self.forecastContextText = String(format: "Forecast: GPS %.3f, %.3f · Nur Sonnenverlauf", context.latitude, context.longitude)
            }
            self.forecastScenarios = self.forecast(for: self.snapshot)
        }
    }

    func start() {
        streamTask?.cancel()
        todayYieldWh = 0
        lastYieldSampleTimestamp = nil
        historyTodayYieldWh = nil
        historyTodayYieldDayStart = nil
        connectionState = isUsingMockData ? "Bluetooth: Demo-Modus aktiv" : "Bluetooth: Suche nach Victron Regler …"
        isConnected = false
        forecastScenarios = forecast(for: snapshot)
        environmentService.start()
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
        environmentService.stop()
        Task {
            await service.stopScanning()
        }
    }

    private func update(with snapshot: TelemetrySnapshot) async {
        self.snapshot = calibratedSnapshot(from: snapshot)
        updateTodayYield(with: self.snapshot)
        self.hasLiveData = true
        self.connectionState = isUsingMockData ? "Bluetooth: Demo-Modus aktiv" : "Bluetooth: Verbunden"
        self.isConnected = !isUsingMockData
        self.lastUpdatedText = Self.relativeTimestamp(from: self.snapshot.timestamp)
        await store.append(self.snapshot)
        self.trendPoints = await store.trendPoints(range: trendRange)
        self.forecastScenarios = forecast(for: self.snapshot)
    }

    func setTrendRange(_ range: TrendRange) {
        trendRange = range
        Task { @MainActor in
            self.trendPoints = await self.store.trendPoints(range: range)
        }
    }

    func setBatteryChemistry(_ chemistry: BatteryChemistry) {
        batteryChemistry = chemistry
        batteryProfile = .custom
        defaults.set(chemistry.rawValue, forKey: batteryChemistryKey)
        defaults.set(BatteryProfile.custom.rawValue, forKey: batteryProfileKey)

        if hasLiveData {
            snapshot = calibratedSnapshot(from: snapshot)
            forecastScenarios = forecast(for: snapshot)
        }
    }

    func setBatteryProfile(_ profile: BatteryProfile) {
        batteryProfile = profile
        defaults.set(profile.rawValue, forKey: batteryProfileKey)

        if profile == .custom {
            defaults.set(batteryChemistry.rawValue, forKey: batteryChemistryKey)
        } else {
            batteryChemistry = profile.chemistry
            defaults.set(profile.chemistry.rawValue, forKey: batteryChemistryKey)
            if let ah = profile.capacityAh {
                batteryCapacityAh = ah
                defaults.set(ah, forKey: batteryCapacityAhKey)
            }
        }

        if hasLiveData {
            snapshot = calibratedSnapshot(from: snapshot)
            forecastScenarios = forecast(for: snapshot)
        }
    }

    func setBatteryCapacityAh(_ ah: Double) {
        batteryCapacityAh = max(20, min(600, ah))
        batteryProfile = .custom
        defaults.set(BatteryProfile.custom.rawValue, forKey: batteryProfileKey)
        defaults.set(batteryCapacityAh, forKey: batteryCapacityAhKey)

        if hasLiveData {
            forecastScenarios = forecast(for: snapshot)
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

    private func forecast(for snapshot: TelemetrySnapshot) -> [ForecastScenario] {
        let modus = snapshot.driveMode ? "Fahrtmodus" : "Geparkt"
        let pessimistic = Self.scenarioRuntime(hours: runtimeHours(for: snapshot, loadFactor: 1.2, weatherFactor: 0.75))
        let realistic = Self.scenarioRuntime(hours: runtimeHours(for: snapshot, loadFactor: 1.0, weatherFactor: 1.0))
        let optimistic = Self.scenarioRuntime(hours: runtimeHours(for: snapshot, loadFactor: 0.88, weatherFactor: 1.18))

        return [
            ForecastScenario(name: "Pessimistisch", description: "Bewölkt und hoher Verbrauch · \(modus)", runtime: pessimistic, confidence: Self.confidenceLabel(for: 0.35, snapshot: snapshot), tint: Theme.warnCoral),
            ForecastScenario(name: "Realistisch", description: "Durchschnittliches Profil · \(modus)", runtime: realistic, confidence: Self.confidenceLabel(for: snapshot.socConfidence, snapshot: snapshot), tint: Theme.flowCyan),
            ForecastScenario(name: "Optimistisch", description: "Starke Sonne, geringer Verbrauch · \(modus)", runtime: optimistic, confidence: Self.confidenceLabel(for: 0.88, snapshot: snapshot), tint: Theme.stateGreen)
        ]
    }

    private func runtimeHours(for snapshot: TelemetrySnapshot, loadFactor: Double, weatherFactor: Double) -> Double {
        let capacityAh = batteryCapacityAh
        let batteryCapacityWh = max(800.0, snapshot.batteryVoltage * capacityAh)
        var remainingWh = batteryCapacityWh * max(0, min(1, snapshot.modeledSOC / 100.0))
        let baseLoadW = max(10.0, snapshot.loadCurrent * snapshot.batteryVoltage) * loadFactor

        let now = Date()
        let context = forecastContext

        let currentSolarW = max(0, snapshot.solarPower)
        let baseSolarPotential: Double = {
            guard let context else { return currentSolarW }
            let sunNow = SolarGeometry.elevationFactor(date: now, latitude: context.latitude, longitude: context.longitude)
            let weatherNow = hourlyWeatherFactor(at: now, context: context)
            // Weather modulates solar yield only when sun is above horizon.
            let combinedNow = max(0.05, sunNow * max(0.2, weatherNow))
            return currentSolarW / combinedNow
        }()

        for hour in 0..<Self.maxForecastHours {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: now) ?? now
            let sunFactor: Double
            let weatherEnv: Double
            var terrainShade = 1.0

            if let context {
                let sunPosition = SolarGeometry.position(date: date, latitude: context.latitude, longitude: context.longitude)
                sunFactor = sunPosition.elevationFactor
                weatherEnv = hourlyWeatherFactor(at: date, context: context)
                if let profile = context.horizonProfile {
                    terrainShade = terrainVisibilityFactor(sunPosition: sunPosition, profile: profile)
                }
            } else {
                sunFactor = 0.65
                weatherEnv = 0.65
            }

            let terrainFactor = 1.0
            // Ensure no solar production at night.
            let projected = max(0, baseSolarPotential * sunFactor * max(0.2, weatherEnv) * weatherFactor * terrainFactor * terrainShade)
            let headroomCap = max(currentSolarW * 1.25, currentSolarW + 25)
            let solarW = min(projected, headroomCap)
            let netWh = solarW - baseLoadW
            remainingWh = min(batteryCapacityWh, remainingWh + netWh)

            if remainingWh <= 0 {
                return max(0.5, Double(hour) + max(0.1, batteryCapacityWh / max(baseLoadW, 1) * 0.05))
            }
        }

        return Double(Self.maxForecastHours)
    }

    private func hourlyWeatherFactor(at date: Date, context: ForecastEnvironmentContext) -> Double {
        guard let nearest = nearestWeatherPoint(to: date, context: context) else { return 0.65 }

        let cloudPenalty = 1 - 0.7 * nearest.cloudCover
        let radiationFactor = min(1.2, nearest.shortwaveRadiation / 850.0)
        let directShare = nearest.shortwaveRadiation > 0 ? nearest.directRadiation / max(1, nearest.shortwaveRadiation) : 0
        let diffuseBoost = min(0.25, nearest.diffuseRadiation / 1200.0)

        return max(0.05, min(1.2, 0.4 * cloudPenalty + 0.45 * radiationFactor + 0.15 * directShare + diffuseBoost))
    }

    private func nearestWeatherPoint(to date: Date, context: ForecastEnvironmentContext) -> ForecastHourlyPoint? {
        context.hourly.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private func terrainVisibilityFactor(sunPosition: SolarGeometry.SolarPosition, profile: HorizonProfile) -> Double {
        if sunPosition.elevationDegrees <= 0 {
            return 0
        }

        let obstruction = profile.obstructionAngle(forAzimuth: sunPosition.azimuthDegrees)
        if sunPosition.elevationDegrees <= obstruction {
            return 0.18
        }

        let margin = sunPosition.elevationDegrees - obstruction
        if margin < 6 {
            return max(0.25, min(1.0, margin / 6.0))
        }
        return 1.0
    }

    private static func scenarioRuntime(hours: Double) -> String {
        if hours >= Double(maxForecastHours) {
            return "30T+"
        }
        if hours >= 48 {
            return String(format: "%.1fT", hours / 24.0)
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

    private func updateTodayYield(with snapshot: TelemetrySnapshot) {
        let calendar = Calendar.current

        if let historyTodayYieldWh {
            if let historyDayStart = historyTodayYieldDayStart,
               !calendar.isDate(historyDayStart, inSameDayAs: snapshot.timestamp) {
                self.historyTodayYieldWh = nil
                self.historyTodayYieldDayStart = nil
                todayYieldWh = 0
                lastYieldSampleTimestamp = nil
            } else {
                todayYieldWh = historyTodayYieldWh
                lastYieldSampleTimestamp = nil
                return
            }
        }

        if let last = lastYieldSampleTimestamp,
           !calendar.isDate(last, inSameDayAs: snapshot.timestamp) {
            todayYieldWh = 0
            lastYieldSampleTimestamp = nil
        }

        if let last = lastYieldSampleTimestamp {
            let dt = snapshot.timestamp.timeIntervalSince(last)
            if dt > 0, dt <= 600 {
                todayYieldWh += max(0, snapshot.solarPower) * (dt / 3600.0)
            }
        }

        lastYieldSampleTimestamp = snapshot.timestamp
    }
}
