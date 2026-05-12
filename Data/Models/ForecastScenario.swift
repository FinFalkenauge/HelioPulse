import SwiftUI

struct ForecastScenario: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let runtime: String
    let confidence: String
    let tint: Color
}

extension ForecastScenario {
    static let mock: [ForecastScenario] = [
        .init(name: "Pessimistisch", description: "Bewölkt und hoher Verbrauch", runtime: "12h", confidence: "Niedrig", tint: Theme.warnCoral),
        .init(name: "Realistisch", description: "Durchschnittliches Profil", runtime: "17h", confidence: "Mittel", tint: Theme.flowCyan),
        .init(name: "Optimistisch", description: "Starke Sonne, geringer Verbrauch", runtime: "23h", confidence: "Hoch", tint: Theme.stateGreen)
    ]
}
