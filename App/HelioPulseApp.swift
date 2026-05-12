import SwiftUI

@main
struct HelioPulseApp: App {
    @StateObject private var dashboard = HelioPulseDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: dashboard)
                .preferredColorScheme(.dark)
                .task {
                    dashboard.start()
                }
        }
    }
}
