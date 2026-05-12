import SwiftUI

struct LiveDashboardView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel

    var body: some View {
        ZStack {
            Theme.cockpitBackground

            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    SolarFlowView(snapshot: viewModel.snapshot, batteryChemistry: viewModel.batteryChemistry)
                    if viewModel.hasLiveData {
                        confidenceCard
                        qualityCard
                    } else {
                        waitingCard
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("HelioPulse")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Profil") {
                        ForEach(BatteryProfile.allCases, id: \.self) { profile in
                            Button {
                                viewModel.setBatteryProfile(profile)
                            } label: {
                                if profile == viewModel.batteryProfile {
                                    Label(profile.localizedName, systemImage: "checkmark")
                                } else {
                                    Text(profile.localizedName)
                                }
                            }
                        }
                    }

                    ForEach(BatteryChemistry.allCases, id: \.self) { chemistry in
                        Button {
                            viewModel.setBatteryChemistry(chemistry)
                        } label: {
                            if chemistry == viewModel.batteryChemistry {
                                Label(chemistry.localizedName, systemImage: "checkmark")
                            } else {
                                Text(chemistry.localizedName)
                            }
                        }
                    }

                    Section("Kapazität (Ah)") {
                        ForEach([60, 80, 100, 120, 160, 200, 280], id: \.self) { ah in
                            Button {
                                viewModel.setBatteryCapacityAh(Double(ah))
                            } label: {
                                if Int(viewModel.batteryCapacityAh.rounded()) == ah {
                                    Label("\(ah) Ah", systemImage: "checkmark")
                                } else {
                                    Text("\(ah) Ah")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Batterie", systemImage: "battery.100")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.flowCyan)
                }
            }
        }
    }

    private var connectionCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(viewModel.isConnected ? Theme.stateGreen : Theme.warnCoral)
                .frame(width: 10, height: 10)
                .shadow(color: (viewModel.isConnected ? Theme.stateGreen : Theme.warnCoral).opacity(0.8), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.connectionState)
                    .font(.custom("AvenirNext-DemiBold", size: 14))
                    .foregroundStyle(Theme.textPrimary)
                Text(viewModel.isUsingMockData ? "Datenquelle: Demo" : "Datenquelle: Victron BLE")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if viewModel.hasLiveData {
                Text("Aktualisiert \(viewModel.lastUpdatedText)")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warte auf Live-Telemetrie")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)
            Text("Sobald der Victron-Controller verbunden ist, erscheinen echte Solar-, Batterie- und Verbrauchsdaten.")
                .font(.custom("AvenirNext-Regular", size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var confidenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modell-Konfidenz")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            Text(viewModel.snapshot.driveMode ? "Fahrtmodus aktiv: Lichtmaschine lädt. Laufzeit und SOC werden weiterhin angezeigt, aber die Konfidenz ist während der Fahrt reduziert." : "Hoch bei geparktem Fahrzeug. Konfidenz ist am stärksten, wenn alle Verbraucher über den MPPT-Lastausgang laufen.")
                .font(.custom("AvenirNext-Regular", size: 14))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                Text(viewModel.snapshot.driveMode ? "Fahrt erkannt" : "Nur Solar")
                    .font(.custom("AvenirNext-Medium", size: 13))
            }
            .foregroundStyle(Theme.flowCyan)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signalqualität")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                qualityChip(title: "Quelle", value: viewModel.snapshot.primarySource.localizedName, tint: Theme.flowCyan)
                qualityChip(title: "Fahrt", value: viewModel.snapshot.driveMode ? "Ja" : "Nein", tint: viewModel.snapshot.driveMode ? Theme.warnCoral : Theme.stateGreen)
                qualityChip(title: "Konfidenz", value: "\(Int(viewModel.snapshot.socConfidence * 100))%", tint: Theme.solarAmber)
                qualityChip(title: "Batterie", value: viewModel.batteryChemistry.localizedName, tint: Theme.flowCyan)
                qualityChip(title: "Ah", value: "\(Int(viewModel.batteryCapacityAh))", tint: Theme.flowCyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func qualityChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom("AvenirNext-Medium", size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 15))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.26), lineWidth: 1)
                )
        )
    }
}
