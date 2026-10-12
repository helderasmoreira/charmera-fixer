import SwiftUI

@main
struct CharmeraFixerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Charmera Fixer", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Folder…", action: model.chooseSource)
                    .keyboardShortcut("o")
                    .disabled(model.phase == .processing)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
