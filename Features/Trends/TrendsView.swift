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
                            y: .value("Batterie (skaliert)", scaledBatteryY(point.batteryVoltage))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.stateGreen)
                        .lineStyle(.init(lineWidth: 2.0, dash: [2, 2]))
                    }
                }
                .chartYScale(domain: 0...maxPowerForAxis)

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
                if showBattery {
                    AxisMarks(position: .trailing, values: batteryAxisTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            .foregroundStyle(Theme.stateGreen.opacity(0.2))
                        AxisTick()
                        AxisValueLabel {
                            if let scaled = value.as(Double.self) {
                                Text(String(format: "%.1fV", voltageFromScaledY(scaled)))
                            }
                        }
                    }
                }
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

    private var maxPowerForAxis: Double {
        let solarMax = viewModel.trendPoints.map(\.solarPower).max() ?? 0
        let loadMax = viewModel.trendPoints.map(\.loadPower).max() ?? 0
        let peak = max(solarMax, loadMax)
        return max(120, peak * 1.15)
    }

    private var batteryRange: (min: Double, max: Double) {
        let values = viewModel.trendPoints.map(\.batteryVoltage)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return (11.8, 14.4)
        }

        if abs(maxValue - minValue) < 0.1 {
            return (minValue - 0.3, maxValue + 0.3)
        }

        let padding = max(0.05, (maxValue - minValue) * 0.15)
        return (minValue - padding, maxValue + padding)
    }

    private var batteryAxisTicks: [Double] {
        let steps = 4.0
        let step = maxPowerForAxis / steps
        return stride(from: 0.0, through: maxPowerForAxis, by: step).map { $0 }
    }

    private func scaledBatteryY(_ voltage: Double) -> Double {
        let range = batteryRange
        let span = max(0.001, range.max - range.min)
        let normalized = (voltage - range.min) / span
        return max(0, min(maxPowerForAxis, normalized * maxPowerForAxis))
    }

    private func voltageFromScaledY(_ scaledY: Double) -> Double {
        let range = batteryRange
        let normalized = max(0, min(1, scaledY / maxPowerForAxis))
        return range.min + normalized * (range.max - range.min)
    }
}
