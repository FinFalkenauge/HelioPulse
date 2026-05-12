import SwiftUI

struct LiveDashboardView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel
    @State private var calibrationSOC: Double = 60

    var body: some View {
        ZStack {
            Theme.cockpitBackground

            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    batterySetupCard
                    calibrationCard
                    SolarFlowView(snapshot: viewModel.snapshot)
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

    private var batterySetupCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.100")
                .foregroundStyle(Theme.solarAmber)

            VStack(alignment: .leading, spacing: 3) {
                Text("Batterietyp")
                    .font(.custom("AvenirNext-DemiBold", size: 14))
                    .foregroundStyle(Theme.textPrimary)
                Text("SOC wird damit deutlich genauer")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Menu {
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
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.batteryChemistry.localizedName)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.custom("AvenirNext-DemiBold", size: 13))
                .foregroundStyle(Theme.flowCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.flowCyan.opacity(0.14))
                )
            }
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

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOC-Feinkalibrierung")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            Text("Setze einen bekannten SOC bei aktueller Ruhe-Spannung. Die App lernt daraus einen Offset pro Batterietyp.")
                .font(.custom("AvenirNext-Regular", size: 13))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 12) {
                Text("Bekannter SOC")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Slider(value: $calibrationSOC, in: 0...100, step: 1)

                Text("\(Int(calibrationSOC))%")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 52, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Label(String(format: "%.2fV", viewModel.snapshot.batteryVoltage), systemImage: "bolt.horizontal.circle")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.flowCyan)

                if viewModel.isRestingForCalibration {
                    Label("Ruhephase", systemImage: "checkmark.seal.fill")
                        .font(.custom("AvenirNext-Medium", size: 12))
                        .foregroundStyle(Theme.stateGreen)
                } else {
                    Label("Unter Last", systemImage: "exclamationmark.triangle.fill")
                        .font(.custom("AvenirNext-Medium", size: 12))
                        .foregroundStyle(Theme.solarAmber)
                }

                Spacer()

                Text(String(format: "Offset %.1f%%", viewModel.socCalibrationOffset))
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 10) {
                Button("Kalibrieren") {
                    viewModel.applySocCalibration(knownSOC: calibrationSOC)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.flowCyan)
                .disabled(viewModel.batteryChemistry == .unknown)

                Button("Reset") {
                    viewModel.resetSocCalibration()
                }
                .buttonStyle(.bordered)
                .tint(Theme.warnCoral)
                .disabled(viewModel.batteryChemistry == .unknown)
            }

            if viewModel.batteryChemistry == .unknown {
                Text("Wahle zuerst einen Batterietyp fur die Feinkalibrierung.")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
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
