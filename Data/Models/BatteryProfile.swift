import Foundation

enum BatteryProfile: String, CaseIterable, Codable, Hashable {
    case custom
    case lifepo4VictronSmart100
    case lifepo4VictronSmart200
    case lifepo4Generic100
    case lifepo4Generic150
    case lifepo4Generic200
    case lifepo4Generic280
    case lifepo4Generic300
    case agmGeneric95
    case agmGeneric100
    case agmGeneric115
    case agmGeneric120
    case agmGeneric140
    case agmGeneric200
    case gelGeneric90
    case gelGeneric100
    case gelGeneric120

    var localizedName: String {
        switch self {
        case .custom: return "Eigene Batterie"
        case .lifepo4VictronSmart100: return "Victron LiFePO4 Smart 100Ah"
        case .lifepo4VictronSmart200: return "Victron LiFePO4 Smart 200Ah"
        case .lifepo4Generic100: return "LiFePO4 100Ah"
        case .lifepo4Generic150: return "LiFePO4 150Ah"
        case .lifepo4Generic200: return "LiFePO4 200Ah"
        case .lifepo4Generic280: return "LiFePO4 280Ah"
        case .lifepo4Generic300: return "LiFePO4 300Ah"
        case .agmGeneric95: return "AGM 95Ah"
        case .agmGeneric100: return "AGM 100Ah"
        case .agmGeneric115: return "AGM 115Ah"
        case .agmGeneric120: return "AGM 120Ah"
        case .agmGeneric140: return "AGM 140Ah"
        case .agmGeneric200: return "AGM 200Ah"
        case .gelGeneric90: return "Gel 90Ah"
        case .gelGeneric100: return "Gel 100Ah"
        case .gelGeneric120: return "Gel 120Ah"
        }
    }

    var chemistry: BatteryChemistry {
        switch self {
        case .custom:
            return .unknown
        case .lifepo4VictronSmart100,
             .lifepo4VictronSmart200,
             .lifepo4Generic100,
             .lifepo4Generic150,
             .lifepo4Generic200,
             .lifepo4Generic280,
             .lifepo4Generic300:
            return .lifepo4
        case .agmGeneric95,
             .agmGeneric100,
             .agmGeneric115,
             .agmGeneric120,
             .agmGeneric140,
             .agmGeneric200:
            return .agm
        case .gelGeneric90, .gelGeneric100, .gelGeneric120:
            return .gel
        }
    }

    var capacityAh: Double? {
        switch self {
        case .custom: return nil
        case .lifepo4VictronSmart100: return 100
        case .lifepo4VictronSmart200: return 200
        case .lifepo4Generic100: return 100
        case .lifepo4Generic150: return 150
        case .lifepo4Generic200: return 200
        case .lifepo4Generic280: return 280
        case .lifepo4Generic300: return 300
        case .agmGeneric95: return 95
        case .agmGeneric100: return 100
        case .agmGeneric115: return 115
        case .agmGeneric120: return 120
        case .agmGeneric140: return 140
        case .agmGeneric200: return 200
        case .gelGeneric90: return 90
        case .gelGeneric100: return 100
        case .gelGeneric120: return 120
        }
    }
}
