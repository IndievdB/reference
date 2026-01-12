import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            GalleryView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Photo.self, Tag.self], inMemory: true)
}
