import SwiftUI

struct DashboardRightPane: View {
    var allTags: [String]
    var selectedTag: String?
    var onSelectTag: (String?) -> Void
    var onAddTag: (String) -> Void
    var newTagText: String
    var tagFieldFocused: FocusState<Bool>.Binding
    var tagError: String?
    var selectedConversation: ConversationRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tag Filters")
                .font(.headline)
                .padding(.top, 16)
                .padding(.horizontal, 16)
            HStack(spacing: 10) {
                if let tag = selectedTag, !tag.isEmpty {
                    TagChip(tag: tag, isSelected: true) {
                        onSelectTag(nil)
                    }
                } else {
                    Text("(None)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            if selectedTag != nil {
                Button(action: { onSelectTag(nil) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                        Text("Clear Tag Filter")
                            .font(.body)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.13))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
            Text("All Tags")
                .font(.headline)
                .padding(.horizontal, 16)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(allTags, id: \ .self) { tag in
                        TagChip(tag: tag, isSelected: selectedTag == tag) {
                            onSelectTag(tag)
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Add tag", text: .constant(newTagText))
                            .font(.body)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.gray.opacity(0.13))
                            .cornerRadius(8)
                            .focused(tagFieldFocused)
                        Button(action: {
                            if !newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let convo = selectedConversation {
                                onAddTag(newTagText.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }) {
                            Text("Add")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                                .background(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedConversation == nil ? Color.gray : Color.accentColor)
                                .cornerRadius(8)
                        }
                        .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedConversation == nil)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            if let tagError = tagError {
                Text(tagError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }
            Spacer()
        }
        .frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
