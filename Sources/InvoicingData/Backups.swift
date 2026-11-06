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

    static let partialPrefix = ".partial-"

    /// Writes a backup of `database` into `folder` (created when missing), then deletes all but the newest
    /// `keepCount`. The copy is written under a hidden name and renamed when complete, so a failed backup
    /// never leaves a half-written file among the backups; hidden copies left by a backup that was cut off
    /// (a crash or power loss) are deleted first. Pruning is best effort: an old backup that cannot be
    /// deleted does not fail the backup just made. `pruning` false keeps every older backup: the one made
    /// before a restore must not delete the backup being restored; the next backup prunes. Returns the
    /// backup file.
    @discardableResult
    public static func make(of database: AppDatabase, in folder: URL, now: Date = Date(),
                            timeZone: TimeZone = .current, appVersion: String? = nil,
                            pruning: Bool = true) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        // Backups run one at a time, so any hidden copy (and its -journal, -wal or -shm) is a leftover.
        if let names = try? files.contentsOfDirectory(atPath: folder.path) {
            for leftover in names where leftover.hasPrefix(partialPrefix) && leftover.contains("." + nameExtension) {
                try? files.removeItem(at: folder.appendingPathComponent(leftover, isDirectory: false))
            }
        }
        let name = fileName(for: now, timeZone: timeZone)
        var target = folder.appendingPathComponent(name, isDirectory: false)
        var suffix = 2
        while files.fileExists(atPath: target.path) {
            let base = String(name.dropLast(nameExtension.count + 1))
            target = folder.appendingPathComponent(base + "-\(suffix)." + nameExtension, isDirectory: false)
            suffix += 1
        }
        let partial = folder.appendingPathComponent(partialPrefix + UUID().uuidString + "." + nameExtension, isDirectory: false)
        do {
            let destination = try DatabaseQueue(path: partial.path)
            try database.queue.backup(to: destination)
            try stamp(destination, now: now, appVersion: appVersion)
            try destination.close()
            try files.moveItem(at: partial, to: target)
        } catch {
            try? files.removeItem(at: partial)
            throw error
        }
        // The backup is made; a folder that cannot be listed or pruned does not undo that.
        if pruning {
            try? prune(in: folder, keeping: keepCount)
        }
        return target
    }

    /// Deletes all but the newest `count` backups in `folder`. A backup that cannot be deleted (locked, or
    /// owned by someone else) is skipped, so the others are still deleted; throws only when the folder
    /// cannot be listed.
    public static func prune(in folder: URL, keeping count: Int) throws {
        let all = try list(in: folder)
        guard all.count > count else { return }
        for url in all.prefix(all.count - count) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
