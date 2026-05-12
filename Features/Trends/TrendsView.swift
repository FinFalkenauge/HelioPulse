import Charts
import SwiftUI

struct TrendsView: View {
    private let points = TelemetrySnapshot.mockTrend

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgDeep, Theme.bgRaised],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    chartCard
                    legendCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Trends")
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("24h power flow")
                .font(.custom("AvenirNext-DemiBold", size: 18))
                .foregroundStyle(Theme.textPrimary)

            Chart(points) { point in
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
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 240)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var legendCard: some View {
        HStack(spacing: 12) {
            label(color: Theme.solarAmber, text: "Solar Input")
            label(color: Theme.flowCyan, text: "Battery Flow")
            label(color: Theme.stateGreen, text: "Load")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
