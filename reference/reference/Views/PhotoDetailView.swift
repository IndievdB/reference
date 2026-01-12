import SwiftUI
import SwiftData

struct PhotoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @Bindable var photo: Photo

    @State private var showingDeleteConfirmation = false
    @State private var showingTagEditor = false
    @State private var showingCropEditor = false
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
                                showingCropEditor = true
                            } label: {
                                Label("Edit Crop", systemImage: "crop")
                                    .font(.subheadline)
                            }
                        }
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
                    onConfirm: { newCropRect, newRotation in
                        photo.cropX = newCropRect.origin.x
                        photo.cropY = newCropRect.origin.y
                        photo.cropSize = newCropRect.width
                        photo.cropRotation = newRotation
                        showingCropEditor = false
                    },
                    onCancel: {
                        showingCropEditor = false
                    }
                )
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

    private func deletePhoto() {
        // Get tags before deleting photo
        let tagsToCheck = photo.tags

        PhotoStorageService.deleteImage(filename: photo.filename)
        modelContext.delete(photo)

        // Remove any tags that now have no photos
        for tag in tagsToCheck {
            if tag.photos.isEmpty {
                modelContext.delete(tag)
            }
        }

        dismiss()
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

#Preview {
    NavigationStack {
        PhotoDetailView(photo: Photo(filename: "test.jpg"))
    }
    .modelContainer(for: [Photo.self, Tag.self], inMemory: true)
}
