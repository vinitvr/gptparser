//
//  ContentView.swift
//  gptparser
//
//  Created by Vineeth V R on 06/10/25.
//

import SwiftUI
import UniformTypeIdentifiers


struct Conversation: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let create_time: String?
    let update_time: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, create_time, update_time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.create_time = try? container.decode(String.self, forKey: .create_time)
        self.update_time = try? container.decode(String.self, forKey: .update_time)
    }
}

// Helper to decode unknown JSON structure
struct AnyCodable: Codable {}

struct ContentView: View {
    @State private var showFileImporter = false
    @State private var showInvalidAlert = false
    @State private var showEmptyAlert = false
    @State private var errorDetails: String = ""
    @State private var conversations: [Conversation] = []
    @State private var selectedConversation: Conversation?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Open") {
                    showFileImporter = true
                }
                .padding()
                Spacer()
            }
            Divider()
            HStack(spacing: 0) {
                // Left sidebar
                List(conversations, selection: $selectedConversation) { convo in
                    Text(convo.title)
                        .onTapGesture {
                            selectedConversation = convo
                        }
                }
                .frame(width: 250)
                Divider()
                // Central pane
                VStack(alignment: .leading) {
                    if let convo = selectedConversation {
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
                        // You can expand this to show more details from mapping
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
                    var didAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        if data.isEmpty {
                            showEmptyAlert = true
                            return
                        }
                        let decoder = JSONDecoder()
                        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                        guard let rawArray = jsonObject as? [Any] else {
                            errorDetails = "Root is not a JSON array."
                            showInvalidAlert = true
                            return
                        }
                        let validConvos: [Conversation] = rawArray.compactMap { element in
                            guard let dict = element as? [String: Any],
                                  let id = dict["id"] as? String,
                                  let title = dict["title"] as? String else { return nil }
                            let jsonData = try? JSONSerialization.data(withJSONObject: dict)
                            return (jsonData != nil) ? (try? decoder.decode(Conversation.self, from: jsonData!)) : nil
                        }
                        conversations = validConvos
                        selectedConversation = validConvos.first
                    } catch {
                        errorDetails = error.localizedDescription
                        showInvalidAlert = true
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
}

#Preview {
    ContentView()
}
