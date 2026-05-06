import SwiftUI
import AppKit

@main
struct ArchiverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var taskStore = TaskStore()

    var body: some Scene {
        MenuBarExtra("Archiver", systemImage: "book.closed.fill") {
            ContentView()
                .environment(taskStore)
                .frame(width: 380, height: 460)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
