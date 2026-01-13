import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.dateAdded, order: .reverse) private var allPhotos: [Photo]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var selectedTag: Tag?
    @State private var angleFilterRotation: HeadRotation?
    @State private var showingCropView = false
    @State private var showingTagSheet = false
    @State private var pendingImageData: Data?
    @State private var pendingCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var pendingCropRotation: Double = 0.0
    @State private var pendingHeadRotation: HeadRotation?
    @State private var pendingFilename: String?  // Reuse for multiple crops from same source
    @State private var showingFileImporter = false
    @State private var isDropTargeted = false

    private let angleTolerance: Double = 20.0  // Degrees

    private var filteredPhotos: [Photo] {
        var photos = allPhotos

        // Filter by tag
        if let tag = selectedTag {
            photos = photos.filter { $0.tags.contains(where: { $0.id == tag.id }) }
        }

        // Filter by head angle
        if let filterRotation = angleFilterRotation {
            photos = photos.filter { photo in
                guard let photoRotation = photo.headRotation else {
                    return false  // Photos without angle data are excluded when filtering
                }
                return photoRotation.isWithinTolerance(of: filterRotation, degrees: angleTolerance)
            }
        }

        return photos
    }

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 300), spacing: 8)
    ]

    private var emptyStateMessage: String {
        if selectedTag != nil && angleFilterRotation != nil {
            return "No photos match both the tag and angle filters"
        } else if selectedTag != nil {
            return "No photos with this tag"
        } else if angleFilterRotation != nil {
            return "No photos match this angle"
        } else {
            return "Add photos to get started"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TagFilterView(tags: allTags, selectedTag: $selectedTag) { tag in
                // Clear selection if deleting the selected tag
                if selectedTag?.id == tag.id {
                    selectedTag = nil
                }
                modelContext.delete(tag)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            HeadAngleFilterView(filterRotation: $angleFilterRotation, tolerance: angleTolerance)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if filteredPhotos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(emptyStateMessage)
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 40)
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
            PhotoDetailView(photo: photo, allPhotos: filteredPhotos)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFileImporter = true
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
        .sheet(isPresented: $showingCropView) {
            if let imageData = pendingImageData {
                CropView(
                    imageData: imageData,
                    initialCropRect: pendingCropRect,
                    initialRotation: pendingCropRotation,
                    initialHeadRotation: pendingHeadRotation,
                    onConfirm: { cropRect, rotation, headRotation in
                        pendingCropRect = cropRect
                        pendingCropRotation = rotation
                        pendingHeadRotation = headRotation
                        showingCropView = false
                        showingTagSheet = true
                    },
                    onCancel: {
                        pendingImageData = nil
                        pendingFilename = nil
                        pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        pendingCropRotation = 0.0
                        pendingHeadRotation = nil
                        showingCropView = false
                    }
                )
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
        }
        .sheet(isPresented: $showingTagSheet) {
            if let imageData = pendingImageData,
               let croppedData = ImageCropService.applyCrop(to: imageData, cropRect: pendingCropRect, rotation: pendingCropRotation) {
                TagSelectionSheet(
                    imageData: croppedData,
                    availableTags: allTags,
                    onSave: { selectedTags in
                        savePhoto(data: imageData, tags: selectedTags)
                        // Clear all pending state - we're done
                        pendingImageData = nil
                        pendingFilename = nil
                        pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        pendingCropRotation = 0.0
                        pendingHeadRotation = nil
                    },
                    onSaveAndAddAnother: { selectedTags in
                        savePhoto(data: imageData, tags: selectedTags)
                        // Keep pendingImageData and pendingFilename for reuse
                        pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        pendingCropRotation = 0.0
                        pendingHeadRotation = nil
                        showingTagSheet = false
                        // Small delay to allow sheet dismissal before showing crop view
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingCropView = true
                        }
                    },
                    onCancel: {
                        pendingImageData = nil
                        pendingFilename = nil
                        pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        pendingCropRotation = 0.0
                        pendingHeadRotation = nil
                    }
                )
            }
        }
    }

    private func savePhoto(data: Data, tags: [Tag]) {
        // Reuse existing filename or create new one
        let filename: String
        if let existing = pendingFilename {
            filename = existing
        } else {
            guard let newFilename = PhotoStorageService.saveImage(data) else { return }
            filename = newFilename
            pendingFilename = newFilename  // Store for reuse
        }

        let photo = Photo(
            filename: filename,
            cropX: pendingCropRect.origin.x,
            cropY: pendingCropRect.origin.y,
            cropSize: pendingCropRect.width,
            cropRotation: pendingCropRotation,
            headYaw: pendingHeadRotation?.yaw,
            headPitch: pendingHeadRotation?.pitch,
            headRoll: pendingHeadRotation?.roll
        )
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
                pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                pendingCropRotation = 0.0
                showingCropView = true
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
                    self.pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    self.pendingCropRotation = 0.0
                    self.showingCropView = true
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
                        self.pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        self.pendingCropRotation = 0.0
                        self.showingCropView = true
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
                    self.pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    self.pendingCropRotation = 0.0
                    self.showingCropView = true
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
                if let data = PhotoStorageService.loadImageData(filename: photo.filename),
                   let croppedData = ImageCropService.applyCrop(to: data, cropRect: photo.cropRect, rotation: photo.cropRotation) {
                    #if os(macOS)
                    if let nsImage = NSImage(data: croppedData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        placeholderView
                    }
                    #else
                    if let uiImage = UIImage(data: croppedData) {
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
