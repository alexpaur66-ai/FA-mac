import GRDB
import InvoicingCore

/// SQLite persistence for FA-mac, built on GRDB. `AppDatabase` opens and migrates the file (schema in
/// `Schema`); the stores (`DocumentStore`, `CustomerStore`, `NumberSeriesStore`, `RateStore`,
/// `ProfileStore`, `StatementStore`, `StockStore`, `ExportStore`, `ClientNoteStore`, `AuditLog`) are the API the app uses; `DocumentStore` also keeps the PDF of each issued document.
public enum InvoicingData {
    /// Highest migration applied by this build.
    public static let schemaVersion = 10
}
