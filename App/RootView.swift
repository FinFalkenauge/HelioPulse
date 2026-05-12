import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: HelioPulseDashboardViewModel
    @State private var selectedTab = 0
    @State private var forecastTransitionID = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LiveDashboardView(viewModel: viewModel)
            }
            .tag(0)
            .tabItem {
                Label("Live", systemImage: "bolt.fill")
            }

            NavigationStack {
                TrendsView(viewModel: viewModel)
            }
            .tag(1)
            .tabItem {
                Label("Verläufe", systemImage: "chart.xyaxis.line")
            }

            NavigationStack {
                ForecastView(viewModel: viewModel, transitionID: forecastTransitionID)
            }
            .tag(2)
            .tabItem {
                Label("Prognose", systemImage: "clock.arrow.circlepath")
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 2 {
                forecastTransitionID = UUID()
            }
        }
        .tint(Theme.flowCyan)
    }
}
