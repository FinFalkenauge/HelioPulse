import Foundation

enum BatteryProfile: String, CaseIterable, Codable, Hashable {
    case custom
    case lifepo4VictronSmart100
    case lifepo4VictronSmart200
    case lifepo4Generic280
    case agmGeneric95
    case agmGeneric120
    case gelGeneric90

    var localizedName: String {
        switch self {
        case .custom: return "Custom"
        case .lifepo4VictronSmart100: return "Victron LiFePO4 Smart 100Ah"
        case .lifepo4VictronSmart200: return "Victron LiFePO4 Smart 200Ah"
        case .lifepo4Generic280: return "LiFePO4 280Ah"
        case .agmGeneric95: return "AGM 95Ah"
        case .agmGeneric120: return "AGM 120Ah"
        case .gelGeneric90: return "Gel 90Ah"
        }
    }

    var chemistry: BatteryChemistry {
        switch self {
        case .custom:
            return .unknown
        case .lifepo4VictronSmart100, .lifepo4VictronSmart200, .lifepo4Generic280:
            return .lifepo4
        case .agmGeneric95, .agmGeneric120:
            return .agm
        case .gelGeneric90:
            return .gel
        }
    }

    var capacityAh: Double? {
        switch self {
        case .custom: return nil
        case .lifepo4VictronSmart100: return 100
        case .lifepo4VictronSmart200: return 200
        case .lifepo4Generic280: return 280
        case .agmGeneric95: return 95
        case .agmGeneric120: return 120
        case .gelGeneric90: return 90
        }
    }
}
