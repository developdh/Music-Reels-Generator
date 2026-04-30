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
    let title: String

    init(updater: SPUUpdater, title: String = "Check for Updates…") {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
        self.title = title
    }

    var body: some View {
        Button(title, action: updater.checkForUpdates)
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

            // Cmd+Z / Shift+Cmd+Z are handled by the SwiftUI Edit menu below —
            // that path also forwards to any focused text responder first, so
            // leave them alone here.
            let action: Selector? = switch chars {
            case "v": #selector(NSText.paste(_:))
            case "c": #selector(NSText.copy(_:))
            case "x": #selector(NSText.cut(_:))
            case "a": #selector(NSText.selectAll(_:))
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
    @StateObject private var templateStore = ProjectTemplateStore.shared
    @State private var showSaveTemplateSheet = false
    @State private var showManageTemplatesSheet = false
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
                .sheet(isPresented: $showSaveTemplateSheet) {
                    SaveTemplateSheet(vm: viewModel, store: templateStore)
                }
                .sheet(isPresented: $showManageTemplatesSheet) {
                    ManageTemplatesSheet(vm: viewModel, store: templateStore)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            TextEditingCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater, title: L10n.Menu.checkForUpdates(viewModel.lang))
            }
            CommandGroup(replacing: .undoRedo) {
                UndoRedoCommands(viewModel: viewModel)
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.Menu.newProject(viewModel.lang)) {
                    viewModel.newProject()
                }
                .keyboardShortcut("n", modifiers: .command)

                Menu(L10n.Menu.newFromTemplate(viewModel.lang)) {
                    if templateStore.templates.isEmpty {
                        Text(L10n.Menu.noTemplates(viewModel.lang))
                    } else {
                        ForEach(templateStore.templates) { template in
                            Button(template.name) {
                                viewModel.newProject(fromTemplate: template)
                            }
                        }
                    }
                    Divider()
                    Button(L10n.Menu.saveAsTemplate(viewModel.lang)) {
                        showSaveTemplateSheet = true
                    }
                    Button(L10n.Menu.manageTemplates(viewModel.lang)) {
                        showManageTemplatesSheet = true
                    }
                    .disabled(templateStore.templates.isEmpty)
                }

                Button(L10n.Menu.openProject(viewModel.lang)) {
                    openProject()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(L10n.Menu.saveProject(viewModel.lang)) {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button(L10n.Menu.saveProjectAs(viewModel.lang)) {
                    saveProjectAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button(L10n.Menu.importVideo(viewModel.lang)) {
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

// MARK: - Undo/Redo Menu Commands

/// Separate View so the menu re-evaluates when undo state changes.
///
/// Only forwards `undo:`/`redo:` to the responder chain when the first responder
/// is actually a text editor. Otherwise NSWindow / NSApp claim the selector via
/// their default NSResponder handler and swallow the event without doing anything,
/// which would silently eat our project-level undo.
private struct UndoRedoCommands: View {
    @ObservedObject var viewModel: ProjectViewModel

    var body: some View {
        Button(L10n.Menu.undo(viewModel.lang)) {
            if Self.forwardToTextResponder("undo:") { return }
            viewModel.performUndo()
        }
        .keyboardShortcut("z", modifiers: .command)

        Button(L10n.Menu.redo(viewModel.lang)) {
            if Self.forwardToTextResponder("redo:") { return }
            viewModel.performRedo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
    }

    private static func forwardToTextResponder(_ selectorName: String) -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder,
              responder is NSText || responder is NSTextView else { return false }
        return NSApp.sendAction(Selector((selectorName)), to: nil, from: nil)
    }
}
