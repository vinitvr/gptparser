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
}

struct ContentView: View {
    @State private var showFileImporter = false
    @State private var showInvalidAlert = false
    @State private var showEmptyAlert = false
    @State private var errorDetails: String = ""
    @State private var conversations: [Conversation] = []
    @State private var selectedConversation: Conversation?
    @State private var isLoading: Bool = false
    @State private var fileLoaded: Bool = false
    
    private let bookmarkKey = "lastConversationFileBookmark"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Open") {
                    conversations = []
                    selectedConversation = nil
                    showFileImporter = true
                }
                .padding()
                Spacer()
            }
            Divider()
            HStack(spacing: 0) {
                // Left sidebar
                List(selection: $selectedConversation) {
                    ForEach(conversations) { convo in
                        Text(convo.title)
                            .padding(.vertical, 4)
                            .background(selectedConversation == convo ? Color.accentColor.opacity(0.2) : Color.clear)
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
                        if let created = convo.create_time {
                            Text("Created: \(created)")
                                .font(.caption)
                        }
                        if let updated = convo.update_time {
                            Text("Updated: \(updated)")
                                .font(.caption)
                        }
                        Divider()
                        if let mapping = convo.mapping {
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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    isLoading = true
                    Task {
                        var didAccess = url.startAccessingSecurityScopedResource()
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
                            let decoder = JSONDecoder()
                            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                            guard let rawArray = jsonObject as? [Any] else {
                                await MainActor.run {
                                    errorDetails = "Root is not a JSON array."
                                    isLoading = false
                                    showInvalidAlert = true
                                }
                                return
                            }
                            let validConvos: [Conversation] = rawArray.compactMap { element in
                                guard let dict = element as? [String: Any],
                                      let id = dict["id"] as? String,
                                      let title = dict["title"] as? String else { return nil }
                                let jsonData = try? JSONSerialization.data(withJSONObject: dict)
                                return (jsonData != nil) ? (try? decoder.decode(Conversation.self, from: jsonData!)) : nil
                            }
                            await MainActor.run {
                                conversations = validConvos
                                selectedConversation = validConvos.first
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
        .onAppear(perform: loadLastFile)
    }
    
    private func loadLastFile() {
        if !fileLoaded {
            if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
                isLoading = true
                Task {
                    var stale = false
                    if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
                        let didAccess = url.startAccessingSecurityScopedResource()
                        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                        do {
                            let data = try Data(contentsOf: url)
                            if data.isEmpty {
                                await MainActor.run {
                                    isLoading = false
                                    showEmptyAlert = true
                                }
                                return
                            }
                            let decoder = JSONDecoder()
                            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                            guard let rawArray = jsonObject as? [Any] else {
                                await MainActor.run {
                                    errorDetails = "Root is not a JSON array."
                                    isLoading = false
                                    showInvalidAlert = true
                                }
                                return
                            }
                            let validConvos: [Conversation] = rawArray.compactMap { element in
                                guard let dict = element as? [String: Any],
                                      let id = dict["id"] as? String,
                                      let title = dict["title"] as? String else { return nil }
                                let jsonData = try? JSONSerialization.data(withJSONObject: dict)
                                return (jsonData != nil) ? (try? decoder.decode(Conversation.self, from: jsonData!)) : nil
                            }
                            await MainActor.run {
                                conversations = validConvos
                                selectedConversation = validConvos.first
                                isLoading = false
                                fileLoaded = true
                            }
                        } catch {
                            await MainActor.run {
                                errorDetails = error.localizedDescription
                                isLoading = false
                                showInvalidAlert = true
                            }
                        }
                    } else {
                        await MainActor.run {
                            isLoading = false
                        }
                    }
                }
            }
        }
    }
}

// SwiftUI Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
