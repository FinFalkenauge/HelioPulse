import Foundation

enum BatteryChemistry: String, CaseIterable, Codable, Hashable {
    case unknown
    case lifepo4
    case agm
    case gel

    var localizedName: String {
        switch self {
        case .unknown: return "Unbekannt"
        case .lifepo4: return "LiFePO4"
        case .agm: return "AGM"
        case .gel: return "Gel"
        }
    }

    func estimateSOC(voltage: Double) -> Double? {
        guard voltage > 0 else { return nil }

        switch self {
        case .unknown:
            return nil
        case .lifepo4:
            return interpolate(voltage: voltage, points: [
                (13.60, 100),
                (13.40, 99),
                (13.30, 95),
                (13.20, 80),
                (13.10, 65),
                (13.00, 40),
                (12.90, 20),
                (12.80, 12),
                (12.60, 5),
                (12.00, 0)
            ])
        case .agm:
            return interpolate(voltage: voltage, points: [
                (12.90, 100),
                (12.80, 90),
                (12.70, 80),
                (12.60, 70),
                (12.50, 60),
                (12.40, 50),
                (12.30, 40),
                (12.20, 30),
                (12.10, 20),
                (12.00, 10),
                (11.80, 0)
            ])
        case .gel:
            return interpolate(voltage: voltage, points: [
                (12.85, 100),
                (12.75, 90),
                (12.65, 80),
                (12.55, 70),
                (12.45, 60),
                (12.35, 50),
                (12.25, 40),
                (12.15, 30),
                (12.05, 20),
                (11.95, 10),
                (11.75, 0)
            ])
        }
    }

    private func interpolate(voltage: Double, points: [(v: Double, soc: Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }

        if voltage >= first.v { return first.soc }
        if voltage <= last.v { return last.soc }

        for index in 0..<(points.count - 1) {
            let high = points[index]
            let low = points[index + 1]
            if voltage <= high.v && voltage >= low.v {
                let ratio = (voltage - low.v) / (high.v - low.v)
                let soc = low.soc + ratio * (high.soc - low.soc)
                return max(0, min(100, soc))
            }
        }

        return 0
    }
}
