import GRDB
import InvoicingCore

/// SQLite persistence for FA-mac, built on GRDB. `AppDatabase` opens and migrates the file (schema in
/// `Schema`); the stores (`DocumentStore`, `CustomerStore`, `NumberSeriesStore`, `RateStore`,
/// `ProfileStore`, `StatementStore`, `AuditLog`) are the API the app uses.
public enum InvoicingData {
    /// Highest migration applied by this build.
    public static let schemaVersion = 1
}
