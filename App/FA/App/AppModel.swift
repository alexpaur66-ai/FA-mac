// The app model: opens the one database file and holds the stores (ADR 0008).

import Foundation
import InvoicingCore
import InvoicingData
import Observation

/// The stores of the open database. A value, so every view can hold it; the stores are Sendable structs.
struct Stores: Sendable {
    let database: AppDatabase
    /// The database file; nil for the in-memory database of previews and tests.
    let databaseURL: URL?

    var documents: DocumentStore { DocumentStore(database) }
    var customers: CustomerStore { CustomerStore(database) }
    var series: NumberSeriesStore { NumberSeriesStore(database) }
    var profile: ProfileStore { ProfileStore(database) }
    var rates: RateStore { RateStore(database) }
    var statements: StatementStore { StatementStore(database) }
    var audit: AuditLog { AuditLog(database) }
}

@MainActor @Observable
final class AppModel {
    /// The stores once the database is open; nil when it could not be opened (`openError` says why).
    /// Opening never shows an alert: the window shows the problem inline (screens-flows.md §2a).
    let stores: Stores?
    let openError: String?

    /// View ▸ Bigger / Smaller: 1 … 2 in steps of a quarter (design-system.md §3), kept across launches.
    private(set) var textScale: CGFloat

    static let textScaleSteps: [CGFloat] = [1, 1.25, 1.5, 1.75, 2]
    private static let textScaleKey = "textScale"

    init() {
        let saved = CGFloat(UserDefaults.standard.double(forKey: Self.textScaleKey))
        textScale = Self.textScaleSteps.contains(saved) ? saved : 1
        do {
            let (database, url) = try Self.openDatabase()
            stores = Stores(database: database, databaseURL: url)
            openError = nil
        } catch {
            stores = nil
            openError = String(describing: error)
        }
    }

    func setTextScale(_ scale: CGFloat) {
        textScale = scale
        UserDefaults.standard.set(Double(scale), forKey: Self.textScaleKey)
    }

    /// Moves one step up (+1) or down (-1) the scale steps.
    func stepTextScale(_ delta: Int) {
        let steps = Self.textScaleSteps
        let index = steps.firstIndex(of: textScale) ?? 0
        let next = min(max(index + delta, 0), steps.count - 1)
        setTextScale(steps[next])
    }

    /// The database lives in the app's sandbox container under Application Support/FA/fa.sqlite.
    /// `FA_DATABASE_PATH` overrides the path; `FA_IN_MEMORY_DATABASE=1` opens a throwaway database.
    private static func openDatabase() throws -> (AppDatabase, URL?) {
        let environment = ProcessInfo.processInfo.environment
        if environment["FA_IN_MEMORY_DATABASE"] == "1" {
            return (try AppDatabase(), nil)
        }
        let url: URL
        if let path = environment["FA_DATABASE_PATH"], !path.isEmpty {
            url = URL(fileURLWithPath: path)
        } else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            url = support.appendingPathComponent("FA", isDirectory: true)
                .appendingPathComponent("fa.sqlite", isDirectory: false)
        }
        return (try AppDatabase(at: url), url)
    }
}
