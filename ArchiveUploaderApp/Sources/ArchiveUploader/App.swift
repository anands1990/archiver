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

    func applicationWillTerminate(_ notification: Notification) {
        // The sidecar is a child process spawned by this app; leaving it behind
        // would hold port 8765 (and ~2GB of model weights) after relaunch.
        Task { @MainActor in
            SidecarProcess.shared.stop()
        }
    }
}
