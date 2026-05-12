import Foundation

enum ChargeState: String, CaseIterable, Codable {
    case off = "Off"
    case bulk = "Bulk"
    case absorption = "Absorption"
    case float = "Float"
    case storage = "Storage"

    var localizedName: String {
        switch self {
        case .off:        return "Aus"
        case .bulk:       return "Bulk"
        case .absorption: return "Absorption"
        case .float:      return "Erhaltung"
        case .storage:    return "Speicher"
        }
    }
}

enum PowerSource: String, CaseIterable, Codable {
    case solar = "Solar"
    case alternator = "Alternator"
    case load = "Load"

    var localizedName: String {
        switch self {
        case .solar:       return "Solar"
        case .alternator:  return "Lichtmaschine"
        case .load:        return "Verbraucher"
        }
    }
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
    let timestamp: Date
    let solarPower: Double
    let loadPower: Double
    let batteryVoltage: Double

    init(timestamp: Date, solarPower: Double, loadPower: Double, batteryVoltage: Double) {
        self.id = UUID()
        self.timestamp = timestamp
        self.solarPower = solarPower
        self.loadPower = loadPower
        self.batteryVoltage = batteryVoltage
    }

    var hour: Int {
        Calendar.current.component(.hour, from: timestamp)
    }
}

enum TrendRange: String, CaseIterable, Identifiable, Codable {
    case day24
    case days7
    case days30
    case year
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day24: return "24h"
        case .days7: return "7T"
        case .days30: return "30T"
        case .year: return "1J"
        case .all: return "Alles"
        }
    }

    var headline: String {
        switch self {
        case .day24: return "24h Leistungsfluss"
        case .days7: return "7 Tage Verlauf"
        case .days30: return "30 Tage Verlauf"
        case .year: return "1 Jahr Verlauf"
        case .all: return "Langzeit-Verlauf"
        }
    }
}

extension TelemetrySnapshot {
    static let empty = TelemetrySnapshot(
        id: UUID(),
        timestamp: .distantPast,
        solarPower: 0,
        solarVoltage: 0,
        solarCurrent: 0,
        batteryVoltage: 0,
        batteryCurrent: 0,
        loadCurrent: 0,
        chargeState: .off,
        modeledSOC: 0,
        socConfidence: 0,
        driveMode: false,
        primarySource: .solar
    )

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
        .init(timestamp: Calendar.current.date(byAdding: .hour, value: -21, to: .now) ?? .now, solarPower: 10, loadPower: 90, batteryVoltage: 12.9),
        .init(timestamp: Calendar.current.date(byAdding: .hour, value: -18, to: .now) ?? .now, solarPower: 0, loadPower: 120, batteryVoltage: 12.5),
        .init(timestamp: Calendar.current.date(byAdding: .hour, value: -15, to: .now) ?? .now, solarPower: 45, loadPower: 140, batteryVoltage: 12.8),
        .init(timestamp: Calendar.current.date(byAdding: .hour, value: -12, to: .now) ?? .now, solarPower: 180, loadPower: 110, batteryVoltage: 13.4),
        .init(timestamp: Calendar.current.date(byAdding: .hour, value: -9, to: .now) ?? .now, solarPower: 260, loadPower: 95, batteryVoltage: 13.8),
        .init(timestamp: Calendar.current.date(byAdding: .hour, value: -6, to: .now) ?? .now, solarPower: 210, loadPower: 105, batteryVoltage: 13.7),
        .init(timestamp: Calendar.current.date(byAdding: .hour, value: -3, to: .now) ?? .now, solarPower: 80, loadPower: 150, batteryVoltage: 13.0),
        .init(timestamp: .now, solarPower: 20, loadPower: 130, batteryVoltage: 12.7)
    ]
}
