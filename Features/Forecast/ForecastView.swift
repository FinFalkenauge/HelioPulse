import SwiftUI

struct ForecastView: View {
    private let scenarios = ForecastScenario.mock

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgDeep, Theme.bgRaised, Theme.bgDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    runtimeHero
                    scenarioList
                }
                .padding(16)
            }
        }
        .navigationTitle("Forecast")
    }

    private var runtimeHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated runtime")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textSecondary)

            Text("17 h 40 m")
                .font(.custom("AvenirNextCondensed-Bold", size: 52))
                .foregroundStyle(Theme.textPrimary)

            Text("Confidence: medium during drive mode")
                .font(.custom("AvenirNext-Medium", size: 13))
                .foregroundStyle(Theme.flowCyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var scenarioList: some View {
        VStack(spacing: 10) {
            ForEach(scenarios) { scenario in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.name)
                            .font(.custom("AvenirNext-DemiBold", size: 15))
                            .foregroundStyle(Theme.textPrimary)
                        Text(scenario.description)
                            .font(.custom("AvenirNext-Regular", size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    Text(scenario.runtime)
                        .font(.custom("AvenirNextCondensed-Bold", size: 26))
                        .foregroundStyle(scenario.tint)
                }
                .glassCard()
            }
        }
    }
}
