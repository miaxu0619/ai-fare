import AppKit
import SwiftUI

@main
struct AIFareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AI Fare", systemImage: "gauge.with.dots.needle.67percent") {
            Button("退出 AI Fare") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
