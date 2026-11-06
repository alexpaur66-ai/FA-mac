import Foundation
import GRDB

/// Backups of the database (screens-flows.md §2h): each one is a whole copy of the database file, the
/// audit log and the stored PDFs included, made with SQLite's online backup, so it is consistent while
/// the app runs. Files are named by the local time they were made, so their names sort by age, and only
/// the newest `keepCount` are kept.
public enum Backups {
    /// "The last 30 are kept" (§2h, set-05).
    public static let keepCount = 30

    static let namePrefix = "FA backup "
    static let nameExtension = "sqlite"

    /// "FA backup 2026-11-06 09-02-13.sqlite", in `timeZone`.
    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func padded(_ value: Int?, _ width: Int) -> String {
            let digits = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        func two(_ value: Int?) -> String { padded(value, 2) }
        let stamp = padded(parts.year, 4) + "-" + two(parts.month) + "-" + two(parts.day)
            + " " + two(parts.hour) + "-" + two(parts.minute) + "-" + two(parts.second)
        return namePrefix + stamp + "." + nameExtension
    }

    /// The backups in `folder`, oldest first; an empty list when the folder does not exist yet.
    public static func list(in folder: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(namePrefix) && $0.hasSuffix("." + nameExtension) }
            // Compared without the extension, so a second backup in the same second ("…13-2") sorts after
            // the first ("…13"): "-" sorts before ".", but the end of a name sorts before "-".
            .sorted { $0.dropLast(nameExtension.count + 1) < $1.dropLast(nameExtension.count + 1) }
        return names.map { folder.appendingPathComponent($0, isDirectory: false) }
    }

    /// Writes a backup of `database` into `folder` (created when missing), then deletes all but the newest
    /// `keepCount`. The copy is written under a hidden name and renamed when complete, so a failed backup
    /// never leaves a half-written file among the backups. Returns the backup file.
    @discardableResult
    public static func make(of database: AppDatabase, in folder: URL, now: Date = Date(),
                            timeZone: TimeZone = .current) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = fileName(for: now, timeZone: timeZone)
        var target = folder.appendingPathComponent(name, isDirectory: false)
        var suffix = 2
        while files.fileExists(atPath: target.path) {
            let base = String(name.dropLast(nameExtension.count + 1))
            target = folder.appendingPathComponent(base + "-\(suffix)." + nameExtension, isDirectory: false)
            suffix += 1
        }
        let partial = folder.appendingPathComponent(".partial-" + UUID().uuidString + "." + nameExtension, isDirectory: false)
        do {
            let destination = try DatabaseQueue(path: partial.path)
            try database.queue.backup(to: destination)
            try destination.close()
            try files.moveItem(at: partial, to: target)
        } catch {
            try? files.removeItem(at: partial)
            throw error
        }
        try prune(in: folder, keeping: keepCount)
        return target
    }

    /// Deletes all but the newest `count` backups in `folder`.
    public static func prune(in folder: URL, keeping count: Int) throws {
        let all = try list(in: folder)
        guard all.count > count else { return }
        for url in all.prefix(all.count - count) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
