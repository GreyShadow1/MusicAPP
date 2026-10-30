import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message):
            return String(localized: "Errore del database: \(message)")
        }
    }
}

enum SQLiteValue {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
}

/// Riga di un risultato, valida solo durante la lettura.
struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func text(_ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    func optionalText(_ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    func integer(_ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    func real(_ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }
}

/// Involucro minimo della API C di SQLite. Non è thread-safe: la sincronizzazione
/// è compito di `PersistenceManager`.
final class SQLiteDatabase {
    /// Equivalente di SQLITE_TRANSIENT, che Swift non importa: SQLite copia il valore.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var handle: OpaquePointer?

    init(path: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
            sqlite3_close(opened)
            throw DatabaseError.failure(message)
        }
        handle = opened
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw lastError()
        }
    }

    func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    func query<Result>(_ sql: String, _ values: [SQLiteValue] = [], map: (SQLiteRow) -> Result) throws -> [Result] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }

        var results: [Result] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                results.append(map(SQLiteRow(statement: statement)))
            } else if step == SQLITE_DONE {
                return results
            } else {
                throw lastError()
            }
        }
    }

    /// Esegue tutto o niente: una chiusura improvvisa non lascia dati a metà.
    func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ values: [SQLiteValue]) throws -> OpaquePointer {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
            throw lastError()
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .integer(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                result = sqlite3_bind_double(statement, index, number)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw lastError()
            }
        }
        return statement
    }

    private func lastError() -> DatabaseError {
        DatabaseError.failure(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database chiuso")
    }
}
