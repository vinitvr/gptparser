import SQLite

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
//

import SwiftUI
import UniformTypeIdentifiers


struct Conversation: Identifiable, Decodable {
    let id: String
    let title: String
    let create_time: String?
    let update_time: String?
    let mapping: [String: AnyCodable]?

    private enum CodingKeys: String, CodingKey {
        case id, title, create_time, update_time, mapping
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.create_time = try? container.decode(String.self, forKey: .create_time)
        self.update_time = try? container.decode(String.self, forKey: .update_time)
        self.mapping = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .mapping)
    }
}

extension Conversation: Hashable, Equatable {
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
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
// End of AnyCodable
}

struct ContentView: SwiftUI.View {
    // Returns conversations filtered by search results if search is active, otherwise all conversations
    func filteredConversations() -> [ConversationRecord] {
        if !searchText.isEmpty && !searchResults.isEmpty {
            // Only show conversations that have a search result
            return conversations.filter { searchResults[$0.id] != nil }
        } else {
            return conversations
        }
    }
    @State private var showFileImporter = false
    @State private var showInvalidAlert = false
    @State private var showEmptyAlert = false
    @State private var errorDetails: String = ""
    @State private var conversations: [ConversationRecord] = []
    @State private var selectedConversation: ConversationRecord?
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
            selectedConversation = conversations[idx]
        }
    }
    // MARK: - Search functionality
    func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchResults = [:]
            return
        }
        let ftsResults = SQLiteManager.shared.searchMessagesFTS(query: trimmed)
        var resultsDict: [String: (content: String, score: Double)] = [:]
        for result in ftsResults {
            // Only show the first matching message per conversation
            if resultsDict[result.conversationId] == nil {
                resultsDict[result.conversationId] = (content: result.content, score: 1.0)
            }
        }
        searchResults = resultsDict
    }
    
    var body: some SwiftUI.View {
        VStack(spacing: 0) {
            // Top bar: Open button, search bar, and tag UI
            HStack(alignment: .center, spacing: 12) {
                Button("Open") {
                    conversations = []
                    selectedConversation = nil
                    showFileImporter = true
                }
                .padding(.vertical)
                // Search bar
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: 260)
                        .onChange(of: searchText) { self.performSearch() }
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
                    // Left sidebar
                    List(selection: $selectedConversation) {
                        let filtered = self.filteredConversations()
                            ForEach(filtered, id: \.id) { convo in
                            let isSelected = selectedConversation == convo
                            let isSearchResult = searchResults[convo.id] != nil
                            VStack(alignment: .leading, spacing: 2) {
                                Text(convo.title)
                                    .fontWeight(isSearchResult ? .bold : .regular)
                                if let result = searchResults[convo.id], !searchText.isEmpty {
                                    Text(result.content)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                            .onTapGesture {
                                selectedConversation = convo
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
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ForEach(messages) { msg in
                                                HStack {
                                                    if msg.author == "user" {
                                                        Text(msg.content)
                                                            .padding(10)
                                                            .background(Color.blue.opacity(0.2))
                                                            .cornerRadius(12)
                                                            .frame(maxWidth: 350, alignment: .leading)
                                                        Spacer()
                                                    } else {
                                                        Spacer()
                                                        Text(msg.content)
                                                            .padding(10)
                                                            .background(Color.green.opacity(0.2))
                                                            .cornerRadius(12)
                                                            .frame(maxWidth: 1000, alignment: .trailing)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            } else {
                                Text("No conversation content available.")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Select a conversation from the left pane.")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    Spacer()
                }
            }
            .onAppear(perform: loadConversationsFromDB)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        isLoading = true
                        Task {
                            let didAccess = url.startAccessingSecurityScopedResource()
                            defer {
                                if didAccess { url.stopAccessingSecurityScopedResource() }
                            }
                            do {
                                let data = try Data(contentsOf: url)
                                if data.isEmpty {
                                    await MainActor.run {
                                        isLoading = false
                                        showEmptyAlert = true
                                    }
                                    return
                                }
                                let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                                guard let rawArray = jsonObject as? [Any] else {
                                    await MainActor.run {
                                        errorDetails = "Root is not a JSON array."
                                        isLoading = false
                                        showInvalidAlert = true
                                    }
                                    return
                                }
                                for element in rawArray {
                                    guard let dict = element as? [String: Any],
                                          let id = dict["id"] as? String,
                                          let title = dict["title"] as? String else { continue }
                                    let mappingData = try? JSONSerialization.data(withJSONObject: dict["mapping"] ?? [:])
                                    let mappingStr = mappingData.flatMap { String(data: $0, encoding: .utf8) }
                                    let convo = ConversationRecord(
                                        id: id,
                                        title: title,
                                        createTime: dict["create_time"] as? String,
                                        updateTime: dict["update_time"] as? String,
                                        mapping: mappingStr,
                                        tags: []
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
                                await MainActor.run {
                                    loadConversationsFromDB()
                                    isLoading = false
                                }
                            } catch {
                                await MainActor.run {
                                    errorDetails = error.localizedDescription
                                    isLoading = false
                                    showInvalidAlert = true
                                }
                            }
                        }
                    }
                case .failure(_):
                    showInvalidAlert = true
                }
            }
            .alert("File is empty", isPresented: $showEmptyAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The selected file is empty.")
            }
            .alert("Unable to parse file", isPresented: $showInvalidAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if errorDetails.isEmpty {
                    Text("The selected file could not be parsed as a ChatGPT conversation JSON file.")
                } else {
                    Text("The selected file could not be parsed as a ChatGPT conversation JSON file.\nError: \(errorDetails)")
                }
            }
        }
        
        private func loadConversationsFromDB() {
            conversations = SQLiteManager.shared.fetchAllConversations()
            if let first = conversations.first {
                selectedConversation = first
            }
        }
    }
