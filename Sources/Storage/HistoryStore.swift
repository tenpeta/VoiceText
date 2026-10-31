import Foundation
import SQLite3

struct VoiceRecord: Identifiable, Equatable, Sendable {
    let id: String
    let createdAt: Date
    let provider: String
    let model: String
    let rawText: String
    let finalText: String
}

actor HistoryStore {
    private var database: OpaquePointer?
    private let url: URL
    init(url: URL) { self.url = url }
    deinit { if let database { sqlite3_close(database) } }

    private func open() throws {
        if database != nil { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw storageError
        }
        database = connection
        sqlite3_busy_timeout(connection, 2000)
        try execute("CREATE TABLE IF NOT EXISTS voice_history (id TEXT PRIMARY KEY, created REAL NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL, raw_text TEXT NOT NULL, final_text TEXT NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS voice_history_created ON voice_history(created DESC, id DESC)")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func insert(_ result: ASRResult, id: String = UUID().uuidString) throws -> String {
        try open()
        let sql = "INSERT INTO voice_history VALUES (?, ?, ?, ?, ?, ?)"
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        bind(id, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        bind(result.provider.rawValue, at: 3, to: statement); bind(result.model, at: 4, to: statement)
        bind(result.text, at: 5, to: statement); bind(result.text, at: 6, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw storageError }
        return id
    }

    func update(id: String, finalText: String) throws {
        try open()
        let statement = try prepare("UPDATE voice_history SET final_text = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(finalText, at: 1, to: statement); bind(id, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw storageError }
    }

    func page(offset: Int = 0, limit: Int = 30) throws -> [VoiceRecord] {
        try open()
        let statement = try prepare("SELECT id, created, provider, model, raw_text, final_text FROM voice_history ORDER BY created DESC, id DESC LIMIT ? OFFSET ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(min(100, max(1, limit))))
        sqlite3_bind_int64(statement, 2, Int64(max(0, offset)))
        var records: [VoiceRecord] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            records.append(.init(id: string(statement, 0), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                                 provider: string(statement, 2), model: string(statement, 3),
                                 rawText: string(statement, 4), finalText: string(statement, 5)))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw storageError }
        return records
    }

    func delete(id: String) throws {
        try open()
        let statement = try prepare("DELETE FROM voice_history WHERE id = ?")
        defer { sqlite3_finalize(statement) }; bind(id, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw storageError }
    }
    func clear() throws { try open(); try execute("DELETE FROM voice_history"); try execute("VACUUM") }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw storageError }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw storageError }
        return statement
    }
    private func bind(_ value: String, at position: Int32, to statement: OpaquePointer) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = value.withCString { sqlite3_bind_text(statement, position, $0, -1, transient) }
    }
    private func string(_ statement: OpaquePointer, _ position: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, position) else { return "" }
        return String(cString: bytes)
    }
    private var storageError: VoiceTextError { .message("无法保存或读取语音历史，请检查磁盘空间及目录权限。") }
}
