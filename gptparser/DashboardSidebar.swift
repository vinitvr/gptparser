import SwiftUI

struct DashboardSidebar: View {
    var sidebarGrouped: [(folder: FolderInfo, conversations: [ConversationRecord])]
    var sidebarUngrouped: [ConversationRecord]
    @Binding var expandedFolders: Set<String>
    @Binding var selectedConversationId: String?
    var onSelectConversation: (String) -> Void
    var onToggleFolder: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Imported Conversations")
                .font(.headline)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .center)
            List {
                if !sidebarGrouped.isEmpty {
                    ForEach(sidebarGrouped, id: \ .folder.id) { group in
                        Section(header: Text(group.folder.name).font(.subheadline).fontWeight(.medium)) {
                            if expandedFolders.contains(group.folder.id) {
                                ForEach(group.conversations, id: \ .id) { convo in
                                    let isSelected = selectedConversationId == convo.id
                                    Text(convo.title)
                                        .font(.body)
                                        .foregroundColor(isSelected ? .accentColor : .primary)
                                        .onTapGesture { onSelectConversation(convo.id) }
                                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                if sidebarGrouped.isEmpty && !sidebarUngrouped.isEmpty {
                    ForEach(sidebarUngrouped, id: \ .id) { convo in
                        let isSelected = selectedConversationId == convo.id
                        Text(convo.title)
                            .font(.body)
                            .foregroundColor(isSelected ? .accentColor : .primary)
                            .onTapGesture { onSelectConversation(convo.id) }
                            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                    }
                }
                if !sidebarGrouped.isEmpty && !sidebarUngrouped.isEmpty {
                    Section(header: Text("Ungrouped").font(.headline)) {
                        ForEach(sidebarUngrouped, id: \ .id) { convo in
                            let isSelected = selectedConversationId == convo.id
                            Text(convo.title)
                                .font(.body)
                                .foregroundColor(isSelected ? .accentColor : .primary)
                                .onTapGesture { onSelectConversation(convo.id) }
                                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .frame(width: 250)
    }
}
