import Foundation
import SwiftData

@Model
final class Photo {
    var id: UUID
    var filename: String
    var dateAdded: Date
    var tags: [Tag] = []

    var imageURL: URL {
        PhotoStorageService.documentsDirectory.appendingPathComponent(filename)
    }

    init(filename: String) {
        self.id = UUID()
        self.filename = filename
        self.dateAdded = Date()
    }
}
