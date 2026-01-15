import SwiftUI
import SwiftData

struct PhotoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]

    let allPhotos: [Photo]  // All photos in current filter context
    @State private var currentPhotoId: UUID

    private var currentIndex: Int? {
        allPhotos.firstIndex(where: { $0.id == currentPhotoId })
    }

    private var photo: Photo {
        allPhotos.first(where: { $0.id == currentPhotoId }) ?? allPhotos[0]
    }

    private var hasPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }

    private var hasNext: Bool {
        guard let index = currentIndex else { return false }
        return index < allPhotos.count - 1
    }

    init(photo: Photo, allPhotos: [Photo]) {
        self.allPhotos = allPhotos
        self._currentPhotoId = State(initialValue: photo.id)
    }

    @State private var showingDeleteConfirmation = false
    @State private var showingTagEditor = false
    @State private var showingCropEditor = false
    @State private var showingAngleEditor = false
    @State private var showingAddAnotherCrop = false
    @State private var showingAddAnotherTagSheet = false
    @State private var showingRelighting = false
    @State private var pendingCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var pendingCropRotation: Double = 0.0
    @State private var pendingHeadRotation: HeadRotation?
    @State private var editingHeadRotation: HeadRotation = .zero
    @State private var newTagName = ""

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    // Full-size cropped image
                    if let data = PhotoStorageService.loadImageData(filename: photo.filename),
                       let croppedData = ImageCropService.applyCrop(to: data, cropRect: photo.cropRect, rotation: photo.cropRotation) {
                        #if os(macOS)
                        if let nsImage = NSImage(data: croppedData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.6)
                        } else {
                            photoPlaceholder
                        }
                        #else
                        if let uiImage = UIImage(data: croppedData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height * 0.6)
                        } else {
                            photoPlaceholder
                        }
                        #endif
                    } else {
                        photoPlaceholder
                    }

                    // Crop section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Crop")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingAddAnotherCrop = true
                            } label: {
                                Label("Add Another", systemImage: "plus.square.on.square")
                                    .font(.subheadline)
                            }
                            Button {
                                showingCropEditor = true
                            } label: {
                                Label("Edit", systemImage: "crop")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Relight section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Relight")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingRelighting = true
                            } label: {
                                Label("Experiment", systemImage: "light.max")
                                    .font(.subheadline)
                            }
                        }
                        Text("Play with lighting direction and intensity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Tags section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tags")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingTagEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.subheadline)
                            }
                        }

                        if photo.tags.isEmpty {
                            Text("No tags")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(photo.tags) { tag in
                                    TagChip(
                                        name: tag.name,
                                        isSelected: true,
                                        action: {}
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Head Angle section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Head Angle")
                                .font(.headline)
                            Spacer()
                            if photo.hasHeadRotation {
                                Button {
                                    editingHeadRotation = photo.headRotation ?? .zero
                                    showingAngleEditor = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .font(.subheadline)
                                }
                            } else {
                                Button {
                                    editingHeadRotation = .zero
                                    showingAngleEditor = true
                                } label: {
                                    Label("Set Angle", systemImage: "plus")
                                        .font(.subheadline)
                                }
                            }
                        }

                        if let rotation = photo.headRotation {
                            HStack(spacing: 16) {
                                HeadModelView(
                                    rotation: .constant(rotation),
                                    isInteractive: false,
                                    showResetButton: false
                                )
                                .frame(width: 80, height: 80)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Yaw: \(Int(rotation.yaw))°")
                                    Text("Pitch: \(Int(rotation.pitch))°")
                                    if rotation.roll != 0 {
                                        Text("Roll: \(Int(rotation.roll))°")
                                    }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                Spacer()
                            }
                        } else {
                            Text("No angle set")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal)

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Added")
                            .font(.headline)
                        Text(photo.dateAdded, style: .date)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Photo")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Button {
                        goToPrevious()
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(!hasPrevious)

                    Button {
                        goToNext()
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(!hasNext)
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete Photo", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deletePhoto()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingTagEditor) {
            TagEditorSheet(photo: photo, availableTags: allTags)
        }
        .sheet(isPresented: $showingCropEditor) {
            if let data = PhotoStorageService.loadImageData(filename: photo.filename) {
                CropView(
                    imageData: data,
                    initialCropRect: photo.cropRect,
                    initialRotation: photo.cropRotation,
                    initialHeadRotation: photo.headRotation,
                    onConfirm: { newCropRect, newRotation, newHeadRotation in
                        photo.cropX = newCropRect.origin.x
                        photo.cropY = newCropRect.origin.y
                        photo.cropSize = newCropRect.width
                        photo.cropRotation = newRotation
                        photo.headRotation = newHeadRotation
                        showingCropEditor = false
                    },
                    onCancel: {
                        showingCropEditor = false
                    }
                )
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
        }
        .sheet(isPresented: $showingAddAnotherCrop) {
            if let data = PhotoStorageService.loadImageData(filename: photo.filename) {
                CropView(
                    imageData: data,
                    initialCropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    initialRotation: 0.0,
                    initialHeadRotation: nil,
                    onConfirm: { cropRect, rotation, headRotation in
                        pendingCropRect = cropRect
                        pendingCropRotation = rotation
                        pendingHeadRotation = headRotation
                        showingAddAnotherCrop = false
                        showingAddAnotherTagSheet = true
                    },
                    onCancel: {
                        showingAddAnotherCrop = false
                    }
                )
                #if os(macOS)
                .presentationSizing(.fitted)
                #endif
            }
        }
        .sheet(isPresented: $showingAddAnotherTagSheet) {
            if let data = PhotoStorageService.loadImageData(filename: photo.filename),
               let croppedData = ImageCropService.applyCrop(to: data, cropRect: pendingCropRect, rotation: pendingCropRotation) {
                TagSelectionSheet(
                    imageData: croppedData,
                    availableTags: allTags,
                    onSave: { selectedTags in
                        saveAnotherCrop(tags: selectedTags)
                        pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        pendingCropRotation = 0.0
                        pendingHeadRotation = nil
                    },
                    onSaveAndAddAnother: { selectedTags in
                        saveAnotherCrop(tags: selectedTags)
                        pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        pendingCropRotation = 0.0
                        pendingHeadRotation = nil
                        showingAddAnotherTagSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingAddAnotherCrop = true
                        }
                    },
                    onCancel: {
                        pendingCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        pendingCropRotation = 0.0
                        pendingHeadRotation = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingAngleEditor) {
            HeadAngleEditorSheet(
                rotation: $editingHeadRotation,
                onSave: {
                    photo.headRotation = editingHeadRotation
                    showingAngleEditor = false
                },
                onCancel: {
                    showingAngleEditor = false
                }
            )
        }
        .sheet(isPresented: $showingRelighting) {
            if let data = PhotoStorageService.loadImageData(filename: photo.filename),
               let croppedData = ImageCropService.applyCrop(to: data, cropRect: photo.cropRect, rotation: photo.cropRotation) {
                RelightingView(imageData: croppedData) {
                    showingRelighting = false
                }
            }
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(4/3, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private func goToPrevious() {
        guard let index = currentIndex, index > 0 else { return }
        currentPhotoId = allPhotos[index - 1].id
    }

    private func goToNext() {
        guard let index = currentIndex, index < allPhotos.count - 1 else { return }
        currentPhotoId = allPhotos[index + 1].id
    }

    private func deletePhoto() {
        // Get tags before deleting photo
        let tagsToCheck = photo.tags
        let filename = photo.filename
        let deletedIndex = currentIndex

        // Check if other photos share this source file
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.filename == filename }
        )
        let photosWithSameFile = (try? modelContext.fetchCount(descriptor)) ?? 0

        // Delete the photo record
        modelContext.delete(photo)

        // Only delete the file if this was the last photo using it
        if photosWithSameFile <= 1 {
            PhotoStorageService.deleteImage(filename: filename)
        }

        // Remove any tags that now have no photos
        for tag in tagsToCheck {
            if tag.photos.isEmpty {
                modelContext.delete(tag)
            }
        }

        // Navigate to adjacent photo or dismiss if this was the last one
        if let index = deletedIndex {
            if index < allPhotos.count - 1 {
                // Go to next (which shifts into current position after delete)
                currentPhotoId = allPhotos[index + 1].id
            } else if index > 0 {
                // Go to previous
                currentPhotoId = allPhotos[index - 1].id
            } else {
                // This was the only photo
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    private func saveAnotherCrop(tags: [Tag]) {
        // Create new photo with same source file but different crop
        let newPhoto = Photo(
            filename: photo.filename,
            cropX: pendingCropRect.origin.x,
            cropY: pendingCropRect.origin.y,
            cropSize: pendingCropRect.width,
            cropRotation: pendingCropRotation,
            headYaw: pendingHeadRotation?.yaw,
            headPitch: pendingHeadRotation?.pitch,
            headRoll: pendingHeadRotation?.roll
        )
        newPhoto.tags = tags
        modelContext.insert(newPhoto)
    }
}

struct TagEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var photo: Photo
    let availableTags: [Tag]

    @State private var newTagName = ""

    private var currentTagIds: Set<UUID> {
        Set(photo.tags.map(\.id))
    }

    var body: some View {
        NavigationStack {
            tagList
                .navigationTitle("Edit Tags")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }

    private var tagList: some View {
        List {
            addTagSection
            allTagsSection
        }
    }

    private var addTagSection: some View {
        Section("Add New Tag") {
            HStack {
                TextField("Tag name", text: $newTagName)
                    .disableAutocorrection(true)

                Button("Add") {
                    addNewTag()
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var allTagsSection: some View {
        Section("All Tags") {
            ForEach(Array(availableTags), id: \.id) { (tag: Tag) in
                tagRow(for: tag)
            }
        }
    }

    private func tagRow(for tag: Tag) -> some View {
        HStack {
            Text(tag.name)
            Spacer()
            if currentTagIds.contains(tag.id) {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleTag(tag)
        }
    }

    private func toggleTag(_ tag: Tag) {
        if let index = photo.tags.firstIndex(where: { $0.id == tag.id }) {
            photo.tags.remove(at: index)
            // Remove tag if it now has no photos
            if tag.photos.isEmpty {
                modelContext.delete(tag)
            }
        } else {
            photo.tags.append(tag)
        }
    }

    private func addNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }

        if let existing = availableTags.first(where: { $0.name == name }) {
            if !photo.tags.contains(where: { $0.id == existing.id }) {
                photo.tags.append(existing)
            }
        } else {
            let tag = Tag(name: name)
            modelContext.insert(tag)
            photo.tags.append(tag)
        }

        newTagName = ""
    }
}

struct HeadAngleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var rotation: HeadRotation
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Adjust the head to match your photo's viewing angle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HeadModelView(
                    rotation: $rotation,
                    isInteractive: true,
                    showResetButton: true
                )
                .frame(maxHeight: 300)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Yaw (left/right):")
                        Spacer()
                        Text("\(Int(rotation.yaw))°")
                    }
                    HStack {
                        Text("Pitch (up/down):")
                        Spacer()
                        Text("\(Int(rotation.pitch))°")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Set Head Angle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }
}

#Preview {
    let photo = Photo(filename: "test.jpg")
    NavigationStack {
        PhotoDetailView(photo: photo, allPhotos: [photo])
    }
    .modelContainer(for: [Photo.self, Tag.self], inMemory: true)
}
