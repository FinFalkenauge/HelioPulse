import Charts
import SwiftUI

struct TrendsView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel

    var body: some View {
        ZStack {
            Theme.cockpitBackground

            ScrollView {
                VStack(spacing: 14) {
                    chartCard
                    summaryCard
                    legendCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("24h power flow")
                .font(.custom("AvenirNext-DemiBold", size: 18))
                .foregroundStyle(Theme.textPrimary)

            Chart(viewModel.trendPoints) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Solar", point.solarPower)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.solarAmber)

                AreaMark(
                    x: .value("Hour", point.hour),
                    y: .value("Solar", point.solarPower)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.solarAmber.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Load", point.loadPower)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.flowCyan)
                .lineStyle(.init(lineWidth: 2.2, dash: [6, 3]))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 240)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            statCard(title: "SOC", value: "\(Int(viewModel.snapshot.modeledSOC))%", tint: Theme.warnCoral)
            statCard(title: "Battery", value: String(format: "%.2fV", viewModel.snapshot.batteryVoltage), tint: Theme.stateGreen)
            statCard(title: "Source", value: viewModel.snapshot.primarySource.rawValue, tint: Theme.flowCyan)
        }
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you are seeing")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                label(color: Theme.solarAmber, text: "Solar Input")
                label(color: Theme.flowCyan, text: "Load")
                label(color: Theme.stateGreen, text: "Battery")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("AvenirNext-Medium", size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func label(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.custom("AvenirNext-Medium", size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
