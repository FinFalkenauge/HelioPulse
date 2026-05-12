import SwiftUI

struct ForecastView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel

    var body: some View {
        ZStack {
            Theme.cockpitBackground

            ScrollView {
                VStack(spacing: 14) {
                    runtimeHero
                    scenarioList
                }
                .padding(16)
            }
        }
        .navigationTitle("Prognose")
        .navigationBarTitleDisplayMode(.inline)
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
}
