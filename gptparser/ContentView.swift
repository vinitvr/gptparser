import SwiftUI
import SQLite
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
        // Use .foregroundColor and .bold for highlight (Text modifiers only)
        result = result + Text(match).foregroundColor(.black).bold()
        currentIndex = range.upperBound
    }
    let after = String(text[currentIndex..<lcText.endIndex])
    if !after.isEmpty { result = result + Text(after) }
    return result
}

// Helper for chat message
struct ChatMessage: Identifiable, Hashable {
    let id: String
    let author: String
    let content: String
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
    // Sort messages by key for now (could use create_time if available)
    return messages.sorted { $0.id < $1.id }
}
//
//  ContentView.swift
//  gptparser
//
//  Created by Vineeth V R on 06/10/25.
// Removed highlightText function and String extension


// Helper to decode unknown JSON structure
struct AnyCodable: Codable, CustomStringConvertible {
    var value: Any

    init(_ value: Any) {
        self.value = value
    }

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

struct ContentView: SwiftUI.View {
    // Explicit public default initializer for use in App
    public init() {}
    // State for expanded/collapsed folders
    @State private var expandedFolders: Set<String> = []

    // State for selected conversation (by id)
    @State private var selectedConversationId: String? = nil

    // Computed property for selected conversation
    private var selectedConversation: ConversationRecord? {
        conversations.first(where: { $0.id == selectedConversationId })
    }

    // State for recent folders (LRU, max 3)
    @State private var recentFolders: [String] = []
    private func updateRecentFolders(with folderId: String) {
        // Remove if already present, then insert at front
        recentFolders.removeAll { $0 == folderId }
        recentFolders.insert(folderId, at: 0)
        // Keep only max 3
        if recentFolders.count > 3 {
            recentFolders = Array(recentFolders.prefix(3))
        }
        // TODO: Persist to SQLite if needed
    }

    // State for recent tags (LRU, max 3)
    @State private var recentTags: [String] = []
    private func updateRecentTags(with tag: String) {
        recentTags.removeAll { $0 == tag }
        recentTags.insert(tag, at: 0)
        if recentTags.count > 3 {
            recentTags = Array(recentTags.prefix(3))
        }
        // TODO: Persist to SQLite if needed
    }
    // Step 1: Data layer helpers for folder/conversation grouping
    struct FolderInfo {
        let id: String
        let name: String
        let conversationIds: [String]
    }

    // Fetch all folders from DB
    func fetchAllFolders() -> [FolderInfo] {
        SQLiteManager.shared.fetchFolders().map { (id, name, conversationIdsJson) in
            let ids: [String]
            if let data = conversationIdsJson.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                ids = arr
            } else {
                ids = []
            }
            return FolderInfo(id: id, name: name, conversationIds: ids)
        }
    }

    // Group conversations by folderId
    func groupConversationsByFolder(conversations: [ConversationRecord], folders: [FolderInfo]) -> ([(folder: FolderInfo, conversations: [ConversationRecord])], [ConversationRecord]) {
        var folderMap: [String: [ConversationRecord]] = [:]
        var ungrouped: [ConversationRecord] = []
        for convo in conversations {
            if let fid = convo.folderId, !fid.isEmpty {
                folderMap[fid, default: []].append(convo)
            } else {
                ungrouped.append(convo)
            }
        }
        let grouped = folders.map { folder in
            (folder: folder, conversations: folderMap[folder.id] ?? [])
        }
        return (grouped, ungrouped)
    }
    // Returns conversations filtered by search results if search is active, otherwise all conversations
    func filteredConversations() -> [ConversationRecord] {
        if !searchText.isEmpty && !searchResults.isEmpty {
            let filtered = conversations.filter { searchResults[$0.id] != nil }
            print("[DEBUG] filteredConversations: searchText=\(searchText), filtered count=\(filtered.count)")
            return filtered
        } else {
            print("[DEBUG] filteredConversations: returning all conversations (count=\(conversations.count))")
            return conversations
        }
    }
    @State private var showFileImporter = false
    @State private var showInvalidAlert = false
    @State private var showEmptyAlert = false
    @State private var errorDetails: String = ""
    // ...existing code...
    @State private var conversations: [ConversationRecord] = []
    // Remove old selectedConversation state
    @State private var isLoading: Bool = false
    @State private var fileLoaded: Bool = false
    @State private var newTagText: String = ""
    
    @FocusState private var tagFieldFocused: Bool
    @State private var tagError: String?
    @State private var searchText: String = ""
    @State private var searchResults: [String: (content: String, score: Double)] = [:]
    
    // MARK: - Tagging helpers
    func addTag(_ tag: String, to convo: ConversationRecord) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        if convo.tags.contains(trimmed) {
            tagError = "Tag already exists."
            newTagText = ""
            return
        }
        SQLiteManager.shared.addTag(trimmed, to: convo.id)
        self.reloadSelectedConversationTags()
        newTagText = ""
        tagFieldFocused = true
    }
    
    func removeTag(_ tag: String, from convo: ConversationRecord) {
        SQLiteManager.shared.removeTag(tag, from: convo.id)
        self.reloadSelectedConversationTags()
    }
    
    func reloadSelectedConversationTags() {
        guard let convo = selectedConversation else { return }
        let updatedTags = SQLiteManager.shared.fetchTags(for: convo.id)
        if let idx = conversations.firstIndex(where: { $0.id == convo.id }) {
            conversations[idx].tags = updatedTags
            // No need to assign to selectedConversation; computed property will update automatically
        }
    }
    // MARK: - Search functionality
    func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[DEBUG] performSearch called. searchText=\(searchText), trimmed=\(trimmed)")
        if trimmed.isEmpty {
            print("[DEBUG] Search text is empty. Clearing searchResults.")
            searchResults = [:]
            return
        }
        var query = trimmed
        // If the search contains spaces, treat as a phrase search
        if query.contains(" ") {
            query = "\"" + query + "\""
        }
        print("[DEBUG] FTS query (no wildcards): \(query)")
        let ftsResults = SQLiteManager.shared.searchMessagesFTS(query: query)
        print("[DEBUG] FTS returned \(ftsResults.count) results.")
        // Collect conversation IDs from FTS
        let ftsConversationIds = Set(ftsResults.map { $0.conversationId })
        // Collect conversation IDs from title search (case-insensitive contains)
        let titleConversationIds = Set(conversations.filter { $0.title.lowercased().contains(trimmed) }.map { $0.id })
        // Union of both
    _ = ftsConversationIds.union(titleConversationIds)
        var resultsDict: [String: (content: String, score: Double)] = [:]
        // For FTS matches, store the first matching message content
        for result in ftsResults {
            if resultsDict[result.conversationId] == nil {
                resultsDict[result.conversationId] = (content: result.content, score: 1.0)
            }
        }
        // For title matches only, store empty content
        for id in titleConversationIds where resultsDict[id] == nil {
            resultsDict[id] = (content: "", score: 1.0)
        }
        print("[DEBUG] searchResults keys: \(resultsDict.keys)")
        searchResults = resultsDict
    }
    
    var body: some SwiftUI.View {
        let dbPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!.appending("/conversations.sqlite3")
    VStack(spacing: 0) {
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
                var didAccess = url.startAccessingSecurityScopedResource()
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
                    // Robustly support both {conversations: [...]} and plain array root
                    var conversationsArray: [[String: Any]] = []
                    var foldersArray: [[String: Any]]? = nil
                    if let rootDict = json as? [String: Any], let arr = rootDict["conversations"] as? [[String: Any]] {
                        conversationsArray = arr
                        foldersArray = rootDict["folders"] as? [[String: Any]]
                        print("[DEBUG] JSON root is object, conversations count: \(conversationsArray.count)")
                    } else if let arr = json as? [[String: Any]] {
                        conversationsArray = arr
                        print("[DEBUG] JSON root is array, conversations count: \(conversationsArray.count)")
                    } else {
                        print("[DEBUG] JSON root is invalid: \(type(of: json))")
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
            // Top bar: Open button, search bar, and tag UI
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DB Path:")

                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(dbPath)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button("Open") {
                        conversations = []
                        selectedConversationId = nil
                        showFileImporter = true
                    }
                    Button("Clear Data") {
                        SQLiteManager.shared.clearAllData()
                        conversations = []
                        selectedConversationId = nil
                    }
                    .foregroundColor(.red)
                }
                .padding(.vertical)
                // Search bar
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: 260)
                        .onSubmit { self.performSearch() }
                    Button(action: { self.performSearch() }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.accentColor)
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
                    // Tag chips for selected conversation
                    if let convo = selectedConversation {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(convo.tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(10)
                                        Button(action: {
                                            self.removeTag(tag, from: convo)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                // Add tag field
                                HStack(spacing: 4) {
                                    TextField("Add tag", text: $newTagText)
                                        .font(.caption)
                                        .frame(minWidth: 60, maxWidth: 100)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($tagFieldFocused)
                                        .onSubmit {
                                            self.addTag(newTagText.trimmingCharacters(in: .whitespacesAndNewlines), to: convo)
                                        }
                                    Button(action: {
                                        self.addTag(newTagText.trimmingCharacters(in: .whitespacesAndNewlines), to: convo)
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(height: 32)
                    }
                    Spacer()
                }
                Divider()
                // Main content: two-pane layout
                HStack(spacing: 0) {
                    // Sidebar: Only folders and their conversations
                    List {
                        let folders = fetchAllFolders()
                        let (grouped, ungrouped) = groupConversationsByFolder(conversations: filteredConversations(), folders: folders)
                        // Folders as expandable/collapsible
                        ForEach(grouped, id: \.folder.id) { group in
                            // Folder header (expand/collapse on tap)
                            HStack {
                                Image(systemName: expandedFolders.contains(group.folder.id) ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.accentColor)
                                Text(group.folder.name)
                                    .font(.headline)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if expandedFolders.contains(group.folder.id) {
                                    expandedFolders.remove(group.folder.id)
                                } else {
                                    expandedFolders.insert(group.folder.id)
                                    updateRecentFolders(with: group.folder.id)
                                }
                            }
                            // Conversations under folder
                            if expandedFolders.contains(group.folder.id) {
                                ForEach(group.conversations, id: \.id) { convo in
                                    let isSelected = selectedConversationId == convo.id
                                    HStack {
                                        Spacer().frame(width: 18)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(convo.title)
                                                .fontWeight(isSelected ? .bold : .regular)
                                            if !convo.tags.isEmpty {
                                                HStack(spacing: 4) {
                                                    ForEach(convo.tags, id: \.self) { tag in
                                                        Text(tag)
                                                            .font(.caption2)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.gray.opacity(0.15))
                                                            .cornerRadius(8)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 3)
                                        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                                        .cornerRadius(6)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedConversationId = convo.id
                                    }
                                }
                            }
                        }
                        // Ungrouped conversations at the bottom
                        if !ungrouped.isEmpty {
                            Section(header: Text("Ungrouped").font(.headline)) {
                                ForEach(ungrouped, id: \.id) { convo in
                                    let isSelected = selectedConversationId == convo.id
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(convo.title)
                                            .fontWeight(isSelected ? .bold : .regular)
                                        if !convo.tags.isEmpty {
                                            HStack(spacing: 4) {
                                                ForEach(convo.tags, id: \.self) { tag in
                                                    Text(tag)
                                                        .font(.caption2)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.gray.opacity(0.15))
                                                        .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 3)
                                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                                    .cornerRadius(6)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedConversationId = convo.id
                                    }
                                }
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
                                    ScrollViewReader { scrollProxy in
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 12) {
                                                let lowerSearch = searchText.lowercased()
                                                let matchIndices = !lowerSearch.isEmpty ? messages.enumerated().compactMap { idx, msg in msg.content.lowercased().contains(lowerSearch) ? idx : nil } : []
                                                ForEach(Array(messages.enumerated()), id: \.offset) { pair in
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
                                            .padding(.top, 8)
                                            .onAppear {
                                                withAnimation {
                                                    scrollProxy.scrollTo("firstMatch", anchor: .center)
                                                }
                                            }
                                        }
                                    }
                                }
                                // ...existing code...
                            }
                        }
                    }
                }
            }
        }

// Helper to reload conversations from DB (outside the view body)
private extension ContentView {
    func loadConversationsFromDB() {
        conversations = SQLiteManager.shared.fetchAllConversations()
        print("[DEBUG] loadConversationsFromDB: loaded \(conversations.count) conversations")
        for convo in conversations {
            print("[DEBUG] convo: id=\(convo.id), title=\(convo.title), folderId=\(String(describing: convo.folderId)), tags=\(convo.tags)")
        }
        if let first = conversations.first {
            selectedConversationId = first.id
        }
    }
}
                                

