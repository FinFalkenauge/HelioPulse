import SwiftUI
import Charts

struct ForecastView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel
    let transitionID: UUID
    @State private var transitionProgress = 0.0

    var body: some View {
        ZStack {
            Theme.cockpitBackground

            ScrollView {
                VStack(spacing: 14) {
                    flowTransitionChart
                    runtimeHero
                    scenarioList
                }
                .padding(16)
            }
        }
        .navigationTitle("Prognose")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startTransitionAnimation()
        }
        .onChange(of: transitionID) { _, _ in
            startTransitionAnimation()
        }
    }

    private var flowTransitionChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Übergang Verlauf → Prognose")
                .font(.custom("AvenirNext-DemiBold", size: 17))
                .foregroundStyle(Theme.textPrimary)

            Text("Zeitachse fließt nach vorne, Prognose übernimmt nahtlos")
                .font(.custom("AvenirNext-Regular", size: 12))
                .foregroundStyle(Theme.textSecondary)

            Chart(flowSeries) { point in
                if point.kind == .solar {
                    LineMark(
                        x: .value("Zeit", point.date),
                        y: .value("Solar", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(point.isForecast ? Theme.solarAmber.opacity(0.65) : Theme.solarAmber)
                    .lineStyle(.init(lineWidth: point.isForecast ? 2 : 2.6, dash: point.isForecast ? [5, 4] : []))
                }

                if point.kind == .load {
                    LineMark(
                        x: .value("Zeit", point.date),
                        y: .value("Last", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(point.isForecast ? Theme.flowCyan.opacity(0.65) : Theme.flowCyan)
                    .lineStyle(.init(lineWidth: point.isForecast ? 2 : 2.6, dash: point.isForecast ? [5, 4] : [6, 3]))
                }
            }
            .chartXScale(domain: chartDomain)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
        }
        .glassCard()
    }

    private var runtimeHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Geschätzte Laufzeit")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textSecondary)

            Text(viewModel.forecastScenarios.first?.runtime ?? "--")
                .font(.custom("AvenirNextCondensed-Bold", size: 52))
                .foregroundStyle(Theme.textPrimary)

            Text(viewModel.hasLiveData ? (viewModel.snapshot.driveMode ? "Fahrtmodus erkannt · Konfidenz reduziert" : "Geparkt · volle Konfidenz") : "Warte auf Live-Telemetrie")
                .font(.custom("AvenirNext-Medium", size: 13))
                .foregroundStyle(Theme.flowCyan)

            Text(viewModel.forecastContextText)
                .font(.custom("AvenirNext-Regular", size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var scenarioList: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.forecastScenarios) { scenario in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.name)
                            .font(.custom("AvenirNext-DemiBold", size: 15))
                            .foregroundStyle(Theme.textPrimary)
                        Text(scenario.description)
                            .font(.custom("AvenirNext-Regular", size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Konfidenz: \(scenario.confidence)")
                            .font(.custom("AvenirNext-Medium", size: 12))
                            .foregroundStyle(scenario.tint)
                    }

                    Spacer()

                    Text(scenario.runtime)
                        .font(.custom("AvenirNextCondensed-Bold", size: 26))
                        .foregroundStyle(scenario.tint)
                }
                .glassCard()
            }

            if viewModel.forecastScenarios.isEmpty {
                Text("Noch keine Prognose verfügbar. Verbinde den Victron-Controller für echte Daten.")
                    .font(.custom("AvenirNext-Regular", size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            }
        }
    }

    private var chartDomain: ClosedRange<Date> {
        let now = Date()
        let start = now.addingTimeInterval((-24 + (18 * transitionProgress)) * 3600)
        let end = now.addingTimeInterval((18 * transitionProgress) * 3600)
        return start...end
    }

    private var flowSeries: [ForecastFlowPoint] {
        let now = Date()
        let historical = viewModel.trendPoints.suffix(12)
        var points: [ForecastFlowPoint] = historical.flatMap { point in
            [
                ForecastFlowPoint(date: point.timestamp, value: point.solarPower, kind: .solar, isForecast: false),
                ForecastFlowPoint(date: point.timestamp, value: point.loadPower, kind: .load, isForecast: false)
            ]
        }

        let baseLoad = max(10.0, viewModel.snapshot.loadCurrent * viewModel.snapshot.batteryVoltage)
        let baseSolar = max(0.0, viewModel.snapshot.solarPower)

        for hour in 1...24 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: now) ?? now
            let hourInDay = Calendar.current.component(.hour, from: date)
            let sunProfile = max(0.0, sin((Double(hourInDay) - 6.0) / 12.0 * .pi))

            let forecastSolar = baseSolar * (0.2 + 1.15 * sunProfile)
            let forecastLoad = baseLoad * (0.92 + (viewModel.snapshot.driveMode ? 0.35 : 0.12) * (1.0 - sunProfile))

            points.append(ForecastFlowPoint(date: date, value: forecastSolar, kind: .solar, isForecast: true))
            points.append(ForecastFlowPoint(date: date, value: forecastLoad, kind: .load, isForecast: true))
        }

        return points
    }

    private func startTransitionAnimation() {
        transitionProgress = 0
        withAnimation(.easeInOut(duration: 0.85)) {
            transitionProgress = 1
        }
    }
}

private struct ForecastFlowPoint: Identifiable {
    enum Kind {
        case solar
        case load
    }

    let id = UUID()
    let date: Date
    let value: Double
    let kind: Kind
    let isForecast: Bool
}
