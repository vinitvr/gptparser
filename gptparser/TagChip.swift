import SwiftUI

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Text(tag)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.13))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isSelected ? 1.2 : 0.5)
            )
            .onTapGesture { onSelect() }
    }
}
