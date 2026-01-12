import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String

    @Relationship(inverse: \Photo.tags)
    var photos: [Photo] = []

    init(name: String) {
        self.id = UUID()
        self.name = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
