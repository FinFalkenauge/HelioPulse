import SwiftUI

struct LiveDashboardView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCapacityPrompt = false
    @State private var customCapacityInput = ""

    var body: some View {
        ZStack {
            Theme.cockpitBackground

            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    heroCard
                    LiveEnergyTopologyView(snapshot: viewModel.snapshot, batteryChemistry: viewModel.batteryChemistry)
                    if viewModel.hasLiveData {
                        confidenceCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        qualityCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        waitingCard
                            .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.hasLiveData)
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
                        ForEach([60, 80, 90, 100, 105, 110, 115, 120, 140, 150, 160, 180, 200, 230, 280, 300], id: \.self) { ah in
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

                        Button {
                            customCapacityInput = String(Int(viewModel.batteryCapacityAh.rounded()))
                            showCapacityPrompt = true
                        } label: {
                            Text("Eigene Ah eingeben …")
                        }
                    }
                } label: {
                    Label("Batterie", systemImage: "battery.100")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.flowCyan)
                }
            }
        }
        .alert("Eigene Batteriekapazität", isPresented: $showCapacityPrompt) {
            TextField("Ah", text: $customCapacityInput)
                .keyboardType(.numberPad)

            Button("Abbrechen", role: .cancel) {
                customCapacityInput = ""
            }

            Button("Übernehmen") {
                let normalized = customCapacityInput
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let ah = Double(normalized), ah > 0 {
                    viewModel.setBatteryCapacityAh(ah)
                }
                customCapacityInput = ""
            }
        } message: {
            Text("Beliebigen Wert zwischen 20 und 600 Ah eingeben")
        }
    }

    private var connectionCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(viewModel.isConnected ? Theme.stateGreen : Theme.warnCoral)
                .frame(width: 10, height: 10)
                .shadow(color: (viewModel.isConnected ? Theme.stateGreen : Theme.warnCoral).opacity(0.8), radius: 4)
                .scaleEffect(reduceMotion ? 1.0 : 1.15)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verbindung")
        .accessibilityValue(viewModel.connectionState)
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Theme.flowCyan)
                Text("Warte auf Live-Telemetrie")
                    .font(.custom("AvenirNext-DemiBold", size: 16))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Sobald der Victron-Controller verbunden ist, erscheinen echte Solar-, Batterie- und Verbrauchsdaten.")
                .font(.custom("AvenirNext-Regular", size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warte auf Live-Telemetrie")
    }

    private var heroCard: some View {
        let yieldText = viewModel.todayYieldWh > 0 ? String(format: "%.0f Wh", viewModel.todayYieldWh) : "–"
        let batteryText = "\(Int(viewModel.snapshot.modeledSOC))%"

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Heute im Fokus")
                        .font(.custom("AvenirNext-Medium", size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Ertrag und Ladezustand")
                        .font(.custom("AvenirNext-DemiBold", size: 18))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text(viewModel.hasLiveData ? viewModel.lastUpdatedText : "Noch keine Live-Daten")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 12) {
                heroMetric(
                    title: "Ertrag heute",
                    value: yieldText,
                    detail: "Solarertrag seit Tagesbeginn",
                    tint: Theme.solarAmber,
                    icon: "sun.max.fill"
                )

                heroMetric(
                    title: "Ladezustand",
                    value: batteryText,
                    detail: viewModel.batteryChemistry.localizedName,
                    tint: Theme.stateGreen,
                    icon: "battery.100"
                )
            }

            HStack(spacing: 10) {
                Label(viewModel.snapshot.chargeState.localizedName, systemImage: "bolt.fill")
                Text(String(format: "%.1fV", viewModel.snapshot.batteryVoltage))
                Text(viewModel.snapshot.driveMode ? "Fahrtmodus" : "Standmodus")
            }
            .font(.custom("AvenirNext-Medium", size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ertrag und Ladezustand")
        .accessibilityValue("Ertrag heute \(yieldText), Ladezustand \(batteryText), \(viewModel.snapshot.chargeState.localizedName), \(String(format: "%.1f Volt", viewModel.snapshot.batteryVoltage))")
    }

    private func heroMetric(title: String, value: String, detail: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.custom("AvenirNext-Medium", size: 12))
            }
            .foregroundStyle(tint)

            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 24))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.22), value: value)

            Text(detail)
                .font(.custom("AvenirNext-Regular", size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                )
        )
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Systemstatus")
    }

    private var qualityCard: some View {
        let columns = [
            GridItem(.flexible(minimum: 110), spacing: 10),
            GridItem(.flexible(minimum: 110), spacing: 10)
        ]

        return VStack(alignment: .leading, spacing: 10) {
            Text("Systemstatus")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                qualityChip(title: "Quelle", value: viewModel.snapshot.primarySource.localizedName, tint: Theme.flowCyan)
                qualityChip(title: "Fahrt", value: viewModel.snapshot.driveMode ? "Ja" : "Nein", tint: viewModel.snapshot.driveMode ? Theme.warnCoral : Theme.stateGreen)
                qualityChip(title: "Zustand", value: viewModel.snapshot.chargeState.localizedName, tint: Theme.stateGreen)
                qualityChip(title: "Konfidenz", value: "\(Int(viewModel.snapshot.socConfidence * 100))%", tint: Theme.solarAmber)
                qualityChip(title: "Ertrag heute", value: viewModel.todayYieldWh > 0 ? String(format: "%.0f Wh", viewModel.todayYieldWh) : "–", tint: Theme.solarAmber)
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
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: value)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
