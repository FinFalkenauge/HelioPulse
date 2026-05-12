import Foundation
import Observation

@MainActor
final class HelioPulseDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: TelemetrySnapshot = .mock
    @Published private(set) var trendPoints: [TrendPoint] = TelemetrySnapshot.mockTrend
    @Published private(set) var forecastScenarios: [ForecastScenario] = ForecastScenario.mock
    @Published private(set) var connectionState: String = "Scanning"
    @Published private(set) var lastUpdatedText: String = "Just now"

    private let service: BluetoothTelemetryService
    private let store = TelemetryStore()
    private var streamTask: Task<Void, Never>?

    init(service: BluetoothTelemetryService = VictronBluetoothTelemetryService()) {
        self.service = service
    }

    func start() {
        streamTask?.cancel()
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
        self.connectionState = snapshot.driveMode ? "Drive mode" : "Solar live"
        self.lastUpdatedText = Self.relativeTimestamp(from: snapshot.timestamp)
        await store.append(snapshot)
        self.trendPoints = await store.trendPoints()
        self.forecastScenarios = Self.forecast(for: snapshot)
    }

    private static func forecast(for snapshot: TelemetrySnapshot) -> [ForecastScenario] {
        let confidenceSuffix = snapshot.driveMode ? "drive-aware" : "parked"
        return [
            ForecastScenario(name: "Conservative", description: "Cloud cover and higher load · \(confidenceSuffix)", runtime: driveAdjusted(hours: 12, snapshot: snapshot), confidence: confidenceLabel(for: 0.35, snapshot: snapshot), tint: Theme.warnCoral),
            ForecastScenario(name: "Realistic", description: "Expected average profile · \(confidenceSuffix)", runtime: driveAdjusted(hours: 17, snapshot: snapshot), confidence: confidenceLabel(for: snapshot.socConfidence, snapshot: snapshot), tint: Theme.flowCyan),
            ForecastScenario(name: "Optimistic", description: "Strong sun and lower load · \(confidenceSuffix)", runtime: driveAdjusted(hours: 23, snapshot: snapshot), confidence: confidenceLabel(for: 0.88, snapshot: snapshot), tint: Theme.stateGreen)
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
            return "Low"
        case 0.45..<0.75:
            return "Medium"
        default:
            return "High"
        }
    }

    private static func relativeTimestamp(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
