import SwiftUI
import MarkdownUI

struct DashboardMessages: View {
    var conversations: [ConversationRecord]
    var selectedConversationId: String?
    var searchText: String
    var isLoading: Bool

    private var selectedConversation: ConversationRecord? {
        conversations.first(where: { $0.id == selectedConversationId })
    }

    var body: some View {
        VStack(alignment: .center) {
            if isLoading {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView("Loading conversations...Please wait")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
                Spacer()
            } else if conversations.isEmpty {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .resizable()
                        .frame(width: 54, height: 54)
                        .foregroundColor(.accentColor.opacity(0.25))
                    Text("No conversations loaded.")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Click 'Open' to import your ChatGPT conversation JSON file.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Divider().padding(.vertical, 8)
                    Text("Tip: You can export your conversations from ChatGPT or Gemini and import them here. For more help, see the documentation or FAQ.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: 400)
                .multilineTextAlignment(.center)
                Spacer()
            } else if selectedConversation == nil {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "arrow.left.circle.fill")
                        .resizable()
                        .frame(width: 54, height: 54)
                        .foregroundColor(.accentColor.opacity(0.25))
                    Text("Select a conversation from the sidebar.")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Click a conversation on the left to view its messages.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 400)
                .multilineTextAlignment(.center)
                Spacer()
            } else if let convo = selectedConversation {
                Text(convo.title)
                    .font(.title2)
                    .padding(.bottom, 4)
                if let created = convo.createTime {
                    Text("Created: \(created)")
                        .font(.caption)
                }
                if let updated = convo.updateTime {
                    Text("Updated: \(updated)")
                        .font(.caption)
                }
                Divider()
                if let mappingStr = convo.mapping, let mappingData = mappingStr.data(using: .utf8) {
                    let mapping = try? JSONDecoder().decode([String: AnyCodable].self, from: mappingData)
                    let messages = extractMessages(mapping: mapping)
                    if messages.isEmpty {
                        Text("No conversation content available.")
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(messages, id: \ .id) { msg in
                                    HStack(alignment: .top) {
                                        if msg.author == "user" {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Markdown(msg.content)
                                            }
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 16)
                                            .background(Color.gray.opacity(0.13))
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                                            )
                                            .frame(maxWidth: 500, alignment: .leading)
                                            Spacer()
                                        } else {
                                            Spacer()
                                            VStack(alignment: .leading, spacing: 4) {
                                                Markdown(msg.content)
                                            }
                                            .padding(.vertical, 10)
                                            .padding(.horizontal, 16)
                                            .background(Color.white)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                                            )
                                            .shadow(color: Color.gray.opacity(0.15), radius: 2, x: 0, y: 1)
                                            .frame(maxWidth: 700, alignment: .trailing)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 4)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
