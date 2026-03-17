import SwiftUI
import AppKit
import Sparkle

// MARK: - Sparkle Update Support

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app is recognized as a regular GUI application
        // (needed when running as a bare executable, not a .app bundle)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  let chars = event.charactersIgnoringModifiers else { return event }

            let action: Selector? = switch chars {
            case "v": #selector(NSText.paste(_:))
            case "c": #selector(NSText.copy(_:))
            case "x": #selector(NSText.cut(_:))
            case "a": #selector(NSText.selectAll(_:))
            case "z": event.modifierFlags.contains(.shift)
                ? #selector(UndoManager.redo)
                : #selector(UndoManager.undo)
            default: nil
            }

            if let action, let responder = NSApp.keyWindow?.firstResponder,
               responder.responds(to: action) {
                responder.perform(action, with: nil)
                return nil
            }
            return event
        }
    }
}

// MARK: - Main App

@main
struct MusicReelsGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = ProjectViewModel()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            TextEditingCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    viewModel.newProject()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Project...") {
                    openProject()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save Project") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save Project As...") {
                    saveProjectAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Import Video...") {
                    importVideo()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    private func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await viewModel.importVideo(url: url)
            }
        }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: ProjectPersistenceService.fileExtension)!]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadProject(from: url)
        }
    }

    private func save() {
        if !viewModel.saveProject() {
            // No file URL yet — show Save As
            saveProjectAs()
        }
    }

    private func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: ProjectPersistenceService.fileExtension)!]
        panel.nameFieldStringValue = "\(viewModel.project.title).\(ProjectPersistenceService.fileExtension)"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveProjectAs(to: url)
        }
    }
}
