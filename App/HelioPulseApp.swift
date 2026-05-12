import SwiftUI

@main
struct HelioPulseApp: App {
    @StateObject private var dashboard = HelioPulseDashboardViewModel()
    @State private var didStartTelemetry = false

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: dashboard)
                .preferredColorScheme(.dark)
                .task {
                    guard !didStartTelemetry else { return }
                    didStartTelemetry = true
                    // Let SwiftUI render the first frame before initializing BLE.
                    try? await Task.sleep(for: .milliseconds(450))
                    dashboard.start()
                }
        }
    }
}
