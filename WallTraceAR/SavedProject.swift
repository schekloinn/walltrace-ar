import Foundation

struct SavedProject: Codable {
    struct Image: Codable {
        var slot: Int
        var name: String
        var png: Data
        var width: Float
        var opacity: Float
        var anchorID: UUID?
    }

    enum StorageError: LocalizedError {
        case invalid, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalid: return "Збережену сцену пошкоджено або її формат не підтримується."
            case .tooLarge: return "Сцена завелика для збереження. Спробуйте менші PNG та компактнішу ділянку кімнати."
            }
        }
    }

    var formatVersion = 1
    var savedAt = Date()
    var selectedIndex: Int
    var worldMap: Data
    var images: [Image]
    static let maximumBytes = 80 * 1024 * 1024

    func validate() throws {
        guard formatVersion == 1, (0..<3).contains(selectedIndex), !worldMap.isEmpty,
              !images.isEmpty, images.count <= 3,
              Set(images.map { $0.slot }).count == images.count,
              Set(images.compactMap { $0.anchorID }).count == images.compactMap({ $0.anchorID }).count else {
            throw StorageError.invalid
        }
        for image in images {
            guard (0..<3).contains(image.slot), image.width.isFinite, image.opacity.isFinite,
                  (0.05...2).contains(image.width), (0.05...1).contains(image.opacity),
                  image.png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
                throw StorageError.invalid
            }
            guard image.png.count <= 32 * 1024 * 1024 else { throw StorageError.tooLarge }
        }
        guard worldMap.count <= Self.maximumBytes else { throw StorageError.tooLarge }
    }

    func write(to url: URL) throws {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw StorageError.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomically replace one complete snapshot; a failed save preserves the old one.
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> SavedProject {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumBytes else { throw StorageError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumBytes else { throw StorageError.tooLarge }
        let project = try JSONDecoder().decode(Self.self, from: data)
        try project.validate()
        return project
    }
}
