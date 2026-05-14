import SwiftUI

private struct MiniBatteryBar: View {
    let level: Double

    private var fillColor: Color {
        level > 0.5 ? Theme.stateGreen : level > 0.25 ? Theme.solarAmber : Theme.warnCoral
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.textSecondary.opacity(0.45), lineWidth: 1.3)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fillColor)
                    .padding(2.2)
                    .frame(width: max(6, (geo.size.width - 4.4) * level + 4.4))
            }
        }
    }
}

struct LiveEnergyTopologyView: View {
    let snapshot: TelemetrySnapshot
    let batteryChemistry: BatteryChemistry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var loadWatts: Double { snapshot.loadCurrent * snapshot.batteryVoltage }
    private var solarActive: Bool { snapshot.solarPower > 3 }
    private var loadActive: Bool { loadWatts > 1 }
    private var estimatedSOC: Bool { snapshot.socConfidence < 0.7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.bgRaised.opacity(0.98), Theme.cardGlass],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 12)

                VStack(spacing: 14) {
                    sunNode

                    flowConnector(color: Theme.solarAmber, active: solarActive)

                    busNode

                    flowConnector(color: Theme.flowCyan, active: solarActive || loadActive)

                    HStack(alignment: .top, spacing: 12) {
                        batteryNode
                        consumerNode
                    }
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Energiefluss")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("Sonne, Bus, Batterie und Verbraucher")
                    .font(.custom("AvenirNext-DemiBold", size: 18))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusPill(text: solarActive ? "Solar aktiv" : "Solar ruhig", tint: solarActive ? Theme.solarAmber : Theme.textSecondary)
                statusPill(text: loadActive ? "Verbrauch aktiv" : "Verbrauch gering", tint: loadActive ? Theme.flowCyan : Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energiefluss")
        .accessibilityValue("Sonne \(Int(snapshot.solarPower)) Watt, Batterie \(Int(snapshot.modeledSOC)) Prozent, Verbraucher \(Int(loadWatts)) Watt")
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.custom("AvenirNext-Medium", size: 11))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    )
            )
    }

    private var sunNode: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Sonne", systemImage: "sun.max.fill")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(Theme.solarAmber)
                Spacer()
                Text(solarActive ? "liefert" : "wartet")
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.solarAmber.opacity(0.16))
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(RadialGradient(
                            colors: [.white, Theme.solarAmber, Theme.solarAmber.opacity(0.65)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 24
                        ))
                        .frame(width: 40, height: 40)
                        .shadow(color: Theme.solarAmber.opacity(0.55), radius: 10)
                    VStack(spacing: -1) {
                        Text("\(Int(snapshot.solarPower))")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.bgDeep)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: snapshot.solarPower)
                        Text("W")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.bgDeep)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Erzeugung")
                        .font(.custom("AvenirNext-Medium", size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text(String(format: "%.0f W", snapshot.solarPower))
                        .font(.custom("AvenirNext-DemiBold", size: 21))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: snapshot.solarPower)
                    Text("Momentane Leistung")
                        .font(.custom("AvenirNext-Regular", size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.solarAmber.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.solarAmber.opacity(0.20), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sonne")
        .accessibilityValue("\(Int(snapshot.solarPower)) Watt")
    }

    private var busNode: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Energiefluss", systemImage: "bolt.horizontal")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(Theme.flowCyan)
                Spacer()
                Text(snapshot.driveMode ? "Fahrtmodus" : "Stand")
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            CamperEnergyFlowDiagram(
                solarActive: solarActive,
                loadActive: loadActive,
                solarPower: snapshot.solarPower,
                batterySOC: snapshot.modeledSOC
            )
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.flowCyan.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.flowCyan.opacity(0.18), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Energiefluss")
        .accessibilityValue(solarActive ? "Solar aktiv, " : "" + (loadActive ? "Verbrauch aktiv" : "Verbrauch gering"))
    }

    private var batteryNode: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Batterie", systemImage: "battery.100")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(Theme.stateGreen)
                Spacer()
                Text(batteryChemistry.localizedName)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            MiniBatteryBar(level: snapshot.modeledSOC / 100)
                .frame(height: 18)
                .opacity(estimatedSOC ? 0.75 : 1)

            Text(estimatedSOC ? "~\(Int(snapshot.modeledSOC))%" : "\(Int(snapshot.modeledSOC))%")
                .font(.custom("AvenirNext-DemiBold", size: 22))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: snapshot.modeledSOC)

            Text(String(format: "%.1f V", snapshot.batteryVoltage))
                .font(.custom("AvenirNext-Medium", size: 12))
                .foregroundStyle(Theme.flowCyan)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: snapshot.batteryVoltage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.stateGreen.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.stateGreen.opacity(0.20), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Batterie")
        .accessibilityValue("\(Int(snapshot.modeledSOC)) Prozent, \(String(format: "%.1f Volt", snapshot.batteryVoltage))")
    }

    private var consumerNode: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Verbraucher", systemImage: "bolt.fill")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(Theme.flowCyan)
                Spacer()
                Text(loadActive ? "zieht" : "ruhig")
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f W", loadWatts))
                    .font(.custom("AvenirNext-DemiBold", size: 22))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: loadWatts)
                Text("Lastleistung")
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f A", snapshot.loadCurrent))
                    .font(.custom("AvenirNext-DemiBold", size: 18))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: snapshot.loadCurrent)
                Text("Strom")
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.flowCyan.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.flowCyan.opacity(0.20), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verbraucher")
        .accessibilityValue("\(Int(loadWatts)) Watt, \(String(format: "%.1f Ampere", snapshot.loadCurrent))")
    }

    private func flowConnector(color: Color, active: Bool) -> some View {
        HStack(spacing: 8) {
            Capsule(style: .continuous)
                .fill(color.opacity(active ? 0.70 : 0.22))
                .frame(width: 2, height: 24)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color.opacity(active ? 0.92 : 0.35))
            Capsule(style: .continuous)
                .fill(color.opacity(active ? 0.70 : 0.22))
                .frame(width: 2, height: 24)
        }
        .accessibilityHidden(true)
        .opacity(reduceMotion ? 0.55 : 1.0)
    }
}

private struct CamperEnergyFlowDiagram: View {
    let solarActive: Bool
    let loadActive: Bool
    let solarPower: Double
    let batterySOC: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var flowArrowColor: Color {
        if solarActive && !loadActive {
            return Theme.stateGreen
        } else if loadActive && !solarActive {
            return Theme.warnCoral
        } else if solarActive && loadActive {
            return Theme.solarAmber
        }
        return Theme.textSecondary.opacity(0.4)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            solarPanelNode
                .frame(height: 68)

            flowArrowDown
                .frame(height: 24)

            busNode
                .frame(height: 56)

            flowArrowDown
                .frame(height: 24)

            HStack(alignment: .center, spacing: 20) {
                batteryNode
                    .frame(maxWidth: .infinity)
                consumerNode
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 68)
        }
    }

    private var solarPanelNode: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.solarAmber.opacity(0.16))
                    .frame(width: 48, height: 48)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.14, green: 0.35, blue: 0.72), Color(red: 0.08, green: 0.22, blue: 0.48)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .overlay {
                        VStack(spacing: 1) {
                            HStack(spacing: 1) {
                                ForEach(0..<2, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 4, height: 4)
                                }
                            }
                            HStack(spacing: 1) {
                                ForEach(0..<2, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 4, height: 4)
                                }
                            }
                        }
                    }
            }

            Text("Solar")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var busNode: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.flowCyan.opacity(0.24), Theme.flowCyan.opacity(0.08)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 28
                ))
                .frame(width: 56, height: 56)

            Circle()
                .fill(Theme.flowCyan.opacity(0.18))
                .stroke(Theme.flowCyan.opacity(0.40), lineWidth: 1.5)
                .frame(width: 40, height: 40)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.flowCyan)
        }
    }

    private var batteryNode: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.stateGreen.opacity(0.5), lineWidth: 1.2)
                    .frame(width: 36, height: 22)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.stateGreen)
                    .padding(2)
                    .frame(width: max(6, 32 * batterySOC / 100), alignment: .leading)

                Rectangle()
                    .fill(Theme.stateGreen.opacity(0.3))
                    .frame(width: 2, height: 8)
                    .offset(x: 18)
            }

            Text("Akku")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var consumerNode: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .frame(width: 36, height: 22)

                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        Circle()
                            .fill(Color.white.opacity(0.32))
                            .frame(width: 3, height: 3)
                        Circle()
                            .fill(Color.white.opacity(0.32))
                            .frame(width: 3, height: 3)
                    }
                    HStack(spacing: 1) {
                        Circle()
                            .fill(Color.white.opacity(0.32))
                            .frame(width: 3, height: 3)
                        Circle()
                            .fill(Color.white.opacity(0.32))
                            .frame(width: 3, height: 3)
                    }
                }
            }

            Text("Verbraucher")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var flowArrowDown: some View {
        VStack(spacing: 2) {
            Capsule(style: .continuous)
                .fill(flowArrowColor.opacity(0.4))
                .frame(width: 1.2, height: 12)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(flowArrowColor)
        }
        .opacity(solarActive || loadActive ? 1.0 : 0.5)
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
            value: solarActive || loadActive
        )
    }
}
