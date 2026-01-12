import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.dateAdded, order: .reverse) private var allPhotos: [Photo]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var selectedTag: Tag?
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingTagSheet = false
    @State private var pendingImageData: Data?
    @State private var showingFileImporter = false
    @State private var isDropTargeted = false

    private var filteredPhotos: [Photo] {
        guard let tag = selectedTag else { return allPhotos }
        return allPhotos.filter { $0.tags.contains(where: { $0.id == tag.id }) }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 300), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 0) {
            TagFilterView(tags: allTags, selectedTag: $selectedTag)
                .padding(.horizontal)
                .padding(.vertical, 8)

            if filteredPhotos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(selectedTag == nil ? "Add photos to get started" : "No photos with this tag")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(filteredPhotos) { photo in
                            NavigationLink(value: photo) {
                                PhotoThumbnailView(photo: photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Reference")
        .navigationDestination(for: Photo.self) { photo in
            PhotoDetailView(photo: photo)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("From Photos Library", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("From Files", systemImage: "folder")
                    }
                } label: {
                    Label("Add Photo", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                    pendingImageData = data
                    showingTagSheet = true
                }
                selectedPhotoItem = nil
            }
        }
        .sheet(isPresented: $showingTagSheet) {
            if let imageData = pendingImageData {
                TagSelectionSheet(
                    imageData: imageData,
                    availableTags: allTags,
                    onSave: { selectedTags in
                        savePhoto(data: imageData, tags: selectedTags)
                        pendingImageData = nil
                    },
                    onCancel: {
                        pendingImageData = nil
                    }
                )
            }
        }
    }

    private func savePhoto(data: Data, tags: [Tag]) {
        guard let filename = PhotoStorageService.saveImage(data) else { return }

        let photo = Photo(filename: filename)
        photo.tags = tags
        modelContext.insert(photo)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if let data = try? Data(contentsOf: url) {
                pendingImageData = data
                showingTagSheet = true
            }
        case .failure:
            break
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        #if os(macOS)
        // On macOS, try to load as NSImage first (handles most drag sources)
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let nsImage = image as? NSImage,
                      let tiffData = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }

                DispatchQueue.main.async {
                    self.pendingImageData = imageData
                    self.showingTagSheet = true
                }
            }
            return
        }
        #endif

        // Try to load as file URL (for files dragged from Finder)
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }

                if let imageData = try? Data(contentsOf: url) {
                    DispatchQueue.main.async {
                        self.pendingImageData = imageData
                        self.showingTagSheet = true
                    }
                }
            }
            return
        }

        // Try to load as image data directly
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data = data else { return }
                DispatchQueue.main.async {
                    self.pendingImageData = data
                    self.showingTagSheet = true
                }
            }
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: Photo

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let data = PhotoStorageService.loadImageData(filename: photo.filename) {
                    #if os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholderView
                    }
                    #else
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholderView
                    }
                    #endif
                } else {
                    placeholderView
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview {
    NavigationStack {
        GalleryView()
    }
    .modelContainer(for: [Photo.self, Tag.self], inMemory: true)
}
