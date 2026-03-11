import Foundation

enum PersistenceError: LocalizedError {
    case saveFailed(String)
    case loadFailed(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let msg): return "Failed to save project: \(msg)"
        case .loadFailed(let msg): return "Failed to load project: \(msg)"
        case .fileNotFound(let path): return "Project file not found: \(path)"
        }
    }
}

enum ProjectPersistenceService {
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

    static let fileExtension = "mreels"

    static func save(_ project: Project, to url: URL) throws {
        do {
            let data = try encoder.encode(project)
            try data.write(to: url, options: .atomic)
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }

    static func load(from url: URL) throws -> Project {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PersistenceError.fileNotFound(url.path)
        }

        do {
            let data = try Data(contentsOf: url)
            let project = try decoder.decode(Project.self, from: data)

            // Validate source video still exists
            if let videoPath = project.sourceVideoPath,
               !FileManager.default.fileExists(atPath: videoPath) {
                print("Warning: Source video not found at \(videoPath)")
            }

            return project
        } catch {
            throw PersistenceError.loadFailed(error.localizedDescription)
        }
    }

    /// Auto-save location in Application Support
    static func autoSaveDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MusicReelsGenerator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func autoSave(_ project: Project) throws {
        let dir = autoSaveDirectory()
        let url = dir.appendingPathComponent("\(project.id.uuidString).\(fileExtension)")
        try save(project, to: url)
    }

    static func listAutoSavedProjects() -> [(url: URL, project: Project)] {
        let dir = autoSaveDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == fileExtension }
            .compactMap { url in
                guard let project = try? load(from: url) else { return nil }
                return (url: url, project: project)
            }
            .sorted { $0.project.updatedAt > $1.project.updatedAt }
    }
}
