import SwiftUI

struct TagFilterView: View {
    let tags: [Tag]
    @Binding var selectedTag: Tag?
    var onDeleteTag: ((Tag) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TagChip(
                    name: "All",
                    isSelected: selectedTag == nil,
                    action: { selectedTag = nil }
                )

                ForEach(tags) { tag in
                    TagChip(
                        name: tag.name,
                        count: tag.photos.count,
                        isSelected: selectedTag?.id == tag.id,
                        action: { selectedTag = tag },
                        onDelete: tag.photos.isEmpty ? { onDeleteTag?(tag) } : nil
                    )
                }
            }
        }
    }
}

struct TagChip: View {
    let name: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(name)
                    if let count {
                        Text("\(count)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)

            // Show X button on hover for deletable tags
            if isHovered && onDelete != nil {
                Button(action: { onDelete?() }) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .fontWeight(isSelected ? .semibold : .regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
        .foregroundStyle(isSelected ? .white : .primary)
        .clipShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    TagFilterView(tags: [], selectedTag: .constant(nil))
        .padding()
}
