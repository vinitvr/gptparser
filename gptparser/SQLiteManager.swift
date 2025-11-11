// ...existing code...

extension SQLiteManager {
    // Fetch all folders for debugging/verification
    func fetchFolders() -> [(id: String, name: String, conversationIdsJson: String)] {
        var results: [(id: String, name: String, conversationIdsJson: String)] = []
        do {
            let conversationIdsCol = Expression<String>("conversation_ids")
            for row in try db.prepare(folders) {
                let folderId = row[folder_id]
                let folderName = row[folder_name]
                let conversationIdsJson = row[conversationIdsCol]
                results.append((id: folderId, name: folderName, conversationIdsJson: conversationIdsJson))
            }
        } catch {
            print("Fetch folders error: \(error)")
        }
        return results
    }
}
// ...existing code...

extension SQLiteManager {
    // Clear all folders and conversations (for testing)
    func clearAllData() {
        do {
            try db.run(conversations.delete())
            try db.run(folders.delete())
            try db.run(conversationTags.delete())
            // Optionally clear FTS table
            try db.execute("DELETE FROM messages_fts;")
        } catch {
            print("SQLite clearAllData error: \(error)")
        }
    }
}
// SQLiteManager.swift
// Handles all SQLite operations for conversations and tags
// Uses SQLite.swift (add via Swift Package Manager)

import Foundation
import SQLite

class SQLiteManager {
    // Search messages using FTS5 and return matching conversation IDs and message snippets
    struct FTSSearchResult {
        let conversationId: String
        let messageId: String
        let author: String
        let content: String
    }

    func searchMessagesFTS(query: String) -> [FTSSearchResult] {
        var results: [FTSSearchResult] = []
        let sql = "SELECT conversation_id, message_id, author, content FROM messages_fts WHERE messages_fts MATCH ?;"
        do {
            for row in try db.prepare(sql, query) {
                if let convoId = row[0] as? String,
                   let msgId = row[1] as? String,
                   let author = row[2] as? String,
                   let content = row[3] as? String {
                    results.append(FTSSearchResult(conversationId: convoId, messageId: msgId, author: author, content: content))
                }
            }
        } catch {
            print("FTS search error: \(error)")
        }
        return results
    }
    
    // Insert a message into the FTS table
    func insertMessageFTS(messageId: String, conversationId: String, author: String, content: String) {
        let insertSQL = "INSERT INTO messages_fts (message_id, conversation_id, author, content) VALUES (?, ?, ?, ?);"
        do {
            try db.run(insertSQL, messageId, conversationId, author, content)
        } catch {
            print("FTS insert error: \(error)")
        }
    }
    static let shared = SQLiteManager()
    let db: Connection

    // Table definitions
    let conversations = Table("conversations")
    let conversationTags = Table("conversation_tags")
    let folders = Table("folders")

    // Columns
    let id = Expression<String>("id")
    let title = Expression<String>("title")
    let createTime = Expression<String?>("create_time")
    let updateTime = Expression<String?>("update_time")
    let mapping = Expression<String?>("mapping")
    let folderId = Expression<String?>("folder_id") // NEW: nullable folder id for conversations

    // Folders table columns
    let folder_id = Expression<String>("id")
    let folder_name = Expression<String>("name")

    let tagId = Expression<Int64>("id")
    let conversationId = Expression<String>("conversation_id")
    let tag = Expression<String>("tag")

    private init() {
        let dbPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!.appending("/conversations.sqlite3")
        db = try! Connection(dbPath)
        migrateIfNeeded()
        createTables()
    }

    // Migration: add folder_id column to conversations if missing
    private func migrateIfNeeded() {
        do {
            let pragma = try db.prepare("PRAGMA table_info(conversations);")
            var hasFolderId = false
            for row in pragma {
                if let name = row[1] as? String, name == "folder_id" {
                    hasFolderId = true
                    break
                }
            }
            if !hasFolderId {
                try db.run("ALTER TABLE conversations ADD COLUMN folder_id TEXT;")
                print("Migrated: Added folder_id column to conversations table.")
            }
        } catch {
            print("Migration error: \(error)")
        }
    }

    private func createTables() {
        do {
            // Conversations table with folder_id
            try db.run(conversations.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(title)
                t.column(createTime)
                t.column(updateTime)
                t.column(mapping)
                t.column(folderId) // NEW
            })
            // Folders table
            try db.run(folders.create(ifNotExists: true) { t in
                t.column(folder_id, primaryKey: true)
                t.column(folder_name)
            })
            try db.run(conversationTags.create(ifNotExists: true) { t in
                t.column(tagId, primaryKey: .autoincrement)
                t.column(conversationId)
                t.column(tag)
                t.unique(conversationId, tag)
            })
            // Create FTS5 table for messages (if not exists)
            let createFTS = """
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                message_id,
                conversation_id,
                author,
                content
            );
            """
            try db.execute(createFTS)
        } catch {
            print("SQLite table creation error: \(error)")
        }
    }

    // Add more CRUD methods here for conversations and tags

    // Upsert (insert or update) a folder
    func upsertFolder(id: String, name: String, conversationIds: [String] = []) {
        print("[DEBUG] upsertFolder called with id=\(id), name=\(name), conversationIds=\(conversationIds)")
        let conversationIdsJson: String
        do {
            let data = try JSONSerialization.data(withJSONObject: conversationIds, options: [])
            conversationIdsJson = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            conversationIdsJson = "[]"
        }
        do {
            let insert = folders.insert(or: .replace,
                folder_id <- id,
                folder_name <- name,
                Expression<String>("conversation_ids") <- conversationIdsJson
            )
            let rowId = try db.run(insert)
            print("[DEBUG] upsertFolder success, rowId=\(rowId)")
        } catch {
            print("[DEBUG] SQLite upsertFolder error: \(error)")
        }
    }

    // Upsert (insert or update) a conversation, including folderId
    func upsertConversation(_ convo: ConversationRecord) {
        do {
            let insert = conversations.insert(or: .replace,
                id <- convo.id,
                title <- convo.title,
                createTime <- convo.createTime,
                updateTime <- convo.updateTime,
                mapping <- convo.mapping,
                folderId <- convo.folderId
            )
            try db.run(insert)
        } catch {
            print("SQLite upsertConversation error: \(error)")
        }
    }
}
