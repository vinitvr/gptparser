// SQLiteManager.swift
// Handles all SQLite operations for conversations and tags
// Uses SQLite.swift (add via Swift Package Manager)

import Foundation
import SQLite

class SQLiteManager {
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
        } catch {
            print("SQLite table creation error: \(error)")
        }
    }

    // Add more CRUD methods here for conversations and tags
}
