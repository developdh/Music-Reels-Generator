import Foundation
import Combine

/// Manages style preset persistence and in-memory state.
/// Stores presets as a JSON file in Application Support, reusable across all projects.
@MainActor
class StylePresetStore: ObservableObject {
    @Published private(set) var presets: [StylePreset] = []

    private static let fileName = "style_presets.json"

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

    static let shared = StylePresetStore()

    private init() {
        loadFromDisk()
    }

    // MARK: - File URL

    private static func fileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("MusicReelsGenerator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    // MARK: - CRUD Operations

    /// Save the current project style as a new named preset.
    func savePreset(
        name: String,
        subtitleStyle: SubtitleStyle,
        metadataOverlay: MetadataOverlaySettings
    ) -> StylePreset {
        let preset = StylePreset.fromProject(
            name: name,
            subtitleStyle: subtitleStyle,
            metadataOverlay: metadataOverlay
        )
        presets.append(preset)
        presets.sort { $0.updatedAt > $1.updatedAt }
        saveToDisk()
        print("[PresetStore] Saved preset: \(name) (id: \(preset.id))")
        return preset
    }

    /// Delete a preset by ID.
    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        saveToDisk()
        print("[PresetStore] Deleted preset: \(id)")
    }

    /// Rename a preset.
    func renamePreset(id: UUID, newName: String) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].name = newName
        presets[idx].updatedAt = Date()
        saveToDisk()
        print("[PresetStore] Renamed preset \(id) to: \(newName)")
    }

    /// Duplicate a preset with a new name.
    func duplicatePreset(id: UUID) -> StylePreset? {
        guard let source = presets.first(where: { $0.id == id }) else { return nil }
        let copy = StylePreset(
            name: "\(source.name) (복사)",
            subtitleStyle: source.subtitleStyle,
            overlayStyle: source.overlayStyle
        )
        presets.append(copy)
        presets.sort { $0.updatedAt > $1.updatedAt }
        saveToDisk()
        print("[PresetStore] Duplicated preset \(source.name) -> \(copy.name)")
        return copy
    }

    /// Update an existing preset with new style values.
    func updatePreset(
        id: UUID,
        subtitleStyle: SubtitleStyle,
        metadataOverlay: MetadataOverlaySettings
    ) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].subtitleStyle = subtitleStyle
        presets[idx].overlayStyle = .from(metadataOverlay)
        presets[idx].updatedAt = Date()
        saveToDisk()
    }

    /// Check if a name already exists (case-insensitive).
    func nameExists(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return presets.contains { $0.name.lowercased() == trimmed }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let library = StylePresetLibrary(presets: presets)
        do {
            let data = try Self.encoder.encode(library)
            try data.write(to: Self.fileURL(), options: .atomic)
        } catch {
            print("[PresetStore] ERROR saving presets: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        let url = Self.fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[PresetStore] No preset file found, starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let library = try Self.decoder.decode(StylePresetLibrary.self, from: data)
            presets = library.presets.sorted { $0.updatedAt > $1.updatedAt }
            print("[PresetStore] Loaded \(presets.count) presets")
        } catch {
            print("[PresetStore] ERROR loading presets: \(error.localizedDescription)")
            // Don't crash — start with empty presets
            presets = []
        }
    }
}
