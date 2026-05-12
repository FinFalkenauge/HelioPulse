import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                LiveDashboardView()
            }
            .tabItem {
                Label("Live", systemImage: "bolt.fill")
            }

            NavigationStack {
                TrendsView()
            }
            .tabItem {
                Label("Trends", systemImage: "chart.xyaxis.line")
            }

            NavigationStack {
                ForecastView()
            }
            .tabItem {
                Label("Forecast", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(Theme.flowCyan)
    }
}
