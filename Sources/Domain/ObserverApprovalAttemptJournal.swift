import Foundation
import SQLite3

/// Local operation identity only. Never stores approval bearer tokens or acts as authority.
/// SQLite's BEGIN IMMEDIATE + unique scope are the cross-process reservation fence.
public struct ObserverApprovalAttemptJournal: Sendable {
    public enum JournalError: Error, Equatable {
        case invalidIdentity
        case conflictingDecision
        case storageFailure(Int32)
        case missingRecord
    }

    public enum Phase: String, Sendable, Equatable {
        case reserved = "RESERVED"
        case submitting = "SUBMITTING"
        case outcomeUnknown = "OUTCOME_UNKNOWN"
        case observed = "OBSERVED" // observation of authoritative status, not proof of attribution
    }

    public struct Record: Sendable, Equatable {
        public let scope: String
        public let approvalID: String
        public let decision: String
        public let attemptID: String
        public let expectedVersion: Int
        public let phase: Phase
        public let observedState: String?
    }

    public let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public static func defaultURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return root.appendingPathComponent("observer-approval-attempts-v1.sqlite")
    }

    public static func scope(baseURL: URL, projectID: String) -> String {
        // Length-framing prevents ambiguous joins and scopes the exact authority origin.
        [baseURL.absoluteString, projectID]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }

    public func claim(scope: String, approvalID: String, decision: String, expectedVersion: Int) throws -> Record {
        guard !scope.isEmpty, !approvalID.isEmpty, (decision == "ALLOW" || decision == "DENY"), expectedVersion > 0 else {
            throw JournalError.invalidIdentity
        }
        return try withDB { db in
            try execute(db, "BEGIN IMMEDIATE")
            var completed = false
            defer { if !completed { try? execute(db, "ROLLBACK") } }
            if let existing = try select(db, scope: scope, approvalID: approvalID) {
                guard existing.decision == decision else { throw JournalError.conflictingDecision }
                try execute(db, "COMMIT")
                completed = true
                return existing
            }
            let attempt = "decision:\(UUID().uuidString.lowercased())"
            try statement(db, "INSERT INTO attempts(scope, approval_id, decision, attempt_id, expected_version, phase) VALUES (?, ?, ?, ?, ?, ?)") { stmt in
                try bind(stmt, 1, scope)
                try bind(stmt, 2, approvalID)
                try bind(stmt, 3, decision)
                try bind(stmt, 4, attempt)
                guard sqlite3_bind_int64(stmt, 5, Int64(expectedVersion)) == SQLITE_OK else { throw JournalError.storageFailure(sqlite3_errcode(db)) }
                try bind(stmt, 6, Phase.reserved.rawValue)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw JournalError.storageFailure(sqlite3_errcode(db)) }
            }
            guard let saved = try select(db, scope: scope, approvalID: approvalID) else { throw JournalError.missingRecord }
            try execute(db, "COMMIT")
            completed = true
            return saved
        }
    }

    public func load(scope: String, approvalID: String) throws -> Record? {
        try withDB { db in try select(db, scope: scope, approvalID: approvalID) }
    }

    /// Acquires exclusive right to perform the first POST for this exact attempt.
    /// Every contender (UI or notification) must call this immediately before sending.
    public func acquireSubmission(scope: String, approvalID: String, attemptID: String) throws -> Bool {
        try withDB { db in
            try execute(db, "BEGIN IMMEDIATE")
            var completed = false
            defer { if !completed { try? execute(db, "ROLLBACK") } }
            let won = try statement(db, "UPDATE attempts SET phase = ? WHERE scope = ? AND approval_id = ? AND attempt_id = ? AND phase = ?") { stmt in
                try bind(stmt, 1, Phase.submitting.rawValue)
                try bind(stmt, 2, scope)
                try bind(stmt, 3, approvalID)
                try bind(stmt, 4, attemptID)
                try bind(stmt, 5, Phase.reserved.rawValue)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw JournalError.storageFailure(sqlite3_errcode(db)) }
                return sqlite3_changes(db) == 1
            }
            try execute(db, "COMMIT")
            completed = true
            return won
        }
    }

    /// Never replace the operation identity. An observed state does not establish which attempt caused it.
    public func transition(scope: String, approvalID: String, attemptID: String, phase: Phase, observedState: String? = nil) throws -> Record {
        try withDB { db in
            try execute(db, "BEGIN IMMEDIATE")
            var completed = false
            defer { if !completed { try? execute(db, "ROLLBACK") } }
            guard let before = try select(db, scope: scope, approvalID: approvalID), before.attemptID == attemptID else {
                throw JournalError.missingRecord
            }
            guard isAllowed(from: before.phase, to: phase) else { throw JournalError.conflictingDecision }
            try statement(db, "UPDATE attempts SET phase = ?, observed_state = ? WHERE scope = ? AND approval_id = ? AND attempt_id = ?") { stmt in
                try bind(stmt, 1, phase.rawValue)
                try bind(stmt, 2, observedState)
                try bind(stmt, 3, scope)
                try bind(stmt, 4, approvalID)
                try bind(stmt, 5, attemptID)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw JournalError.storageFailure(sqlite3_errcode(db)) }
            }
            guard let after = try select(db, scope: scope, approvalID: approvalID) else { throw JournalError.missingRecord }
            try execute(db, "COMMIT")
            completed = true
            return after
        }
    }

    private func isAllowed(from: Phase, to: Phase) -> Bool {
        if from == to { return true }
        switch (from, to) {
        case (.reserved, .submitting), (.reserved, .observed),
             (.submitting, .outcomeUnknown), (.submitting, .observed),
             (.outcomeUnknown, .observed): return true
        default: return false
        }
    }

    private func withDB<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw JournalError.storageFailure(rc)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 3000)
        try execute(db, "PRAGMA journal_mode=DELETE")
        try execute(db, "PRAGMA synchronous=FULL")
        try execute(db, "CREATE TABLE IF NOT EXISTS attempts (scope TEXT NOT NULL, approval_id TEXT NOT NULL, decision TEXT NOT NULL, attempt_id TEXT NOT NULL UNIQUE, expected_version INTEGER NOT NULL, phase TEXT NOT NULL, observed_state TEXT, PRIMARY KEY(scope, approval_id))")
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: databaseURL.path)
        #endif
        return try body(db)
    }

    private func select(_ db: OpaquePointer, scope: String, approvalID: String) throws -> Record? {
        try statement(db, "SELECT scope, approval_id, decision, attempt_id, expected_version, phase, observed_state FROM attempts WHERE scope = ? AND approval_id = ?") { stmt in
            try bind(stmt, 1, scope)
            try bind(stmt, 2, approvalID)
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { return nil }
            guard rc == SQLITE_ROW,
                  let p = Phase(rawValue: col(stmt, 5) ?? ""),
                  let a = col(stmt, 0), let b = col(stmt, 1), let c = col(stmt, 2), let d = col(stmt, 3) else {
                throw JournalError.storageFailure(sqlite3_errcode(db))
            }
            return Record(scope: a, approvalID: b, decision: c, attemptID: d, expectedVersion: Int(sqlite3_column_int64(stmt, 4)), phase: p, observedState: col(stmt, 6))
        }
    }

    private func statement<T>(_ db: OpaquePointer, _ sql: String, _ callback: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw JournalError.storageFailure(rc) }
        defer { sqlite3_finalize(stmt) }
        return try callback(stmt)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        let rc = sqlite3_exec(db, sql, nil, nil, nil)
        guard rc == SQLITE_OK else { throw JournalError.storageFailure(rc) }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) throws {
        let rc = value.map { text in
            text.withCString { sqlite3_bind_text(stmt, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        } ?? sqlite3_bind_null(stmt, index)
        guard rc == SQLITE_OK else { throw JournalError.storageFailure(rc) }
    }

    private func col(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let x = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: x)
    }
}
