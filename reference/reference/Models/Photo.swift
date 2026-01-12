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
    var cropRotation: Double = 0.0  // Rotation in degrees

    // Head rotation angles (in degrees, nil = not set)
    var headYaw: Double?    // Left/Right rotation (-180 to 180)
    var headPitch: Double?  // Up/Down tilt (-90 to 90)
    var headRoll: Double?   // Side tilt (-180 to 180)

    var imageURL: URL {
        PhotoStorageService.documentsDirectory.appendingPathComponent(filename)
    }

    var cropRect: CGRect {
        CGRect(x: cropX, y: cropY, width: cropSize, height: cropSize)
    }

    var hasHeadRotation: Bool {
        headYaw != nil && headPitch != nil && headRoll != nil
    }

    init(
        filename: String,
        cropX: Double = 0.0,
        cropY: Double = 0.0,
        cropSize: Double = 1.0,
        cropRotation: Double = 0.0,
        headYaw: Double? = nil,
        headPitch: Double? = nil,
        headRoll: Double? = nil
    ) {
        self.id = UUID()
        self.filename = filename
        self.dateAdded = Date()
        self.cropX = cropX
        self.cropY = cropY
        self.cropSize = cropSize
        self.cropRotation = cropRotation
        self.headYaw = headYaw
        self.headPitch = headPitch
        self.headRoll = headRoll
    }
}
