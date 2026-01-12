import SwiftUI

struct TagFilterView: View {
    let tags: [Tag]
    @Binding var selectedTag: Tag?

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
                        action: { selectedTag = tag }
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

    var body: some View {
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
            .font(.subheadline)
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TagFilterView(tags: [], selectedTag: .constant(nil))
        .padding()
}
