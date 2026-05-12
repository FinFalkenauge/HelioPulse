import Charts
import SwiftUI

struct TrendsView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel
    @State private var showSolar = true
    @State private var showLoad = true
    @State private var showBattery = false

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
        .navigationTitle("Verläufe")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.trendRange.headline)
                .font(.custom("AvenirNext-DemiBold", size: 18))
                .foregroundStyle(Theme.textPrimary)

            Picker("Zeitraum", selection: Binding(
                get: { viewModel.trendRange },
                set: { viewModel.setTrendRange($0) }
            )) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                metricToggle(title: "Solar", color: Theme.solarAmber, isOn: $showSolar)
                metricToggle(title: "Last", color: Theme.flowCyan, isOn: $showLoad)
                metricToggle(title: "Batterie", color: Theme.stateGreen, isOn: $showBattery)
            }

            ZStack {
                Chart(viewModel.trendPoints) { point in
                    if showSolar {
                        LineMark(
                            x: .value("Zeit", point.timestamp),
                            y: .value("Solar", point.solarPower)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.solarAmber)

                        AreaMark(
                            x: .value("Zeit", point.timestamp),
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

                    if showLoad {
                        LineMark(
                            x: .value("Zeit", point.timestamp),
                            y: .value("Last", point.loadPower)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.flowCyan)
                        .lineStyle(.init(lineWidth: 2.2, dash: [6, 3]))
                    }

                    if showBattery {
                        LineMark(
                            x: .value("Zeit", point.timestamp),
                            y: .value("Batterie", point.batteryVoltage * 25.0)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.stateGreen)
                        .lineStyle(.init(lineWidth: 2.0, dash: [2, 2]))
                    }
                }

                if viewModel.trendPoints.count < 3 {
                    Text("Sammle Verlaufspunkte …")
                        .font(.custom("AvenirNext-Medium", size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.35))
                        )
                }
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
            statCard(title: "Batterie", value: String(format: "%.2fV", viewModel.snapshot.batteryVoltage), tint: Theme.stateGreen)
            statCard(title: "Quelle", value: viewModel.snapshot.primarySource.localizedName, tint: Theme.flowCyan)
        }
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Legende")
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                label(color: Theme.solarAmber, text: "Solareingang")
                label(color: Theme.flowCyan, text: "Verbrauch")
                label(color: Theme.stateGreen, text: "Batterie")
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

    private func metricToggle(title: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.custom("AvenirNext-Medium", size: 12))
            }
            .foregroundStyle(isOn.wrappedValue ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn.wrappedValue ? color.opacity(0.2) : Color.white.opacity(0.06))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isOn.wrappedValue ? color.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
