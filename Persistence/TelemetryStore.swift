import Foundation

actor TelemetryStore {
    private struct DailyAggregate: Codable {
        let dayStart: Date
        var sampleCount: Int
        var solarSum: Double
        var loadSum: Double
        var voltageSum: Double
    }

    private struct PersistedHistory: Codable {
        let snapshots: [TelemetrySnapshot]
        let dailyAggregates: [DailyAggregate]
    }

    private(set) var snapshots: [TelemetrySnapshot] = []
    private var dailyAggregates: [DailyAggregate] = []
    private var appendCountSinceSave = 0
    private let maxSnapshots = 1_440
    private let maxDailyAggregates = 4_000
    private let saveInterval = 24
    private let calendar = Calendar.current
    private let historyURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("HelioPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        historyURL = dir.appendingPathComponent("telemetry-history.json")
        loadHistory()
    }

    func append(_ snapshot: TelemetrySnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }

        appendToDailyAggregate(snapshot)
        appendCountSinceSave += 1
        if appendCountSinceSave >= saveInterval {
            saveHistory()
            appendCountSinceSave = 0
        }
    }

    func latest() -> TelemetrySnapshot? {
        snapshots.last
    }

    func recent(limit: Int = 36) -> [TelemetrySnapshot] {
        Array(snapshots.suffix(limit))
    }

    func trendPoints(range: TrendRange = .day24) -> [TrendPoint] {
        switch range {
        case .day24:
            return hourlyPointsForLast24h()
        case .days7:
            return dailyPoints(lastDays: 7)
        case .days30:
            return dailyPoints(lastDays: 30)
        case .year:
            return dailyPoints(lastDays: 365)
        case .all:
            return dailyPoints(lastDays: nil)
        }
    }

    func importVictronHistory(_ payload: VictronHistoryPayload, referenceDate: Date = .now) {
        let today = calendar.startOfDay(for: referenceDate)
        if let todayRaw = payload.todayYieldRaw {
            upsertHistoryDay(
                dayStart: today,
                yieldRaw: todayRaw,
                maxPowerW: payload.maxTodayPowerW
            )
        }

        if let yesterdayRaw = payload.yesterdayYieldRaw,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            upsertHistoryDay(
                dayStart: yesterday,
                yieldRaw: yesterdayRaw,
                maxPowerW: payload.maxYesterdayPowerW
            )
        }

        dailyAggregates.sort(by: { $0.dayStart < $1.dayStart })
        if dailyAggregates.count > maxDailyAggregates {
            dailyAggregates.removeFirst(dailyAggregates.count - maxDailyAggregates)
        }
        saveHistory()
    }

    private func hourlyPointsForLast24h() -> [TrendPoint] {
        let start = Date().addingTimeInterval(-24 * 3600)
        let filtered = snapshots.filter { $0.timestamp >= start }
        guard !filtered.isEmpty else { return [] }

        var buckets: [Date: DailyAggregate] = [:]
        for snapshot in filtered {
            let hourStart = calendar.dateInterval(of: .hour, for: snapshot.timestamp)?.start ?? snapshot.timestamp
            var aggregate = buckets[hourStart] ?? DailyAggregate(dayStart: hourStart, sampleCount: 0, solarSum: 0, loadSum: 0, voltageSum: 0)
            aggregate.sampleCount += 1
            aggregate.solarSum += snapshot.solarPower
            aggregate.loadSum += snapshot.loadCurrent * snapshot.batteryVoltage
            aggregate.voltageSum += snapshot.batteryVoltage
            buckets[hourStart] = aggregate
        }

        return buckets.keys.sorted().compactMap { hourStart in
            guard let agg = buckets[hourStart], agg.sampleCount > 0 else { return nil }
            let c = Double(agg.sampleCount)
            return TrendPoint(
                timestamp: hourStart,
                solarPower: agg.solarSum / c,
                loadPower: agg.loadSum / c,
                batteryVoltage: agg.voltageSum / c
            )
        }
    }

    private func dailyPoints(lastDays: Int?) -> [TrendPoint] {
        let cutoff: Date? = {
            guard let lastDays else { return nil }
            return calendar.date(byAdding: .day, value: -lastDays + 1, to: calendar.startOfDay(for: .now))
        }()

        let selected = dailyAggregates.filter { aggregate in
            guard let cutoff else { return true }
            return aggregate.dayStart >= cutoff
        }

        return selected.sorted(by: { $0.dayStart < $1.dayStart }).compactMap { agg in
            guard agg.sampleCount > 0 else { return nil }
            let c = Double(agg.sampleCount)
            return TrendPoint(
                timestamp: agg.dayStart,
                solarPower: agg.solarSum / c,
                loadPower: agg.loadSum / c,
                batteryVoltage: agg.voltageSum / c
            )
        }
    }

    private func appendToDailyAggregate(_ snapshot: TelemetrySnapshot) {
        let dayStart = calendar.startOfDay(for: snapshot.timestamp)
        if let lastIndex = dailyAggregates.indices.last, dailyAggregates[lastIndex].dayStart == dayStart {
            dailyAggregates[lastIndex].sampleCount += 1
            dailyAggregates[lastIndex].solarSum += snapshot.solarPower
            dailyAggregates[lastIndex].loadSum += snapshot.loadCurrent * snapshot.batteryVoltage
            dailyAggregates[lastIndex].voltageSum += snapshot.batteryVoltage
        } else {
            dailyAggregates.append(
                DailyAggregate(
                    dayStart: dayStart,
                    sampleCount: 1,
                    solarSum: snapshot.solarPower,
                    loadSum: snapshot.loadCurrent * snapshot.batteryVoltage,
                    voltageSum: snapshot.batteryVoltage
                )
            )
            if dailyAggregates.count > maxDailyAggregates {
                dailyAggregates.removeFirst(dailyAggregates.count - maxDailyAggregates)
            }
        }
    }

    private func upsertHistoryDay(dayStart: Date, yieldRaw: Int, maxPowerW: Int?) {
        let yieldWh = normalizedYieldWh(from: yieldRaw)
        let avgSolarW = max(0, yieldWh / 24.0)
        let representativeSolarW = max(avgSolarW, Double(maxPowerW ?? 0) * 0.25)

        if let idx = dailyAggregates.firstIndex(where: { calendar.isDate($0.dayStart, inSameDayAs: dayStart) }) {
            var existing = dailyAggregates[idx]
            if existing.sampleCount <= 1 {
                existing.sampleCount = 1
                existing.solarSum = representativeSolarW
                dailyAggregates[idx] = existing
            }
            return
        }

        dailyAggregates.append(
            DailyAggregate(
                dayStart: dayStart,
                sampleCount: 1,
                solarSum: representativeSolarW,
                loadSum: 0,
                voltageSum: snapshots.last?.batteryVoltage ?? 12.6
            )
        )
    }

    private func normalizedYieldWh(from raw: Int) -> Double {
        let asCentiKWhWh = Double(raw) * 10.0
        if asCentiKWhWh <= 30_000 {
            return asCentiKWhWh
        }
        return Double(raw)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        guard let persisted = try? JSONDecoder().decode(PersistedHistory.self, from: data) else { return }
        snapshots = persisted.snapshots
        dailyAggregates = persisted.dailyAggregates.sorted(by: { $0.dayStart < $1.dayStart })
    }

    private func saveHistory() {
        let persisted = PersistedHistory(snapshots: snapshots, dailyAggregates: dailyAggregates)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}
