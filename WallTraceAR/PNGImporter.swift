import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum PNGImporter {
    private enum ImportError: LocalizedError {
        case tooLarge, invalidPNG
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Оберіть PNG розміром до 32 МіБ."
            case .invalidPNG: return "Файл пошкоджений або не є PNG."
            }
        }
    }

    static func load(_ url: URL) throws -> UIImage {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ImportError.invalidPNG }
        let limit = 32 * 1024 * 1024
        guard let size = values.fileSize, size > 0, size <= limit else { throw ImportError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limit else { throw ImportError.tooLarge }
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier else {
            throw ImportError.invalidPNG
        }
        // Decode directly to a bounded texture, without allocating the full image.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImportError.invalidPNG
        }
        return UIImage(cgImage: thumbnail)
    }
}
