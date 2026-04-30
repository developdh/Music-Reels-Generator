import Foundation
import Combine

/// Persists project templates as a JSON file in Application Support.
/// Mirrors `StylePresetStore`'s shape but operates on `ProjectTemplate`.
@MainActor
class ProjectTemplateStore: ObservableObject {
    @Published private(set) var templates: [ProjectTemplate] = []

    private static let fileName = "project_templates.json"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let shared = ProjectTemplateStore()

    private init() {
        loadFromDisk()
    }

    private static func fileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("MusicReelsGenerator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    @discardableResult
    func saveTemplate(
        name: String,
        project: Project,
        alignmentQualityMode: AlignmentQualityMode
    ) -> ProjectTemplate {
        let template = ProjectTemplate.fromProject(
            name: name,
            project: project,
            alignmentQualityMode: alignmentQualityMode
        )
        templates.append(template)
        templates.sort { $0.updatedAt > $1.updatedAt }
        saveToDisk()
        print("[TemplateStore] Saved template: \(name) (id: \(template.id))")
        return template
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        saveToDisk()
        print("[TemplateStore] Deleted template: \(id)")
    }

    func renameTemplate(id: UUID, newName: String) {
        guard let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[idx].name = newName
        templates[idx].updatedAt = Date()
        saveToDisk()
    }

    @discardableResult
    func duplicateTemplate(id: UUID, copySuffix: String) -> ProjectTemplate? {
        guard let source = templates.first(where: { $0.id == id }) else { return nil }
        let copy = ProjectTemplate(
            name: "\(source.name)\(copySuffix)",
            subtitleStyle: source.subtitleStyle,
            overlayStyle: source.overlayStyle,
            primaryLanguage: source.primaryLanguage,
            cropMode: source.cropMode,
            horizontalBlurRadius: source.horizontalBlurRadius,
            alignmentQualityMode: source.alignmentQualityMode
        )
        templates.append(copy)
        templates.sort { $0.updatedAt > $1.updatedAt }
        saveToDisk()
        return copy
    }

    func nameExists(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return templates.contains { $0.name.lowercased() == trimmed }
    }

    private func saveToDisk() {
        let library = ProjectTemplateLibrary(templates: templates)
        do {
            let data = try Self.encoder.encode(library)
            try data.write(to: Self.fileURL(), options: .atomic)
        } catch {
            print("[TemplateStore] ERROR saving templates: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        let url = Self.fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[TemplateStore] No template file found, starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let library = try Self.decoder.decode(ProjectTemplateLibrary.self, from: data)
            templates = library.templates.sorted { $0.updatedAt > $1.updatedAt }
            print("[TemplateStore] Loaded \(templates.count) templates")
        } catch {
            print("[TemplateStore] ERROR loading templates: \(error.localizedDescription)")
            templates = []
        }
    }
}
