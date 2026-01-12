import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum PhotoStorageService {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
    }

    static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: documentsDirectory,
            withIntermediateDirectories: true
        )
    }

    static func saveImage(_ data: Data) -> String? {
        ensureDirectoryExists()

        let filename = "\(UUID().uuidString).jpg"
        let url = documentsDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            return filename
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }

    #if canImport(UIKit)
    static func saveImage(_ image: UIImage, compressionQuality: CGFloat = 0.8) -> String? {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }
        return saveImage(data)
    }
    #endif

    static func loadImageData(filename: String) -> Data? {
        let url = documentsDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    static func deleteImage(filename: String) {
        let url = documentsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    static func imageExists(filename: String) -> Bool {
        let url = documentsDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
