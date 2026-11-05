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

/// The six sidebar sections, ⌘1 … ⌘6.
enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview, documents, clients, payments, rates, exports

    var id: Self { self }

    /// The sidebar label, in sentence case.
    var title: LocalizedStringResource {
        switch self {
        case .overview: L.overview
        case .documents: L.documents
        case .clients: L.clients
        case .payments: L.payments
        case .rates: L.rates
        case .exports: L.exports
        }
    }

    /// The View menu item, in title case where the two differ.
    var menuTitle: LocalizedStringResource {
        switch self {
        case .rates: L.menuRates
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .documents: Symbols.document
        case .clients: "person.2"
        case .payments: "banknote"
        case .rates: "arrow.left.arrow.right"
        case .exports: "externaldrive"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .documents: "2"
        case .clients: "3"
        case .payments: "4"
        case .rates: "5"
        case .exports: "6"
        }
    }

    /// Exchange rates and Exports & Backup have no inspector (design-system.md §8.11): the item is disabled there.
    var hasInspector: Bool {
        switch self {
        case .overview, .documents, .clients, .payments: true
        case .rates, .exports: false
        }
    }
}

/// The smart filters under Documents. The rules follow the aggregation table in screens-flows.md §2a:
/// Unpaid and Overdue count invoices and final invoices only; advances have their own filter.
enum DocumentSmartFilter: String, CaseIterable, Identifiable, Sendable {
    case all, drafts, unpaid, overdue, thisMonth, openAdvances

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: L.filterAll
        case .drafts: L.filterDrafts
        case .unpaid: L.filterUnpaid
        case .overdue: L.filterOverdue
        case .thisMonth: L.filterThisMonth
        case .openAdvances: L.filterOpenAdvances
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .drafts: "pencil.circle"
        case .unpaid: "clock"
        case .overdue: "exclamationmark.circle"
        case .thisMonth: "calendar"
        case .openAdvances: Symbols.advance
        }
    }

    /// Drafts, Overdue and Open advances carry a count badge in the sidebar.
    var showsBadge: Bool {
        self == .drafts || self == .overdue || self == .openAdvances
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
        case .overdue:
            // Like Unpaid: invoices and final invoices only. Overdue advances are counted on their own
            // line (Open advances), and an advance deducted by a final invoice is never overdue (§2a).
            return state.countsAsUnpaidInvoice && state.isOverdue
        case .thisMonth:
            // Issued this month: a draft has no issue date yet, whatever date it carries.
            return summary.status == .issued && summary.issueDate.year == today.year && summary.issueDate.month == today.month
        case .openAdvances:
            return state.isOpenAdvance
        }
    }

    /// Each filter opens with its own sort (screens-flows.md §2b); drafts by their last edit.
    var defaultSortOrder: [KeyPathComparator<DocumentRow>] {
        switch self {
        case .overdue, .unpaid:
            [KeyPathComparator(\DocumentRow.dueDate, order: .forward)]
        case .openAdvances:
            [KeyPathComparator(\DocumentRow.issueDate, order: .forward)]
        case .drafts:
            [KeyPathComparator(\DocumentRow.updatedAt, order: .reverse)]
        case .all, .thisMonth:
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
            self = .section(section)
        } else if rawValue.hasPrefix(Self.filterPrefix),
                  let filter = DocumentSmartFilter(rawValue: String(rawValue.dropFirst(Self.filterPrefix.count))) {
            self = .filter(filter)
        } else {
            return nil
        }
    }

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
