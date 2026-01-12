import SwiftUI
import SwiftData

struct TagSelectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let imageData: Data
    let availableTags: [Tag]
    let onSave: ([Tag]) -> Void
    let onSaveAndAddAnother: (([Tag]) -> Void)?
    let onCancel: () -> Void

    @State private var selectedTagIds: Set<UUID> = []
    @State private var newTagName = ""

    #if os(macOS)
    private var previewImage: NSImage? {
        NSImage(data: imageData)
    }
    #else
    private var previewImage: UIImage? {
        UIImage(data: imageData)
    }
    #endif

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Add Tags")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        HStack(spacing: 12) {
                            if onSaveAndAddAnother != nil {
                                Button("Save & Add Another") {
                                    let selectedTags = availableTags.filter { selectedTagIds.contains($0.id) }
                                    onSaveAndAddAnother?(selectedTags)
                                    dismiss()
                                }
                            }
                            Button("Save") {
                                let selectedTags = availableTags.filter { selectedTagIds.contains($0.id) }
                                onSave(selectedTags)
                                dismiss()
                            }
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 550)
        #endif
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            imagePreview
            Divider()
            tagList
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = previewImage {
            #if os(macOS)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
            #else
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
            #endif
        }
    }

    private var tagList: some View {
        List {
            addTagSection
            existingTagsSection
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

    @ViewBuilder
    private var existingTagsSection: some View {
        if !availableTags.isEmpty {
            Section("Existing Tags") {
                ForEach(Array(availableTags), id: \.id) { (tag: Tag) in
                    tagRow(for: tag)
                }
            }
        }
    }

    private func tagRow(for tag: Tag) -> some View {
        HStack {
            Text(tag.name)
            Spacer()
            if selectedTagIds.contains(tag.id) {
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
        if selectedTagIds.contains(tag.id) {
            selectedTagIds.remove(tag.id)
        } else {
            selectedTagIds.insert(tag.id)
        }
    }

    private func addNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }

        if let existing = availableTags.first(where: { $0.name == name }) {
            selectedTagIds.insert(existing.id)
        } else {
            let tag = Tag(name: name)
            modelContext.insert(tag)
            selectedTagIds.insert(tag.id)
        }

        newTagName = ""
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        let totalWidth = frames.map { $0.maxX }.max() ?? 0

        return (CGSize(width: totalWidth, height: totalHeight), frames)
    }
}
