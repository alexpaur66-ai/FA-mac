// Backups (screens-flows.md §2h, set-05): fixed behaviour with no options. A backup runs on the first
// launch of each day, on quit and from File ▸ Back Up Now (later also before every Export for
// Accountant); the last 30 are kept. The one setting is the folder, in Settings ▸ General: by default a
// "Backups" folder next to the data file, or a folder Saša picks (kept as a security-scoped bookmark).
// The outcome of the last backup is kept in UserDefaults, so the General caption and the Overview row
// follow it through @AppStorage.

import AppKit
import Foundation
import InvoicingCore
import InvoicingData

enum BackupSettings {
    static let folderBookmarkKey = "backupFolderBookmark"
    /// When the last backup succeeded, as seconds since 1970; 0 before the first one.
    static let lastSuccessKey = "backup.lastSuccess"
    /// Why the last backup failed; empty once one succeeds again.
    static let lastFailureKey = "backup.lastFailure"

    /// "Backups" next to the data file, inside the app's container: no bookmark needed.
    static func defaultFolder(databaseURL: URL) -> URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    /// The folder Saša picked, resolved from its bookmark; nil when none was picked, the bookmark no longer
    /// resolves, or the folder is in the Trash.
    static func chosenFolderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: folderBookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: folderBookmarkKey)
        }
        return PDFSettings.isInTrash(url) ? nil : url
    }

    /// Where backups go: the picked folder, else the default; nil for the in-memory database.
    static func folderURL(databaseURL: URL?) -> URL? {
        guard let databaseURL else { return nil }
        return chosenFolderURL() ?? defaultFolder(databaseURL: databaseURL)
    }

    static func setFolder(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: folderBookmarkKey)
    }

    /// Choose Folder… under Backup folder; nil when cancelled.
    @MainActor
    static func chooseFolder() throws -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: L.choose)
        panel.message = String(localized: L.backupFolderPrompt)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try setFolder(url)
        return url
    }

    /// "1.0 (7)", written into each backup for the restore preview.
    static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard let build = info?["CFBundleVersion"] as? String, build != short else { return short }
        return short + " (" + build + ")"
    }

    static var lastSuccess: Date? {
        let seconds = UserDefaults.standard.double(forKey: lastSuccessKey)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }
}

@MainActor
enum BackupService {
    /// Makes a backup now and records the outcome for the caption and the Overview row. Nil for the
    /// in-memory database, which has nothing to back up.
    @discardableResult
    static func backUp(_ stores: Stores, now: Date = Date()) -> Result<URL, Error>? {
        guard let folder = BackupSettings.folderURL(databaseURL: stores.databaseURL) else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            let url = try Backups.make(of: stores.database, in: folder, now: now, appVersion: BackupSettings.appVersion)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: BackupSettings.lastSuccessKey)
            UserDefaults.standard.removeObject(forKey: BackupSettings.lastFailureKey)
            return .success(url)
        } catch {
            UserDefaults.standard.set(ErrorText.message(error), forKey: BackupSettings.lastFailureKey)
            return .failure(error)
        }
    }

    /// The first launch of each day makes a backup; later launches that day do not.
    static func backUpOnFirstLaunchOfDay(_ stores: Stores, now: Date = Date()) {
        if let last = BackupSettings.lastSuccess, Calendar.current.isDate(last, inSameDayAs: now) { return }
        backUp(stores, now: now)
    }
}

/// The words for the last backup's outcome, from the two stored values that @AppStorage follows.
enum BackupStatus {
    /// The Overview queue's backup row (screens-flows.md §2a), first match wins: a failure until the next
    /// success, then "No backup yet", then "Last backup 9 days ago" once the last success is more than 7
    /// days old; nil when no row shows.
    static func queueText(lastSuccess: Double, failure: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        if !failure.isEmpty { return String(localized: L.backupFailed(failure)) }
        guard lastSuccess > 0 else { return String(localized: L.backupNone) }
        let last = Date(timeIntervalSince1970: lastSuccess)
        // "More than 7 days" is elapsed time, not calendar days.
        guard now.timeIntervalSince(last) > 7 * 86_400 else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        return String(localized: L.backupDaysAgo(max(days, 7)))
    }

    /// The caption under Backup folder in Settings ▸ General (§2i).
    static func caption(lastSuccess: Double, failure: String, now: Date = Date(), locale: Locale) -> String {
        let last = lastSuccess > 0 ? Date(timeIntervalSince1970: lastSuccess) : nil
        if !failure.isEmpty {
            guard let last else { return String(localized: L.backupCaptionFailedNever(failure)) }
            return String(localized: L.backupCaptionFailed(failure, CalendarDay(last, in: .current).formatted(locale)))
        }
        guard let last else { return String(localized: L.backupCaptionNone) }
        return String(localized: L.backupCaption(when(last, now: now, locale: locale)))
    }

    /// "today 9:02", or "3. 11. 2026 9:02" on another day.
    static func when(_ date: Date, now: Date = Date(), locale: Locale) -> String {
        let time = timeText(date, locale: locale)
        let day = Calendar.current.isDate(date, inSameDayAs: now)
            ? String(localized: L.todayWord) : CalendarDay(date, in: .current).formatted(locale)
        return String(localized: L.backupWhen(day, time))
    }

    static func timeText(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
    }
}
