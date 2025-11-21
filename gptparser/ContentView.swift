import SwiftUI
import SQLite
import MarkdownUI

// FolderInfo struct for folder grouping
struct FolderInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

// Helper for chat message
struct ChatMessage: Identifiable, Hashable {
    let id: String
    let author: String
    let content: String
}

// Helper to decode unknown JSON structure
struct AnyCodable: Codable, CustomStringConvertible {
    var value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = ""
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let arrayValue = value as? [Any] {
            let codableArray = arrayValue.map { AnyCodable($0) }
            try container.encode(codableArray)
        } else if let dictValue = value as? [String: Any] {
            let codableDict = dictValue.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        } else {
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
    var description: String {
        if let dict = value as? [String: Any] {
            return prettyPrint(dict)
        } else if let array = value as? [Any] {
            return String(describing: array)
        } else {
            return String(describing: value)
        }
    }
    private func prettyPrint(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return String(describing: dict)
        }
        return str
    }
}

// Helper to highlight search terms in a string for SwiftUI
func highlightText(_ text: String, search: String) -> Text {
    guard !search.isEmpty else { return Text(text) }
    let lcText = text.lowercased()
    let lcSearch = search.lowercased()
    var result = Text("")
    var currentIndex = lcText.startIndex
    while let range = lcText.range(of: lcSearch, options: [], range: currentIndex..<lcText.endIndex) {
        let before = String(text[currentIndex..<range.lowerBound])
        if !before.isEmpty { result = result + Text(before) }
        let match = String(text[range])
        result = result + Text(match).foregroundColor(.black).bold()
        currentIndex = range.upperBound
    }
    let after = String(text[currentIndex..<lcText.endIndex])
    if !after.isEmpty { result = result + Text(after) }
    return result
}

// Extract messages from mapping
func extractMessages(mapping: [String: AnyCodable]?) -> [ChatMessage] {
    guard let mapping = mapping else { return [] }
    // Build a map of id -> node
    var nodeMap: [String: [String: Any]] = [:]
    for (key, value) in mapping {
        if let node = value.value as? [String: Any] {
            nodeMap[key] = node
        }
    }
    // Print all mapping keys for debug
    print("[extractMessages] Mapping keys: \(Array(nodeMap.keys))")
    // Find all root node candidates (parent == nil, NSNull, or missing)
    let rootIds = nodeMap.compactMap { (key, node) -> String? in
        let parentRaw = node["parent"]
        if parentRaw == nil { return key }
        if parentRaw is NSNull { return key }
        if let ac = parentRaw as? AnyCodable, ac.value is NSNull { return key }
        if let str = parentRaw as? String, str.isEmpty { return key }
        return nil
    }
    print("[extractMessages] Root node candidates: \(rootIds)")
    guard rootIds.count == 1, let rootId = rootIds.first else {
        print("[extractMessages] Error: Expected exactly one root node, found \(rootIds.count)")
        print("[extractMessages] Node keys and parent values:")
        for (key, node) in nodeMap {
            if let parent = node["parent"] {
                print("  id: \(key), parent: \(parent)")
            } else {
                print("  id: \(key), parent: <missing>")
            }
        }
        return []
    }
    var orderedMessages: [ChatMessage] = []
    var currentId: String? = rootId
    while let cid = currentId, let node = nodeMap[cid] {
        if let message = node["message"] as? [String: Any],
           let author = message["author"] as? [String: Any],
           let role = author["role"] as? String,
           let content = message["content"] as? [String: Any],
           let parts = content["parts"] as? [Any],
           let text = parts.first as? String {
            orderedMessages.append(ChatMessage(id: cid, author: role, content: text))
        }
        // Follow only the first child
        if let children = node["children"] as? [String], let nextId = children.first {
            currentId = nextId
        } else {
            currentId = nil
        }
    }
    return orderedMessages
}

struct ContentView: SwiftUI.View {
    // Computed properties for sidebar grouping
    private var sidebarGrouped: [(folder: FolderInfo, conversations: [ConversationRecord])] {
        let folders = fetchAllFolders()
        return groupConversationsByFolder(conversations: conversations, folders: folders).grouped
    }

    private var sidebarUngrouped: [ConversationRecord] {
        let folders = fetchAllFolders()
        return groupConversationsByFolder(conversations: conversations, folders: folders).ungrouped
    }
    // --- State properties ---
    @State private var showLoadingModal = false
    @State private var showFileImporter = false
    @State private var showOpenFileWarning = false
    @State private var showInvalidAlert = false
    @State private var showEmptyAlert = false
    @State private var showClearDataAlert = false
    @State private var errorDetails: String = ""
    @State private var conversations: [ConversationRecord] = []
    @State private var isLoading: Bool = false
    @State private var fileLoaded: Bool = false
    @State private var newTagText: String = ""
    @FocusState private var tagFieldFocused: Bool
    @State private var tagError: String?
    @State private var searchText: String = ""
    @State private var searchResults: [String: (content: String, score: Double)] = [:]
    @State private var selectedTag: String? = nil
    @State private var expandedFolders: Set<String> = []
    @State private var selectedConversationId: String? = nil
    @State private var recentFolders: [String] = []
    @State private var recentTags: [String] = []

    // Add a tag to a conversation and update UI
    private func addTag(_ tag: String, to convo: ConversationRecord) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if convo.tags.contains(trimmed) {
            tagError = "Tag already exists."
            newTagText = ""
            return
        }
        SQLiteManager.shared.addTag(trimmed, to: convo.id)
    }

    var body: some SwiftUI.View {
        Dashboard(
            conversations: $conversations,
            sidebarGrouped: sidebarGrouped,
            sidebarUngrouped: sidebarUngrouped,
            expandedFolders: $expandedFolders,
            selectedConversationId: $selectedConversationId,
            onSelectConversation: { id in selectedConversationId = id },
            onToggleFolder: { id in
                if expandedFolders.contains(id) {
                    expandedFolders.remove(id)
                } else {
                    expandedFolders.insert(id)
                }
            }
        )
        .onAppear {
            loadConversationsFromDB()
        }
    }

    // --- Helper methods and computed properties ---
    // Fetch all folders from SQLiteManager
    private func fetchAllFolders() -> [FolderInfo] {
        let folderTuples = SQLiteManager.shared.fetchFolders()
        return folderTuples.map { FolderInfo(id: $0.id, name: $0.name) }
    }

    // Group conversations by folder
    private func groupConversationsByFolder(conversations: [ConversationRecord], folders: [FolderInfo]) -> (grouped: [(folder: FolderInfo, conversations: [ConversationRecord])], ungrouped: [ConversationRecord]) {
        var folderMap: [String: [ConversationRecord]] = [:]
        var ungrouped: [ConversationRecord] = []
        for convo in conversations {
            if let folderId = convo.folderId, let _ = folders.first(where: { $0.id == folderId }) {
                folderMap[folderId, default: []].append(convo)
            } else {
                ungrouped.append(convo)
            }
        }
        let grouped = folders.compactMap { folder -> (folder: FolderInfo, conversations: [ConversationRecord])? in
            let convos = folderMap[folder.id] ?? []
            return convos.isEmpty ? nil : (folder, convos)
        }
        return (grouped, ungrouped)
    }

    // Filtered conversations by search and tag
    private func filteredConversations() -> [ConversationRecord] {
        var filtered = conversations
        print("[DEBUG] filteredConversations: initial count = \(filtered.count), selectedTag = \(String(describing: selectedTag)), searchText = \(searchText)")
        if let tag = selectedTag, !tag.isEmpty {
            filtered = filtered.filter { $0.tags.contains(tag) }
            print("[DEBUG] filteredConversations: after tag filter count = \(filtered.count)")
        }
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            filtered = filtered.filter { $0.title.lowercased().contains(lower) || ($0.mapping?.lowercased().contains(lower) ?? false) }
            print("[DEBUG] filteredConversations: after search filter count = \(filtered.count)")
        }
        return filtered
    }

    // Update recent folders (LRU, max 3)
    private func updateRecentFolders(with folderId: String) {
        if let idx = recentFolders.firstIndex(of: folderId) {
            recentFolders.remove(at: idx)
        }
        recentFolders.insert(folderId, at: 0)
        if recentFolders.count > 3 {
            recentFolders = Array(recentFolders.prefix(3))
        }
    }

    // Update recent tags (LRU, max 3)
    private func updateRecentTags(with tag: String) {
        if let idx = recentTags.firstIndex(of: tag) {
            recentTags.remove(at: idx)
        }
        recentTags.insert(tag, at: 0)
        if recentTags.count > 3 {
            recentTags = Array(recentTags.prefix(3))
        }
    }

    // Selected conversation (computed property)
    private var selectedConversation: ConversationRecord? {
        conversations.first(where: { $0.id == selectedConversationId })
    }

    // Perform search (simple title/content search)
    private func performSearch() {
        // This can be replaced with FTS for more advanced search
        // For now, just triggers filteredConversations recompute
    }
    // --- Helper methods and computed properties ---
    @ViewBuilder
    private func ConversationRow(convo: ConversationRecord, isSelected: Bool, onSelect: @escaping () -> Void) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: 2) {
            Text(convo.title)
                .font(.body)
            if !convo.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(convo.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.18))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onTapGesture { onSelect() }
    }

    @ViewBuilder
    private func FolderHeader(folder: FolderInfo, isExpanded: Bool, onToggle: @escaping () -> Void) -> some SwiftUI.View {
        // ...existing code...
    }

    @ViewBuilder
    private func TagChip(tag: String, isSelected: Bool, onSelect: @escaping () -> Void) -> some SwiftUI.View {
        // ...existing code...
    }

    // Helper view for rendering chat messages
    @ViewBuilder
    private func MessagesView(messages: [ChatMessage], searchText: String) -> some SwiftUI.View {
        MessagesForEachView(messages: messages, searchText: searchText)
    }

    // Helper view for ForEach over messages
    @ViewBuilder
    private func MessagesForEachView(messages: [ChatMessage], searchText: String) -> some SwiftUI.View {
        let lowerSearch = searchText.lowercased()
        let matchIndices = !lowerSearch.isEmpty ? messages.enumerated().compactMap { idx, msg in msg.content.lowercased().contains(lowerSearch) ? idx : nil } : []
        ForEach(Array(messages.enumerated()), id: \ .offset) { pair in
            let (idx, msg) = pair
            let isMatch = !lowerSearch.isEmpty && msg.content.lowercased().contains(lowerSearch)
            let isFirstMatch = isMatch && matchIndices.first == idx
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
                    .id(isFirstMatch ? "firstMatch" : nil)
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
                    .id(isFirstMatch ? "firstMatch" : nil)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
        }
    }

    // Helper: Fetch all unique tags from all conversations
    private var allTags: [String] {
        let tags = conversations.flatMap { $0.tags }
        return Array(Set(tags)).sorted()
    }
    // MARK: - Load Conversations
    func loadConversationsFromDB() {
        self.conversations = SQLiteManager.shared.fetchAllConversations()
        print("[DEBUG] loadConversationsFromDB: loaded \(conversations.count) conversations")
        for convo in conversations {
            print("[DEBUG] convo: id=\(convo.id), title=\(convo.title), folderId=\(String(describing: convo.folderId)), tags=\(convo.tags)")
        }
        if let first = conversations.first {
            selectedConversationId = first.id
        }
    }


    // MARK: - Main View
    // ...existing code for the main body property and its implementation...
}
// Helper: Print sidebar state for debugging (file-scope function)
fileprivate func debugPrintSidebarState(sidebarGrouped: [FolderInfo], sidebarUngrouped: [ConversationRecord]) {
    print("[DEBUG] Sidebar List: grouped count = \(sidebarGrouped.count), ungrouped count = \(sidebarUngrouped.count)")
    if !sidebarUngrouped.isEmpty {
        print("[DEBUG] Sidebar List: rendering ungrouped section with \(sidebarUngrouped.count) conversations")
    }
    if sidebarGrouped.isEmpty && sidebarUngrouped.isEmpty {
        print("[DEBUG] Sidebar List: no conversations found")
    }
}
