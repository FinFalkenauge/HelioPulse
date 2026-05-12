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
}
