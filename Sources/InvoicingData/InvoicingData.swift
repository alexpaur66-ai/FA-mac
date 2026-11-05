import GRDB
import InvoicingCore

/// SQLite persistence for FA-mac, built on GRDB. Schema and migrations live here.
public enum InvoicingData {
    /// Highest migration applied by this build. 0 = no schema yet (scaffold).
    public static let schemaVersion = 0
}
