import SwiftUI

@main
struct MusicReelsGeneratorApp: App {
    @StateObject private var viewModel = ProjectViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
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
