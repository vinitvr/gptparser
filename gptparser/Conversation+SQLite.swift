// Conversation+SQLite.swift
// Helper struct for Conversation and tag CRUD with SQLiteManager

import Foundation
import SQLite

struct ConversationRecord: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let createTime: String?
    let updateTime: String?
    let mapping: String? // JSON string
    var tags: [String] = []
    var folderId: String? = nil
}

// Extend SQLiteManager for CRUD
extension SQLiteManager {
    // Fetch all conversations
    func fetchAllConversations() -> [ConversationRecord] {
        var results: [ConversationRecord] = []
        do {
            for row in try db.prepare(conversations) {
                let convo = ConversationRecord(
                    id: row[id],
                    title: row[title],
                    createTime: row[createTime],
                    updateTime: row[updateTime],
                    mapping: row[mapping],
                    tags: fetchTags(for: row[id]),
                    folderId: row[folderId]
                )
                results.append(convo)
            }
        } catch {
            print("Fetch conversations error: \(error)")
        }
        return results
    }

    // ...existing code...

    // Fetch tags for a conversation
    func fetchTags(for convoId: String) -> [String] {
        var tagsArr: [String] = []
        do {
            let query = conversationTags.filter(conversationId == convoId)
            for row in try db.prepare(query) {
                tagsArr.append(row[tag])
            }
        } catch {
            print("Fetch tags error: \(error)")
        }
        return tagsArr
    }

    // Add a tag
    func addTag(_ tagStr: String, to convoId: String) {
        do {
            let insert = conversationTags.insert(conversationId <- convoId, tag <- tagStr)
            try db.run(insert)
        } catch {
            print("Add tag error: \(error)")
        }
    }

    // Remove a tag
    func removeTag(_ tagStr: String, from convoId: String) {
        do {
            let query = conversationTags.filter(conversationId == convoId && tag == tagStr)
            try db.run(query.delete())
        } catch {
            print("Remove tag error: \(error)")
        }
    }
}
