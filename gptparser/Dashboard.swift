import SwiftUI

// Import the modal and manager
import MarkdownUI
// FileManagerHelper and FileImportModalView are in FileManager.swift

struct Dashboard: View {
    @StateObject private var fileManagerHelper = FileManagerHelper()
    // Minimal state for now; will expand as we wire up more logic
    // MARK: - Parameters (incrementally add more as needed)
    @Binding var conversations: [ConversationRecord]
    var sidebarGrouped: [(folder: FolderInfo, conversations: [ConversationRecord])]
    var sidebarUngrouped: [ConversationRecord]
    @Binding var expandedFolders: Set<String>
    @Binding var selectedConversationId: String?
    var onSelectConversation: (String) -> Void
    var onToggleFolder: (String) -> Void

    // File import and modal state
    @State private var showFileImporter = false
    @State private var showOpenFileWarning = false
    @State private var showClearDataAlert = false
    @State private var showLoadingModal = false
    @State private var showInvalidAlert = false
    @State private var showFileLoadedAlert = false
    @State private var errorDetails: String = ""
    @State private var isLoading: Bool = false

    // Search state
    @State private var searchText: String = ""

    // File import handler
    private func handleImportTapped() {
        if conversations.isEmpty {
            showFileImporter = true
        } else {
            showOpenFileWarning = true
        }
    }

    private func handleClearTapped() {
        showClearDataAlert = true
    }
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top bar
                HStack(alignment: .center, spacing: 0) {
                    // Left: Open and Clear Data
                    HStack(spacing: 10) {
                        Button(action: handleImportTapped) {
                            Label("Import Conversations", systemImage: "folder")
                                .font(.body)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .background(Color.accentColor.opacity(0.13))
                                .cornerRadius(8)
                        }
                        .alert(isPresented: $showOpenFileWarning) {
                            Alert(
                                title: Text("Open New File?"),
                                message: Text("Opening a new file will overwrite the current database. All existing conversations, tags, and folders will be lost. You will need to recreate your tags and folder structure. Continue?"),
                                primaryButton: .destructive(Text("Open")) {
                                    showFileImporter = true
                                },
                                secondaryButton: .cancel()
                            )
                        }
                        Button(action: handleClearTapped) {
                            Label("Clear Data", systemImage: "trash")
                                .font(.body)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 14)
                                .background(Color.red.opacity(0.13))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                        .disabled(conversations.isEmpty)
                        .alert(isPresented: $showClearDataAlert) {
                            Alert(
                                title: Text("Clear All Data?"),
                                message: Text("This will permanently delete your local database, all conversations, tags, and folders. This action cannot be undone. Are you sure you want to proceed?"),
                                primaryButton: .destructive(Text("Delete Everything")) {
                                    fileManagerHelper.clearData { newConvos in
                                        conversations = newConvos
                                        showClearDataAlert = false
                                    }
                                },
                                secondaryButton: .cancel()
                            )
                        }
                    }
                    .padding(.leading, 18)
                    Spacer()
                    // Center: Search bar (wired to state)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search conversations...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220, maxWidth: 340)
                        Button(action: { /* TODO: Implement search action if needed */ }) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.title3)
                        }
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .disabled(searchText.isEmpty)
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
                    // Sidebar: Folders and conversations (unchanged)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Imported Conversations")
                            .font(.headline)
                            .padding(.leading, 16)
                            .padding(.top, 8)
                        List {
                            // Folders as expandable/collapsible
                            if !sidebarGrouped.isEmpty {
                                ForEach(sidebarGrouped, id: \ .folder.id) { group in
                                    VStack(alignment: .leading, spacing: 0) {
                                        HStack {
                                            Button(action: { onToggleFolder(group.folder.id) }) {
                                                Image(systemName: expandedFolders.contains(group.folder.id) ? "chevron.down" : "chevron.right")
                                                    .foregroundColor(.accentColor)
                                            }
                                            Text(group.folder.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.leading, 4)
                                        if expandedFolders.contains(group.folder.id) {
                                            ForEach(group.conversations, id: \ .id) { convo in
                                                let isSelected = selectedConversationId == convo.id
                                                HStack {
                                                    Spacer().frame(width: 18)
                                                    Text(convo.title)
                                                        .font(.body)
                                                        .foregroundColor(isSelected ? .accentColor : .primary)
                                                        .onTapGesture { onSelectConversation(convo.id) }
                                                }
                                                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                                .cornerRadius(8)
                                            }
                                        }
                                    }
                                }
                            }
                            // If there are ungrouped conversations and no folders, show them directly (no Section)
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
                            // If there are both folders and ungrouped, show ungrouped in a Section
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
                    }
                    .frame(width: 250)
                    // Central pane placeholder
                    VStack(alignment: .center) {
                        Spacer()
                        Text("Dashboard Main Content")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            // ...existing code...
            // File Importer (native document picker)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        showLoadingModal = true
                        fileManagerHelper.importFile(url: url) { importResult in
                            showLoadingModal = false
                            switch importResult {
                            case .success(let newConvos):
                                conversations = newConvos
                                showFileLoadedAlert = true
                            case .failure(let error):
                                errorDetails = error.localizedDescription
                                showInvalidAlert = true
                            }
                        }
                    }
                case .failure(let error):
                    errorDetails = error.localizedDescription
                    showInvalidAlert = true
                }
            }
            // Loading modal overlay
            .overlay(
                Group {
                    if showLoadingModal {
                        ZStack {
                            Color.black.opacity(0.2).edgesIgnoringSafeArea(.all)
                            VStack(spacing: 20) {
                                ProgressView("Importing conversations...Please wait")
                                    .progressViewStyle(CircularProgressViewStyle())
                                Button("Cancel") { showLoadingModal = false }
                            }
                            .padding(32)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.windowBackgroundColor)))
                            .shadow(radius: 10)
                        }
                    }
                }
            )
            // Alert for invalid file
            .alert("Unable to parse file", isPresented: $showInvalidAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if errorDetails.isEmpty {
                    Text("The selected file could not be parsed as a ChatGPT conversation JSON file.")
                } else {
                    Text(errorDetails)
                }
            }
            // Alert for successful import
            .alert("Conversations Imported", isPresented: $showFileLoadedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your conversations have been successfully imported.")
            }
        }
    }
}

struct Dashboard_Previews: PreviewProvider {
    static var previews: some View {
        Dashboard(
            conversations: .constant([]),
            sidebarGrouped: [],
            sidebarUngrouped: [],
            expandedFolders: .constant([]),
            selectedConversationId: .constant(nil),
            onSelectConversation: { _ in },
            onToggleFolder: { _ in }
        )
    }
}
