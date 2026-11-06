// The information architecture: sections, document filters and the sidebar selection (screens-flows.md §1.2).

import InvoicingCore
import InvoicingData
import SwiftUI

/// SF Symbols renamed in macOS 15 (design-system.md §7), with the macOS 14 names as fallback.
enum Symbols {
    static var document: String {
        if #available(macOS 15, *) { "text.document" } else { "doc.text" }
    }
    static var advance: String {
        if #available(macOS 15, *) { "document.badge.clock" } else { "doc.badge.clock" }
    }
    static var receipt: String {
        if #available(macOS 15.2, *) { "receipt" } else { "doc.plaintext" }
    }
    static var finalInvoice: String {
        if #available(macOS 15, *) { "checkmark.seal.text.page" } else { "checkmark.seal" }
    }
}

/// The four sidebar sections, ⌘1 … ⌘4 (screens-flows.md §1.2). Exchange rates, the export and the backup
/// are File menu commands; ⌘5 waits for Stock and ⌘6 is unassigned.
enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview, documents, clients, payments

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .overview: L.overview
        case .documents: L.documents
        case .clients: L.clients
        case .payments: L.payments
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .documents: Symbols.document
        case .clients: "person.2"
        case .payments: "banknote"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .documents: "2"
        case .clients: "3"
        case .payments: "4"
        }
    }
}

/// The smart filters of Documents: the Documents row itself (all) and the three rows under it. The rules
/// follow the aggregation table in screens-flows.md §2a: Unpaid counts invoices and final invoices only
/// (overdue ones first, with their status word); advances have their own filter.
enum DocumentSmartFilter: String, CaseIterable, Identifiable, Sendable {
    case all, drafts, unpaid, openAdvances

    var id: Self { self }

    /// The sidebar row and the window subtitle.
    var title: LocalizedStringResource {
        switch self {
        case .all: L.documents
        case .drafts: L.filterDrafts
        case .unpaid: L.filterUnpaid
        case .openAdvances: L.filterOpenAdvances
        }
    }

    /// View ▸ Filter ▸, in title case.
    var menuTitle: LocalizedStringResource {
        switch self {
        case .all: L.filterAllDocuments
        case .drafts: L.filterDrafts
        case .unpaid: L.filterUnpaid
        case .openAdvances: L.menuFilterOpenAdvances
        }
    }

    var symbol: String {
        switch self {
        case .all: Symbols.document
        case .drafts: "pencil.circle"
        case .unpaid: "clock"
        case .openAdvances: Symbols.advance
        }
    }

    func matches(_ state: DocumentState, today: CalendarDay) -> Bool {
        let summary = state.summary
        switch self {
        case .all:
            return true
        case .drafts:
            return summary.status == .draft
        case .unpaid:
            return state.countsAsUnpaidInvoice
        case .openAdvances:
            return state.isOpenAdvance
        }
    }

    /// Each filter opens with its own sort (screens-flows.md §2b); Unpaid by due date, so overdue rows
    /// come first. After that it keeps the sort chosen for it (`DocumentSortMemory`).
    var defaultSort: DocumentSort {
        switch self {
        case .unpaid: DocumentSort(column: .due, ascending: true)
        case .openAdvances: DocumentSort(column: .issued, ascending: true)
        case .drafts: DocumentSort(column: .updated, ascending: false)
        case .all: DocumentSort(column: .issued, ascending: false)
        }
    }
}

/// A sortable column of the Documents table, in header order, plus the Drafts filter's last edit (no
/// column of its own). View ▸ Sort By ▸ lists the columns.
enum DocumentSortColumn: String, CaseIterable, Identifiable, Sendable {
    case number, type, client, issued, due, total, open, taxPoint, vs, updated

    var id: Self { self }

    /// The columns View ▸ Sort By ▸ lists, in header order.
    static let menuColumns: [DocumentSortColumn] = [.number, .type, .client, .issued, .due, .total, .open, .taxPoint, .vs]

    var title: LocalizedStringResource {
        switch self {
        case .number: L.colNumber
        case .type: L.colType
        case .client: L.colClient
        case .issued: L.colIssued
        case .due: L.colDue
        case .total: L.colTotal
        case .open: L.colOpen
        case .taxPoint: L.colTaxPoint
        case .vs: L.colVS
        case .updated: L.sortLastEdited
        }
    }

    var keyPath: PartialKeyPath<DocumentRow> {
        switch self {
        case .number: \DocumentRow.number
        case .type: \DocumentRow.typeName
        case .client: \DocumentRow.customerName
        case .issued: \DocumentRow.issueDate
        case .due: \DocumentRow.dueDate
        case .total: \DocumentRow.total
        case .open: \DocumentRow.outstanding
        case .taxPoint: \DocumentRow.taxPointKey
        case .vs: \DocumentRow.variableSymbol
        case .updated: \DocumentRow.updatedAt
        }
    }

    func comparator(ascending: Bool) -> KeyPathComparator<DocumentRow> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch self {
        case .number: return KeyPathComparator(\DocumentRow.number, order: order)
        case .type: return KeyPathComparator(\DocumentRow.typeName, order: order)
        case .client: return KeyPathComparator(\DocumentRow.customerName, order: order)
        case .issued: return KeyPathComparator(\DocumentRow.issueDate, order: order)
        case .due: return KeyPathComparator(\DocumentRow.dueDate, order: order)
        case .total: return KeyPathComparator(\DocumentRow.total, order: order)
        case .open: return KeyPathComparator(\DocumentRow.outstanding, order: order)
        case .taxPoint: return KeyPathComparator(\DocumentRow.taxPointKey, order: order)
        case .vs: return KeyPathComparator(\DocumentRow.variableSymbol, order: order)
        case .updated: return KeyPathComparator(\DocumentRow.updatedAt, order: order)
        }
    }

    init?(keyPath: PartialKeyPath<DocumentRow>) {
        guard let column = Self.allCases.first(where: { $0.keyPath == keyPath }) else { return nil }
        self = column
    }
}

/// One filter's sort: a column and a direction.
struct DocumentSort: Equatable, Sendable {
    var column: DocumentSortColumn
    var ascending: Bool

    var comparators: [KeyPathComparator<DocumentRow>] { [column.comparator(ascending: ascending)] }

    /// The sort a table header click asks for; nil for a key path no column has.
    init?(_ comparators: [KeyPathComparator<DocumentRow>]) {
        guard let first = comparators.first, let column = DocumentSortColumn(keyPath: first.keyPath) else { return nil }
        self.init(column: column, ascending: first.order == .forward)
    }

    init(column: DocumentSortColumn, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}

/// Each filter's sort, kept with the window as one text: "unpaid=due.a,all=issued.d" (screens-flows.md
/// §2b, "Each filter remembers its own sort").
enum DocumentSortMemory {
    static func sort(for filter: DocumentSmartFilter, in stored: String) -> DocumentSort {
        decode(stored)[filter] ?? filter.defaultSort
    }

    static func setting(_ sort: DocumentSort, for filter: DocumentSmartFilter, in stored: String) -> String {
        var sorts = decode(stored)
        sorts[filter] = sort
        return DocumentSmartFilter.allCases.compactMap { filter in
            sorts[filter].map { "\(filter.rawValue)=\($0.column.rawValue).\($0.ascending ? "a" : "d")" }
        }.joined(separator: ",")
    }

    private static func decode(_ stored: String) -> [DocumentSmartFilter: DocumentSort] {
        var sorts: [DocumentSmartFilter: DocumentSort] = [:]
        for entry in stored.split(separator: ",") {
            let parts = entry.split(separator: "=")
            guard parts.count == 2, let filter = DocumentSmartFilter(rawValue: String(parts[0])) else { continue }
            let value = parts[1].split(separator: ".")
            guard value.count == 2, let column = DocumentSortColumn(rawValue: String(value[0])) else { continue }
            sorts[filter] = DocumentSort(column: column, ascending: value[1] == "a")
        }
        return sorts
    }
}

/// What the sidebar selects: a section, or one document filter. Stored per window as text.
enum SidebarItem: Hashable, Sendable, RawRepresentable {
    case section(AppSection)
    case filter(DocumentSmartFilter)

    private static let filterPrefix = "documents."

    init?(rawValue: String) {
        if let section = AppSection(rawValue: rawValue) {
            self = section == .documents ? .filter(.all) : .section(section)
        } else if rawValue.hasPrefix(Self.filterPrefix) {
            let name = String(rawValue.dropFirst(Self.filterPrefix.count))
            if let filter = DocumentSmartFilter(rawValue: name) {
                self = .filter(filter)
            } else if let filter = Self.removedFilters[name] {
                self = .filter(filter)
            } else {
                return nil
            }
        } else if Self.removedSections.contains(rawValue) {
            self = .section(.overview)
        } else {
            return nil
        }
    }

    /// Rows of earlier versions restore to the nearest row (screens-flows.md §1.1, Restore).
    private static let removedFilters: [String: DocumentSmartFilter] = ["overdue": .unpaid, "thisMonth": .all]
    private static let removedSections: Set<String> = ["rates", "exports"]

    var rawValue: String {
        switch self {
        case .section(let section): section.rawValue
        case .filter(let filter): Self.filterPrefix + filter.rawValue
        }
    }

    var section: AppSection {
        switch self {
        case .section(let section): section
        case .filter: .documents
        }
    }

    var documentFilter: DocumentSmartFilter {
        switch self {
        case .filter(let filter): filter
        case .section: .all
        }
    }
}
