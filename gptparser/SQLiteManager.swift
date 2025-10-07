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

    // Columns
    let id = Expression<String>("id")
    let title = Expression<String>("title")
    let createTime = Expression<String?>("create_time")
    let updateTime = Expression<String?>("update_time")
    let mapping = Expression<String?>("mapping")

    let tagId = Expression<Int64>("id")
    let conversationId = Expression<String>("conversation_id")
    let tag = Expression<String>("tag")

    private init() {
        let dbPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!.appending("/conversations.sqlite3")
        db = try! Connection(dbPath)
        createTables()
    }

    private func createTables() {
        do {
            try db.run(conversations.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(title)
                t.column(createTime)
                t.column(updateTime)
                t.column(mapping)
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
}
