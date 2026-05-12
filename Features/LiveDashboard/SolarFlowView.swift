import SwiftUI

// MARK: - Private Shapes & Helpers

private struct VWBusOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let fx = w * 0.07, rx = w * 0.93
        let ry = h * 0.04, sy = h * 0.76
        let cr: CGFloat = 6

        // Start front-bottom
        p.move(to: CGPoint(x: fx + cr, y: sy))
        // Front bottom corner
        p.addQuadCurve(to: CGPoint(x: fx, y: sy - cr),
                       control: CGPoint(x: fx, y: sy))
        // Front face (nearly vertical with slight top taper)
        p.addLine(to: CGPoint(x: fx + 4, y: ry + cr * 2))
        // Front roof corner
        p.addQuadCurve(to: CGPoint(x: fx + 4 + cr, y: ry),
                       control: CGPoint(x: fx + 4, y: ry))
        // Roof (flat — characteristic T2 roofline)
        p.addLine(to: CGPoint(x: rx - 4 - cr, y: ry))
        // Rear roof corner
        p.addQuadCurve(to: CGPoint(x: rx - 4, y: ry + cr * 2),
                       control: CGPoint(x: rx - 4, y: ry))
        // Rear face
        p.addLine(to: CGPoint(x: rx, y: sy - cr))
        // Rear bottom corner
        p.addQuadCurve(to: CGPoint(x: rx - cr, y: sy),
                       control: CGPoint(x: rx, y: sy))
        // Bottom sill
        p.addLine(to: CGPoint(x: fx + cr, y: sy))
        p.closeSubpath()
        return p
    }
}

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
            // Pulsing glow halo
            Circle()
                .fill(Theme.solarAmber.opacity(0.10 * sunGlow))
                .frame(width: 110, height: 110)

            // Rotating rays via TimelineView (smooth 60fps, no @State)
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let cx = size.width / 2, cy = size.height / 2
                    let t  = tl.date.timeIntervalSinceReferenceDate * 0.35
                    for i in 0..<12 {
                        let a      = t + Double(i) * (.pi / 6)
                        let isMain = i % 3 == 0
                        let inner: Double = 29
                        let outer: Double = isMain ? 53 : 43
                        var ray = Path()
                        ray.move(to: .init(x: cx + inner * cos(a), y: cy + inner * sin(a)))
                        ray.addLine(to: .init(x: cx + outer * cos(a), y: cy + outer * sin(a)))
                        ctx.stroke(ray,
                                   with: .color(Theme.solarAmber.opacity(isMain ? 0.95 : 0.45)),
                                   style: .init(lineWidth: isMain ? 2.5 : 1.5, lineCap: .round))
                    }
                }
                .frame(width: 110, height: 110)
            }

            // Sun core
            Circle()
                .fill(RadialGradient(
                    colors: [.white, Theme.solarAmber, Theme.solarAmber.opacity(0.6)],
                    center: .center, startRadius: 0, endRadius: 26))
                .frame(width: 52, height: 52)
                .shadow(color: Theme.solarAmber.opacity(0.85), radius: 14)

            // Watt value on sun
            VStack(spacing: -1) {
                Text("\(Int(snapshot.solarPower))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                Text("W")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.bgDeep)
        }
        .frame(height: 112)
    }

    // MARK: VW Bus (T2 Bulli)

    private var busSection: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let wheelR: CGFloat = 14
            let wheelY  = h * 0.86
            let winTop  = h * 0.12
            let winH    = h * 0.28
            let darkFill = Color(red: 0.09, green: 0.11, blue: 0.17)

            ZStack {
                // 1. Wheels behind body
                wheelView(cx: w * 0.21, cy: wheelY, r: wheelR, fill: darkFill)
                wheelView(cx: w * 0.75, cy: wheelY, r: wheelR, fill: darkFill)

                // 2. Body fill — T2 Bulli midnight blue
                VWBusOutline()
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.25, blue: 0.46),
                            Color(red: 0.08, green: 0.13, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))

                // 3. Body stroke (cyan → amber glow)
                VWBusOutline()
                    .stroke(LinearGradient(
                        colors: [Theme.flowCyan.opacity(0.55), Theme.solarAmber.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                            lineWidth: 1.5)

                // 4. VW T2 windows
                //    Split windscreen (2 panes at front-left)
                winView(lx: w * 0.10, ty: winTop, ww: w * 0.07, wh: winH)
                winView(lx: w * 0.18, ty: winTop, ww: w * 0.07, wh: winH)
                //    Front side window
                winView(lx: w * 0.30, ty: winTop, ww: w * 0.15, wh: winH)
                //    Rear side window
                winView(lx: w * 0.50, ty: winTop, ww: w * 0.17, wh: winH)
                //    Rear window
                winView(lx: w * 0.83, ty: winTop, ww: w * 0.09, wh: winH)

                // 5. Battery display — lower half of cabin
                VStack(spacing: 5) {
                    BatteryIndicator(level: snapshot.modeledSOC / 100)
                        .frame(width: 54, height: 20)
                    HStack(spacing: 10) {
                        Text("\(Int(snapshot.modeledSOC))%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(socColor)
                        Text(String(format: "%.1fV", snapshot.batteryVoltage))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.flowCyan)
                    }
                }
                .position(x: w * 0.50, y: h * 0.55)
            }
        }
        .frame(height: 108)
    }

    // MARK: Load (consumer)

    private var loadSection: some View {
        VStack(spacing: 8) {
            Label("Verbraucher", systemImage: "plug.fill")
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

    @ViewBuilder
    private func wheelView(cx: CGFloat, cy: CGFloat, r: CGFloat, fill: Color) -> some View {
        ZStack {
            Circle()
                .fill(fill)
                .overlay(Circle().stroke(Theme.textSecondary.opacity(0.45), lineWidth: 1.5))
            Circle()
                .fill(Theme.textSecondary.opacity(0.3))
                .frame(width: r * 0.55, height: r * 0.55)
        }
        .frame(width: r * 2, height: r * 2)
        .position(x: cx, y: cy)
    }

    @ViewBuilder
    private func winView(lx: CGFloat, ty: CGFloat, ww: CGFloat, wh: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Theme.flowCyan.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(Theme.flowCyan.opacity(0.4), lineWidth: 0.8)
            )
            .frame(width: ww, height: wh)
            .position(x: lx + ww / 2, y: ty + wh / 2)
    }
}
