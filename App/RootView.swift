import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel

    var body: some View {
        TabView {
            NavigationStack {
                LiveDashboardView(viewModel: viewModel)
            }
            .tabItem {
                Label("Live", systemImage: "bolt.fill")
            }

            NavigationStack {
                TrendsView(viewModel: viewModel)
            }
            .tabItem {
                Label("Trends", systemImage: "chart.xyaxis.line")
            }

            NavigationStack {
                ForecastView(viewModel: viewModel)
            }
            .tabItem {
                Label("Forecast", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(Theme.flowCyan)
    }
}
