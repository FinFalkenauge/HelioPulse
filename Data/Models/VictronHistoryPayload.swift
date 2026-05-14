import Foundation

struct VictronHistoryPayload: Codable, Equatable {
    let todayYieldRaw: Int?
    let yesterdayYieldRaw: Int?
    let maxTodayPowerW: Int?
    let maxYesterdayPowerW: Int?
    let daysSinceLastFullCharge: Int?

    var isEmpty: Bool {
        todayYieldRaw == nil && yesterdayYieldRaw == nil && maxTodayPowerW == nil && maxYesterdayPowerW == nil && daysSinceLastFullCharge == nil
    }

    var todayYieldWh: Double? {
        todayYieldRaw.map(Self.normalizedYieldWh(from:))
    }

    private static func normalizedYieldWh(from raw: Int) -> Double {
        let asCentiKWhWh = Double(raw) * 10.0
        if asCentiKWhWh <= 30_000 {
            return asCentiKWhWh
        }
        return Double(raw)
    }
}
