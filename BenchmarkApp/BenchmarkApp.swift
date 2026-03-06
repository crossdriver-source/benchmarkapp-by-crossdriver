import SwiftUI
import AppKit

@main
struct BenchmarkAppApp: App {
    private var defaultWindowHeight: CGFloat {
        NSScreen.main?.frame.height ?? 860
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1180, minHeight: 780)
        }
        .windowResizability(.automatic)
        .defaultSize(width: 1280, height: defaultWindowHeight)
    }
}
