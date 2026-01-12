import Foundation
import SwiftData
import CoreGraphics

@Model
final class Photo {
    var id: UUID
    var filename: String
    var dateAdded: Date
    var tags: [Tag] = []

    // Crop coordinates (normalized 0.0-1.0 for resolution independence)
    var cropX: Double = 0.0
    var cropY: Double = 0.0
    var cropSize: Double = 1.0  // Square crop, single dimension

    var imageURL: URL {
        PhotoStorageService.documentsDirectory.appendingPathComponent(filename)
    }

    var cropRect: CGRect {
        CGRect(x: cropX, y: cropY, width: cropSize, height: cropSize)
    }

    init(filename: String, cropX: Double = 0.0, cropY: Double = 0.0, cropSize: Double = 1.0) {
        self.id = UUID()
        self.filename = filename
        self.dateAdded = Date()
        self.cropX = cropX
        self.cropY = cropY
        self.cropSize = cropSize
    }
}
