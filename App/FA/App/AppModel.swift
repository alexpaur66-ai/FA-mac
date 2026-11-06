// The app model: opens the one database file and holds the stores (ADR 0008).

import AppKit
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
    var stock: StockStore { StockStore(database) }
    var exports: ExportStore { ExportStore(database) }
    var clientNotes: ClientNoteStore { ClientNoteStore(database) }
}

@MainActor @Observable
final class AppModel {
    /// The stores once the database is open; nil when it could not be opened (`openError` says why).
    /// Opening never shows an alert: the window shows the problem inline (screens-flows.md §2a).
    private(set) var stores: Stores? = nil
    private(set) var openError: String? = nil

    /// Bumped when a restore replaced the data: the windows rebuild their content, so no view keeps
    /// figures, selections or drafts read from the data that was replaced.
    private(set) var generation = 0

    /// View ▸ Bigger / Smaller: 1 … 2 in steps of a quarter (design-system.md §3), kept across launches.
    private(set) var textScale: CGFloat

    static let textScaleSteps: [CGFloat] = [1, 1.25, 1.5, 1.75, 2]
    private static let textScaleKey = "textScale"

    /// The database file, known even when opening it failed, so the error view can show the folder.
    let databaseURL: URL?

    /// Restore from Backup… (screens-flows.md §2h): the picked file and what it holds, while the preview
    /// is up.
    var restoreCandidate: RestoreCandidate? = nil
    /// Why the picked file can't be restored, or why the restore failed; shown in an alert.
    var restoreProblem: String? = nil
    /// The result line the main window shows once its content is rebuilt after a restore.
    @ObservationIgnored private var pendingNotice: String? = nil

    /// The quit observer that makes the on-quit backup (screens-flows.md §2h).
    @ObservationIgnored private var terminationObserver: NSObjectProtocol? = nil

    init() {
        let saved = CGFloat(UserDefaults.standard.double(forKey: Self.textScaleKey))
        textScale = Self.textScaleSteps.contains(saved) ? saved : 1
        var url: URL?
        var locationError: Error?
        do {
            url = try Self.databaseLocation()
        } catch {
            locationError = error
        }
        databaseURL = url
        if let locationError {
            openError = String(describing: locationError)
        } else {
            open()
        }
        if let stores {
            // A backup on the first launch of each day and on quit (§2h, set-05).
            BackupService.backUpOnFirstLaunchOfDay(stores)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let stores = self?.stores { _ = BackupService.backUp(stores) }
            }
        }
    }

    /// Opens the data file (or the in-memory database) and keeps its stores, or the reason it failed.
    private func open() {
        do {
            let database: AppDatabase
            if let databaseURL {
                database = try AppDatabase(at: databaseURL)
            } else {
                database = try AppDatabase()
            }
            let opened = Stores(database: database, databaseURL: databaseURL)
            // A new database gets the three fixed number series; an existing one keeps its own (set-09). A
            // failure here leaves Settings ▸ Numbering and Issue to say what is missing.
            _ = try? opened.series.ensureDefaultSeries(year: CalendarDay(Date(), in: .current).year)
            stores = opened
            openError = nil
        } catch {
            stores = nil
            openError = String(describing: error)
        }
    }

    // MARK: Restore from Backup… (screens-flows.md §2h)

    struct RestoreCandidate: Identifiable {
        let url: URL
        let info: BackupInfo
        var id: URL { url }
    }

    /// Restore from Backup… needs a data file to restore into; the in-memory database has none.
    var canRestore: Bool { databaseURL != nil }

    /// Picks the backup file and opens the preview, or says why the file can't be restored.
    func chooseBackupToRestore() {
        guard canRestore else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = BackupSettings.folderURL(databaseURL: databaseURL)
        panel.prompt = String(localized: L.choose)
        panel.message = String(localized: L.restorePanelMessage)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            restoreCandidate = RestoreCandidate(url: url, info: try Backups.inspect(url))
        } catch {
            restoreProblem = ErrorText.message(error)
        }
    }

    /// Replaces the data with the backup once the alert is confirmed. The current data is backed up first,
    /// and nothing is restored when that fails; a data file that can't be opened is kept beside the
    /// restored one instead. The windows then rebuild on the restored data.
    func restore(_ candidate: RestoreCandidate) {
        restoreCandidate = nil
        if let stores {
            // Open editors write what they hold and then stop; the windows are rebuilt afterwards whether
            // or not the restore succeeds, so none keeps an editor that no longer saves. A Remove Bank Account
            // made before it can no longer be undone, even from a Settings window that is closed now.
            BankAccountUndo.invalidateAll()
            NotificationCenter.default.post(name: .dataWillBeReplaced, object: nil)
            defer { generation += 1 }
            // Not pruned: the oldest backup may be the one being restored. The next backup prunes.
            if case .failure(let error)? = BackupService.backUp(stores, pruning: false) {
                restoreProblem = String(localized: L.restoreNotBackedUp(ErrorText.message(error)))
                return
            }
            do {
                try Backups.restore(from: candidate.url, into: stores.database)
            } catch {
                restoreProblem = ErrorText.message(error)
                return
            }
        } else if let databaseURL {
            do {
                try Backups.replaceUnopenableFile(at: databaseURL, with: candidate.url)
            } catch {
                restoreProblem = ErrorText.message(error)
                return
            }
            open()
            // Still not open: the error view shows the new reason.
            guard stores != nil else { return }
        } else {
            return
        }
        if let madeAt = candidate.info.madeAt {
            pendingNotice = String(localized: L.restoredFrom(CalendarDay(madeAt, in: .current).formatted(.current)))
        } else {
            pendingNotice = String(localized: L.restoredNoDate)
        }
    }

    /// The line to show once after a restore; nil afterwards.
    func takeNotice() -> String? {
        defer { pendingNotice = nil }
        return pendingNotice
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
    /// `FA_DATABASE_PATH` overrides the path; `FA_IN_MEMORY_DATABASE=1` (nil here) opens a throwaway database.
    private static func databaseLocation() throws -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if environment["FA_IN_MEMORY_DATABASE"] == "1" {
            return nil
        }
        if let path = environment["FA_DATABASE_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("FA", isDirectory: true)
            .appendingPathComponent("fa.sqlite", isDirectory: false)
    }
}
