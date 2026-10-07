import SwiftUI

@main
struct GugudanApp: App {
    @State private var stats = StatsStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(stats)
        }
    }
}
