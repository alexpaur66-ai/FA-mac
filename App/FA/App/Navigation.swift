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
    /// come first.
    var defaultSortOrder: [KeyPathComparator<DocumentRow>] {
        switch self {
        case .unpaid:
            [KeyPathComparator(\DocumentRow.dueDate, order: .forward)]
        case .openAdvances:
            [KeyPathComparator(\DocumentRow.issueDate, order: .forward)]
        case .drafts:
            [KeyPathComparator(\DocumentRow.updatedAt, order: .reverse)]
        case .all:
            [KeyPathComparator(\DocumentRow.issueDate, order: .reverse)]
        }
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
