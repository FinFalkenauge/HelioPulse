import SwiftUI

// MARK: - Private Shapes & Helpers

private struct BatteryIndicator: View {
    let level: Double
    private var barColor: Color {
        level > 0.5 ? Theme.stateGreen : level > 0.25 ? Theme.solarAmber : Theme.warnCoral
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.textSecondary.opacity(0.5), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .padding(2.5)
                    .frame(width: max(6, (geo.size.width - 5) * level + 5))
            }
        }
    }
}

private struct FlowLine: View {
    let active: Bool
    let color: Color
    @State private var phase: CGFloat = 0
    private let dash: CGFloat = 8, gap: CGFloat = 6

    var body: some View {
        Canvas { ctx, size in
            let cx   = size.width / 2
            let step = dash + gap
            let off  = active ? phase.truncatingRemainder(dividingBy: step) : 0
            var y    = -step + off

            while y < size.height {
                let s = max(0, y), e = min(size.height, y + dash)
                if e > s {
                    var ln = Path()
                    ln.move(to: .init(x: cx, y: s))
                    ln.addLine(to: .init(x: cx, y: e))
                    ctx.stroke(ln,
                               with: .color(color.opacity(active ? 0.88 : 0.2)),
                               style: .init(lineWidth: 3, lineCap: .round))
                }
                y += step
            }
            if active {
                var arr = Path()
                arr.move(to: .init(x: cx - 6, y: size.height - 12))
                arr.addLine(to: .init(x: cx,     y: size.height - 3))
                arr.addLine(to: .init(x: cx + 6, y: size.height - 12))
                ctx.stroke(arr,
                           with: .color(color.opacity(0.9)),
                           style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 40)
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                phase = dash + gap
            }
        }
    }
}

// MARK: - SolarFlowView

struct SolarFlowView: View {
    let snapshot: TelemetrySnapshot
    let batteryChemistry: BatteryChemistry
    @State private var sunGlow: CGFloat = 1.0

    private var loadWatts: Double { snapshot.loadCurrent * snapshot.batteryVoltage }
    private var solarOn: Bool { snapshot.solarPower > 3 }
    private var loadOn: Bool  { loadWatts > 1 }

    var body: some View {
        VStack(spacing: 0) {
            sunSection
            FlowLine(active: solarOn, color: Theme.solarAmber)
            busSection
            FlowLine(active: loadOn, color: Theme.warnCoral)
            loadSection
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.cardGlass)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.solarAmber.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: Theme.solarAmber.opacity(0.08), radius: 18, y: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                sunGlow = 1.6
            }
        }
    }

    // MARK: Sun

    private var sunSection: some View {
        ZStack {
            sunGlowHalo
            sunRays
            sunCore
            sunPowerLabel
        }
        .frame(height: 112)
    }

    private var sunGlowHalo: some View {
        Circle()
            .fill(Theme.solarAmber.opacity(0.10 * sunGlow))
            .frame(width: 110, height: 110)
    }

    private var sunRays: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                drawSunRays(in: ctx, size: size, date: tl.date)
            }
            .frame(width: 110, height: 110)
        }
    }

    private var sunCore: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white, Theme.solarAmber, Theme.solarAmber.opacity(0.6)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 26
                )
            )
            .frame(width: 52, height: 52)
            .shadow(color: Theme.solarAmber.opacity(0.85), radius: 14)
    }

    private var sunPowerLabel: some View {
        VStack(spacing: -1) {
            Text("\(Int(snapshot.solarPower))")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: snapshot.solarPower)

            Text("W")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.bgDeep)
    }

    private func drawSunRays(in ctx: GraphicsContext, size: CGSize, date: Date) {
        let cx = size.width / 2
        let cy = size.height / 2
        let t = date.timeIntervalSinceReferenceDate * 0.35

        for i in 0..<12 {
            let a = t + Double(i) * (.pi / 6)
            let isMain = i.isMultiple(of: 3)
            let inner: Double = 29
            let outer: Double = isMain ? 53 : 43

            var ray = Path()
            ray.move(to: CGPoint(x: cx + inner * cos(a), y: cy + inner * sin(a)))
            ray.addLine(to: CGPoint(x: cx + outer * cos(a), y: cy + outer * sin(a)))

            ctx.stroke(
                ray,
                with: .color(Theme.solarAmber.opacity(isMain ? 0.95 : 0.45)),
                style: .init(lineWidth: isMain ? 2.5 : 1.5, lineCap: .round)
            )
        }
    }

    // MARK: VW Bus (T2 Bulli)

    private var busSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )

            VStack(spacing: 6) {
                VWBus3DView()

                HStack(spacing: 10) {
                    BatteryIndicator(level: snapshot.modeledSOC / 100)
                        .frame(width: 58, height: 18)
                        .opacity(isSocEstimated ? 0.55 : 1)
                    Text(socText)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(isSocEstimated ? Theme.textSecondary : socColor)
                    Text(String(format: "%.1fV", snapshot.batteryVoltage))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.flowCyan)
                }

                if showSocHint {
                    Text(socHintText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(height: 126)
    }

    // MARK: Load (consumer)

    private var loadSection: some View {
        VStack(spacing: 8) {
            Label("Verbraucher", systemImage: "bolt.fill")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text(String(format: "%.0f W", loadWatts))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.warnCoral)
                    Text("Leistung")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                Rectangle()
                    .fill(Theme.textSecondary.opacity(0.25))
                    .frame(width: 1, height: 36)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f A", snapshot.loadCurrent))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.warnCoral)
                    Text("Strom")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.warnCoral.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.warnCoral.opacity(0.28), lineWidth: 1)
                    }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    private var socColor: Color {
        snapshot.modeledSOC > 60 ? Theme.stateGreen
            : snapshot.modeledSOC > 25 ? Theme.solarAmber
            : Theme.warnCoral
    }

    private var isSocEstimated: Bool {
        snapshot.socConfidence < 0.7
    }

    private var socText: String {
        if isSocEstimated {
            return "~\(Int(snapshot.modeledSOC))%"
        }
        return "\(Int(snapshot.modeledSOC))%"
    }

    private var showSocHint: Bool {
        batteryChemistry == .unknown || snapshot.socConfidence < 0.7
    }

    private var socHintText: String {
        if batteryChemistry == .unknown {
            return "Batterietyp wählen für bessere SOC-Schätzung"
        }
        if snapshot.socConfidence < 0.7 {
            return "SOC aus Spannung + Profil (unter Last ungenauer)"
        }
        return "SOC aus Spannung + Profil"
    }

}
