import SwiftUI
import SQLite

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
    var messages: [ChatMessage] = []
    for (key, value) in mapping {
        if let node = value.value as? [String: Any],
           let message = node["message"] as? [String: Any],
           let author = message["author"] as? [String: Any],
           let role = author["role"] as? String,
           let content = message["content"] as? [String: Any],
           let parts = content["parts"] as? [Any],
           let text = parts.first as? String {
            messages.append(ChatMessage(id: key, author: role, content: text))
        }
    }
    return messages.sorted { $0.id < $1.id }
}

struct ContentView: SwiftUI.View {
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
        reloadSelectedConversationTags()
        newTagText = ""
        tagFieldFocused = true
    }

    // Reload tags for the selected conversation
    private func reloadSelectedConversationTags() {
        guard let convo = selectedConversation else { return }
        let updatedTags = SQLiteManager.shared.fetchTags(for: convo.id)
        if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
            conversations[idx].tags = updatedTags
        }
    }
    // Helper view for rendering the tag grid in the right tag panel
    @ViewBuilder
    private func TagGridView(selectedTag: String?, allTags: [String], onSelect: @escaping (String) -> Void) -> some SwiftUI.View {
        let columns = [GridItem(.adaptive(minimum: 90, maximum: 140), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(allTags, id: \ .self) { tag in
                Button(action: { onSelect(tag) }) {
                    Text(tag)
                        .font(.body)
                        .foregroundColor(selectedTag == tag ? .white : .primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(selectedTag == tag ? Color.accentColor : Color.gray.opacity(0.13))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    // Helper view for rendering the scrollable messages area in the central pane
    @ViewBuilder
    private func CentralMessagesScrollView(messages: [ChatMessage], searchText: String) -> some SwiftUI.View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                CentralMessagesSection(messages: messages, searchText: searchText)
            }
            .onAppear {
                withAnimation {
                    scrollProxy.scrollTo("firstMatch", anchor: .center)
                }
            }
        }
    }
    // Helper view for rendering the messages section in the central pane
    @ViewBuilder
    private func CentralMessagesSection(messages: [ChatMessage], searchText: String) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: 12) {
            MessagesForEachView(messages: messages, searchText: searchText)
        }
        .padding(.top, 8)
    }
    // Helper view for rendering ungrouped conversations in the sidebar
    private var SidebarUngroupedView: some SwiftUI.View {
        ForEach(sidebarUngrouped, id: \.id) { convo in
            let isSelected = selectedConversationId == convo.id
            ConversationRow(convo: convo, isSelected: isSelected) {
                selectedConversationId = convo.id
            }
        }
    }
    // Helper view for rendering all folder groups in the sidebar
    private var SidebarFolderGroupsView: some SwiftUI.View {
        ForEach(sidebarGrouped, id: \ .folder.id) { group in
            SidebarFolderGroupView(group: group)
        }
    }

    // Helper view for rendering a single folder group
    private func SidebarFolderGroupView(group: (folder: FolderInfo, conversations: [ConversationRecord])) -> some SwiftUI.View {
        let isExpanded = expandedFolders.contains(group.folder.id)
        return Group {
            FolderHeader(folder: group.folder, isExpanded: isExpanded) {
                if isExpanded {
                    expandedFolders.remove(group.folder.id)
                } else {
                    expandedFolders.insert(group.folder.id)
                    updateRecentFolders(with: group.folder.id)
                }
            }
            if isExpanded {
                ForEach(group.conversations, id: \ .id) { convo in
                    let isSelected = selectedConversationId == convo.id
                    HStack {
                        Spacer().frame(width: 18)
                        ConversationRow(convo: convo, isSelected: isSelected) {
                            selectedConversationId = convo.id
                        }
                    }
                }
            }
        }
    }
    // --- Sidebar Data Computed Properties ---
    private var sidebarFolders: [FolderInfo] { fetchAllFolders() }
    private var sidebarFiltered: [ConversationRecord] { filteredConversations() }
    private var sidebarGroupedResult: (grouped: [(folder: FolderInfo, conversations: [ConversationRecord])], ungrouped: [ConversationRecord]) {
        groupConversationsByFolder(conversations: sidebarFiltered, folders: sidebarFolders)
    }
    private var sidebarGrouped: [(folder: FolderInfo, conversations: [ConversationRecord])] { sidebarGroupedResult.grouped }
    private var sidebarUngrouped: [ConversationRecord] { sidebarGroupedResult.ungrouped }

    // --- State properties ---
    @State private var showFileImporter = false
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

    // --- Main View ---
    var body: some SwiftUI.View {
        VStack(spacing: 0) {
            // Top bar
            HStack(alignment: .center, spacing: 0) {
                // Left: Open and Clear Data
                HStack(spacing: 10) {
                    Button(action: {
                        conversations = []
                        selectedConversationId = nil
                        showFileImporter = true
                    }) {
                        Label("Open", systemImage: "folder")
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .background(Color.accentColor.opacity(0.13))
                            .cornerRadius(8)
                    }
                    Button(action: {
                        showClearDataAlert = true
                    }) {
                        Label("Clear Data", systemImage: "trash")
                            .font(.body)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .background(Color.red.opacity(0.13))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                }
                .padding(.leading, 18)
                Spacer()
                // Center: Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, maxWidth: 340)
                        .onSubmit { self.performSearch() }
                    Button(action: { self.performSearch() }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = [:]
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 0)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                .frame(maxWidth: 420)
            }
            .frame(height: 56)
            .background(Color(NSColor.windowBackgroundColor))
            Divider()
            // Main content: two-pane layout
            HStack(spacing: 0) {
                // Sidebar: Only folders and their conversations
                VStack {
                    // Debug prints for sidebar state (removed from ViewBuilder context)
                    List {
                        // Folders as expandable/collapsible
                        if !sidebarGrouped.isEmpty {
                            SidebarFolderGroupsView
                        }
                        // If there are ungrouped conversations and no folders, show them directly (no Section)
                        if sidebarGrouped.isEmpty && !sidebarUngrouped.isEmpty {
                            SidebarUngroupedView
                        }
                        // If there are both folders and ungrouped, show ungrouped in a Section
                        if !sidebarGrouped.isEmpty && !sidebarUngrouped.isEmpty {
                            Section(header: Text("Ungrouped").font(.headline)) {
                                SidebarUngroupedView
                            }
                        }
                        // If there are no folders and no ungrouped, show a placeholder
                        if sidebarGrouped.isEmpty && sidebarUngrouped.isEmpty {
                            Text("No conversations found.")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }

                }
                .frame(width: 250)
                Divider()
                // Central pane
                VStack(alignment: .leading) {
                    if isLoading {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView("Loading conversations...Please wait")
                                .progressViewStyle(CircularProgressViewStyle())
                            Spacer()
                        }
                        Spacer()
                    } else if let convo = selectedConversation {
                        Text(convo.title)
                            .font(.title2)
                            .padding(.bottom, 4)
                        Text("ID: \(convo.id)")
                            .font(.caption)
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
                                CentralMessagesScrollView(messages: messages, searchText: searchText)
                            }
                        }
                    }
                }
                Divider()
                // Right tag panel: Recently used tags, all tags, and add tag
                VStack(alignment: .leading, spacing: 20) {
                    // Tag Filters (show only the selected tag as chip)
                    Text("Tag Filters")
                        .font(.headline)
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                    HStack(spacing: 10) {
                        if let tag = selectedTag, !tag.isEmpty {
                            TagChip(tag: tag, isSelected: true) {
                                selectedTag = nil
                            }
                        } else {
                            Text("(None)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    // Clear Tag Filter Button
                    if selectedTag != nil {
                        Button(action: { selectedTag = nil }) {
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
                    // All Tags
                    Text("All Tags")
                        .font(.headline)
                        .padding(.horizontal, 16)
                    GeometryReader { geo in
                        ScrollView {
                            TagGridView(selectedTag: selectedTag, allTags: allTags) { tag in
                                selectedTag = tag
                            }
                        }
                        .frame(height: max(geo.size.height * 0.5, 120))
                    }
                    // Add Tag Field (horizontal, production look)
                    HStack(spacing: 8) {
                        TextField("Add tag", text: $newTagText)
                            .font(.body)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.gray.opacity(0.13))
                            .cornerRadius(8)
                            .focused($tagFieldFocused)
                            .onSubmit {
                                if let convo = selectedConversation {
                                    self.addTag(newTagText.trimmingCharacters(in: .whitespacesAndNewlines), to: convo)
                                    updateRecentTags(with: newTagText.trimmingCharacters(in: .whitespacesAndNewlines))
                                }
                            }
                        Button(action: {
                            if let convo = selectedConversation {
                                self.addTag(newTagText.trimmingCharacters(in: .whitespacesAndNewlines), to: convo)
                                updateRecentTags(with: newTagText.trimmingCharacters(in: .whitespacesAndNewlines))
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
                    .padding(.bottom, 16)
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
        // Attach all view modifiers to the main VStack
        .alert("Unable to parse file", isPresented: $showInvalidAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if errorDetails.isEmpty {
                Text("The selected file could not be parsed as a ChatGPT conversation JSON file.")
            } else {
                Text(errorDetails)
            }
        }
        .alert("Clear All Data?", isPresented: $showClearDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                SQLiteManager.shared.clearAllData()
                conversations = []
                selectedConversationId = nil
                searchText = ""
                searchResults = [:]
            }
        } message: {
            Text("This will permanently delete your local database, all conversations, tags, and folders. This action cannot be undone. Are you sure you want to proceed?")
        }
        .onAppear {
            loadConversationsFromDB()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                print("[DEBUG] fileImporter: .success, urls=\(urls)")
                guard let url = urls.first else {
                    print("[DEBUG] fileImporter: no url selected")
                    showEmptyAlert = true
                    return
                }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    print("[DEBUG] fileImporter: data read, size=\(data.count)")
                    guard !data.isEmpty else {
                        print("[DEBUG] fileImporter: data is empty")
                        showEmptyAlert = true
                        return
                    }
                    let json = try JSONSerialization.jsonObject(with: data)
                    print("[DEBUG] fileImporter: JSON parsed, type=\(type(of: json))")
                    // Support both {conversations: [...]} and plain array root
                    var conversationsArray: [[String: Any]] = []
                    var foldersArray: [[String: Any]]? = nil
                    if let rootDict = json as? [String: Any], let arr = rootDict["conversations"] as? [[String: Any]], !arr.isEmpty {
                        conversationsArray = arr
                        foldersArray = rootDict["folders"] as? [[String: Any]]
                        print("[DEBUG] JSON root is object, conversations count: \(conversationsArray.count)")
                    } else if let arr = json as? [[String: Any]], !arr.isEmpty,
                              arr.first? ["id"] != nil, arr.first? ["title"] != nil {
                        conversationsArray = arr
                        print("[DEBUG] JSON root is array, conversations count: \(conversationsArray.count)")
                    } else {
                        print("[DEBUG] JSON root is invalid or missing required keys: \(type(of: json))")
                        errorDetails = "The selected file is not a valid ChatGPT conversation export."
                        showInvalidAlert = true
                        return
                    }
                    // Insert folders if present
                    if let foldersArray = foldersArray {
                        for folder in foldersArray {
                            guard let folderId = folder["id"] as? String,
                                  let folderName = folder["name"] as? String else { continue }
                            let conversationIds: [String]
                            if let ids = folder["conversation_ids"] as? [String] {
                                conversationIds = ids
                            } else if let ids = folder["conversation_ids"] as? [Any] {
                                conversationIds = ids.compactMap { $0 as? String }
                            } else {
                                conversationIds = []
                            }
                            SQLiteManager.shared.upsertFolder(id: folderId, name: folderName, conversationIds: conversationIds)
                        }
                    }
                    // Debug: print conversationsArray count and sample
                    print("[DEBUG] conversationsArray count: \(conversationsArray.count)")
                    for (i, dict) in conversationsArray.prefix(3).enumerated() {
                        print("[DEBUG] conversationsArray[\(i)]: \(dict)")
                    }
                    // Insert conversations
                    for dict in conversationsArray {
                        guard let id = dict["id"] as? String,
                              let title = dict["title"] as? String else { continue }
                        let mappingData = try? JSONSerialization.data(withJSONObject: dict["mapping"] ?? [:])
                        let mappingStr = mappingData.flatMap { String(data: $0, encoding: .utf8) }
                        let folderId = dict["folder_id"] as? String
                        let convo = ConversationRecord(
                            id: id,
                            title: title,
                            createTime: dict["create_time"] as? String,
                            updateTime: dict["update_time"] as? String,
                            mapping: mappingStr,
                            tags: [],
                            folderId: folderId
                        )
                        SQLiteManager.shared.upsertConversation(convo)
                        // Insert messages into FTS table
                        if let mapping = dict["mapping"] as? [String: Any] {
                            for (msgId, nodeAny) in mapping {
                                guard let node = nodeAny as? [String: Any],
                                      let message = node["message"] as? [String: Any],
                                      let authorDict = message["author"] as? [String: Any],
                                      let role = authorDict["role"] as? String,
                                      let contentDict = message["content"] as? [String: Any],
                                      let parts = contentDict["parts"] as? [Any],
                                      let text = parts.first as? String else { continue }
                                SQLiteManager.shared.insertMessageFTS(messageId: msgId, conversationId: id, author: role, content: text)
                            }
                        }
                    }
                    // Reload from DB
                    print("[DEBUG] fileImporter: calling loadConversationsFromDB() after import")
                    loadConversationsFromDB()
                    isLoading = false
                } catch {
                    print("[DEBUG] fileImporter: error: \(error)")
                    errorDetails = error.localizedDescription
                    isLoading = false
                    showInvalidAlert = true
                }
            case .failure(let err):
                print("[DEBUG] fileImporter: .failure, error=\(err)")
                showInvalidAlert = true
            }
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
            let idx = pair.offset
            let msg = pair.element
            let isMatch = !lowerSearch.isEmpty && msg.content.lowercased().contains(lowerSearch)
            let isFirstMatch = isMatch && matchIndices.first == idx
            HStack {
                if msg.author == "user" {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isMatch ? Color.yellow.opacity(0.6) : Color.blue.opacity(0.2))
                        highlightText(msg.content, search: lowerSearch)
                            .padding(10)
                    }
                    .frame(maxWidth: 350, alignment: .leading)
                    .id(isFirstMatch ? "firstMatch" : nil)
                    Spacer()
                } else {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isMatch ? Color.yellow.opacity(0.6) : Color.green.opacity(0.2))
                        highlightText(msg.content, search: lowerSearch)
                            .padding(10)
                    }
                    .frame(maxWidth: 1000, alignment: .trailing)
                    .id(isFirstMatch ? "firstMatch" : nil)
                }
            }
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