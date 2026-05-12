import SwiftUI

struct ForecastScenario: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let runtime: String
    let tint: Color
}

extension ForecastScenario {
    static let mock: [ForecastScenario] = [
        .init(name: "Conservative", description: "Cloud cover and higher load", runtime: "12h", tint: Theme.warnCoral),
        .init(name: "Realistic", description: "Expected average profile", runtime: "17h", tint: Theme.flowCyan),
        .init(name: "Optimistic", description: "Strong sun and lower load", runtime: "23h", tint: Theme.stateGreen),
    ]
}
