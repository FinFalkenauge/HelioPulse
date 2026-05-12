import SwiftUI

struct LiveDashboardView: View {
    private let snapshot = TelemetrySnapshot.mock

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
                    header
                    kpiGrid
                    confidenceCard
                }
                .padding(16)
            }
        }
        .navigationTitle("HelioPulse")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Cockpit")
                .font(.custom("AvenirNext-DemiBold", size: 18))
                .foregroundStyle(Theme.textSecondary)

            Text("\(Int(snapshot.solarPower)) W")
                .font(.custom("AvenirNextCondensed-Bold", size: 56))
                .foregroundStyle(Theme.textPrimary)

            Text("Solar input power")
                .font(.custom("AvenirNext-Regular", size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var kpiGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                kpi(title: "Battery", value: String(format: "%.2fV", snapshot.batteryVoltage), tint: Theme.flowCyan)
                kpi(title: "Load", value: String(format: "%.1fA", snapshot.loadCurrent), tint: Theme.solarAmber)
            }

            HStack(spacing: 12) {
                kpi(title: "State", value: snapshot.chargeState, tint: Theme.stateGreen)
                kpi(title: "SOC", value: "\(Int(snapshot.modeledSOC))%", tint: Theme.warnCoral)
            }
        }
    }

    private var confidenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model confidence")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            Text("High while parked. During drive sessions with alternator charging, forecast confidence is reduced automatically.")
                .font(.custom("AvenirNext-Regular", size: 14))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                Text("Alternator-aware mode")
                    .font(.custom("AvenirNext-Medium", size: 13))
            }
            .foregroundStyle(Theme.flowCyan)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func kpi(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("AvenirNext-Medium", size: 14))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.custom("AvenirNextCondensed-Bold", size: 34))
                .foregroundStyle(Theme.textPrimary)
            RoundedRectangle(cornerRadius: 3)
                .fill(tint)
                .frame(height: 4)
                .opacity(0.9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
