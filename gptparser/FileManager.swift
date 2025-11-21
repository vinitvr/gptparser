import SwiftUI

struct FileImportModalView: View {
    @Binding var isPresented: Bool
    @Binding var isLoading: Bool
    @Binding var errorDetails: String?
    var onImport: (URL) -> Void
    var onCancel: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            if isLoading {
                ProgressView("Importing...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                Text("Import a conversation file")
                    .font(.headline)
                if let error = errorDetails {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                HStack(spacing: 16) {
                    Button("Cancel") { onCancel() }
                    Button("Import") {
                        // The actual file import will be triggered by .fileImporter in the parent
                    }
                }
            }
        }
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.windowBackgroundColor)))
        .shadow(radius: 10)
    }
}

class FileManagerHelper: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorDetails: String? = nil
    func importFile(url: URL, completion: @escaping (Result<[ConversationRecord], Error>) -> Void) {
        isLoading = true
        errorDetails = nil
        print("[DEBUG] importFile: Starting import from \(url)")
        DispatchQueue.global(qos: .userInitiated).async {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                print("[DEBUG] importFile: Read \(data.count) bytes from file")
                // Try to parse as array or {conversations: [...]}
                var conversationsArray: [[String: Any]] = []
                if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    conversationsArray = arr
                    print("[DEBUG] importFile: JSON root is array, count=\(conversationsArray.count)")
                } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let arr = dict["conversations"] as? [[String: Any]] {
                    conversationsArray = arr
                    print("[DEBUG] importFile: JSON root is object, conversations count=\(conversationsArray.count)")
                } else {
                    throw NSError(domain: "FileManagerHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "File is not a valid ChatGPT export (array or {conversations: [...]})"])
                }
                // Clear existing data before import
                SQLiteManager.shared.clearAllData()
                print("[DEBUG] importFile: Cleared all data in DB")
                var imported: [ConversationRecord] = []
                for dict in conversationsArray {
                    guard let id = dict["id"] as? String,
                          let title = dict["title"] as? String else { continue }
                    let mappingStr: String? = {
                        if let mapping = dict["mapping"] as? String {
                            return mapping
                        } else if let mappingDict = dict["mapping"] as? [String: Any],
                                  let mappingData = try? JSONSerialization.data(withJSONObject: mappingDict),
                                  let str = String(data: mappingData, encoding: .utf8) {
                            return str
                        } else {
                            return nil
                        }
                    }()
                    let createTime = dict["create_time"] as? String
                    let updateTime = dict["update_time"] as? String
                    let folderId = dict["folder_id"] as? String
                    let convo = ConversationRecord(
                        id: id,
                        title: title,
                        createTime: createTime,
                        updateTime: updateTime,
                        mapping: mappingStr,
                        tags: [],
                        folderId: folderId
                    )
                    print("[DEBUG] importFile: Upserting conversation id=\(convo.id), title=\(convo.title)")
                    SQLiteManager.shared.upsertConversation(convo)
                    imported.append(convo)
                }
                let allConvos = SQLiteManager.shared.fetchAllConversations()
                print("[DEBUG] importFile: DB now has \(allConvos.count) conversations")
                DispatchQueue.main.async {
                    self.isLoading = false
                    completion(.success(allConvos))
                }
            } catch {
                print("[DEBUG] importFile: Error during import: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorDetails = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    func clearData(completion: @escaping ([ConversationRecord]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            SQLiteManager.shared.clearAllData()
            let allConvos = SQLiteManager.shared.fetchAllConversations()
            DispatchQueue.main.async {
                completion(allConvos)
            }
        }
    }
}
