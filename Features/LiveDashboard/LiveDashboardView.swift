import SwiftUI

struct LiveDashboardView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel

    var body: some View {
        ZStack {
            Theme.cockpitBackground

            ScrollView {
                VStack(spacing: 14) {
                    header
                    kpiGrid
                    confidenceCard
                    qualityCard
                }
                .padding(16)
            }
        }
        .navigationTitle("HelioPulse")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.connectionState)
                .font(.custom("AvenirNext-DemiBold", size: 18))
                .foregroundStyle(Theme.textSecondary)

            Text("\(Int(viewModel.snapshot.solarPower)) W")
                .font(.custom("AvenirNextCondensed-Bold", size: 56))
                .foregroundStyle(Theme.textPrimary)

            Text("Updated \(viewModel.lastUpdatedText)")
                .font(.custom("AvenirNext-Regular", size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var kpiGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                kpi(title: "Battery", value: String(format: "%.2fV", viewModel.snapshot.batteryVoltage), subtitle: String(format: "%.1fA", viewModel.snapshot.batteryCurrent), tint: Theme.flowCyan)
                kpi(title: "Load", value: String(format: "%.1fA", viewModel.snapshot.loadCurrent), subtitle: viewModel.snapshot.primarySource.rawValue, tint: Theme.solarAmber)
            }

            HStack(spacing: 12) {
                kpi(title: "State", value: viewModel.snapshot.chargeState.rawValue, subtitle: viewModel.snapshot.driveMode ? "Drive mode" : "Parked", tint: Theme.stateGreen)
                kpi(title: "SOC", value: "\(Int(viewModel.snapshot.modeledSOC))%", subtitle: "Confidence \(Int(viewModel.snapshot.socConfidence * 100))%", tint: Theme.warnCoral)
            }
        }
    }

    private var confidenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model confidence")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            Text(viewModel.snapshot.driveMode ? "Alternator-aware mode is active. Runtime and SOC are still shown, but confidence is reduced while charging from the engine." : "High while parked. Forecast confidence is strongest when all consumers run through the MPPT load output.")
                .font(.custom("AvenirNext-Regular", size: 14))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                Text(viewModel.snapshot.driveMode ? "Drive session detected" : "Solar-only session")
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
            Text("Signal quality")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                qualityChip(title: "Source", value: viewModel.snapshot.primarySource.rawValue, tint: Theme.flowCyan)
                qualityChip(title: "Drive", value: viewModel.snapshot.driveMode ? "On" : "Off", tint: viewModel.snapshot.driveMode ? Theme.warnCoral : Theme.stateGreen)
                qualityChip(title: "Confidence", value: "\(Int(viewModel.snapshot.socConfidence * 100))%", tint: Theme.solarAmber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func kpi(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("AvenirNext-Medium", size: 14))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.custom("AvenirNextCondensed-Bold", size: 34))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.custom("AvenirNext-Medium", size: 12))
                .foregroundStyle(Theme.textSecondary)
            RoundedRectangle(cornerRadius: 3)
                .fill(tint)
                .frame(height: 4)
                .opacity(0.9)
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
