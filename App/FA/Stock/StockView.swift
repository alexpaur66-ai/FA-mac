// Stock (screens-flows.md §2n): the items table in the content column, the selected item in the detail
// column, and the Count…, Receive…, Take Out… and New Stock Item… sheets. Rough on purpose: the figure is
// what the app last knew, and a count fixes it in one step.

import InvoicingCore
import InvoicingData
import SwiftUI

/// One row of the items table, with keys every column sorts by.
struct StockRow: Identifiable, Hashable {
    let id: String
    let name: String
    let unit: String
    let onHand: Decimal
    let reorderLevel: Decimal?
    let lastCounted: CalendarDay?
    let isLow: Bool
    let hasMovements: Bool

    /// Low items first (the default sort), as a sortable key.
    var lowRank: Int { isLow ? 0 : 1 }
    /// No reorder level sorts first.
    var reorderKey: Decimal { reorderLevel ?? -1 }
    /// Never counted sorts first.
    var countedKey: String { lastCounted?.isoString ?? "" }

    init(_ state: StockItemState) {
        id = state.id
        name = state.item.name
        unit = state.item.unit
        onHand = state.onHand
        reorderLevel = state.item.reorderLevel
        lastCounted = state.lastCounted
        isLow = state.isLow
        hasMovements = state.movementCount > 0
    }

    func matches(search: String) -> Bool {
        let key = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || name.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension StatusStyle {
    /// The Low badge: the caution tone, a symbol and the word, never colour alone (design-system §4.3).
    static let stockLow = StatusStyle(tone: .caution, symbol: "arrow.down.circle", label: L.stockLow)
}

/// "3 weeks ago", or "Never".
enum StockDates {
    static func counted(_ day: CalendarDay?, locale: Locale) -> String {
        guard let day else { return String(localized: L.stockNever) }
        return relative(day, locale: locale)
    }

    static func relative(_ day: CalendarDay, locale: Locale) -> String {
        let today = CalendarDay(Date(), in: .current)
        if day == today { return String(localized: L.todayWord) }
        var style = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
        style.locale = locale
        return day.midnight(in: .current).formatted(style)
    }

    /// "4. 11.": a history line's day.
    static func short(_ day: CalendarDay, locale: Locale) -> String {
        day.midnight(in: .current).formatted(Date.FormatStyle(locale: locale).day().month(.defaultDigits))
    }
}

struct StockView: View {
    @Bindable var stock: StockModel
    @Binding var selection: String?
    @Binding var search: String
    /// A problem from Delete or Archive, for the window's result line.
    let report: @MainActor (String) -> Void

    @State private var sortOrder = [KeyPathComparator(\StockRow.lowRank),
                                     KeyPathComparator(\StockRow.name, comparator: .localizedStandard)]
    @Environment(\.locale) private var locale
    @Environment(\.undoManager) private var undoManager

    private var rows: [StockRow] {
        stock.states.map(StockRow.init).filter { $0.matches(search: search) }.sorted(using: sortOrder)
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            if let error = stock.error {
                HStack(spacing: Spacing.m) {
                    InlineMessage(error)
                    Spacer()
                    Button { stock.reload() } label: { Text(L.retry) }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                Divider()
            }
            if rows.isEmpty && search.isEmpty {
                if stock.loaded {
                    ContentUnavailableView {
                        Label { Text(L.noStockItems) } icon: { Image(systemName: "shippingbox") }
                    } description: {
                        Text(L.noStockItemsDescription)
                    } actions: {
                        Button { stock.sheet = .newItem } label: { Text(L.newStockItem) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Spacer()
                }
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                table(rows)
            }
        }
        .navigationTitle(selectedName.map { Text(verbatim: $0) } ?? Text(L.stock))
        .searchable(text: $search, placement: .toolbar, prompt: Text(L.searchStock))
        .toolbar {
            ToolbarItem {
                Button { stock.sheet = .newItem } label: {
                    Label { Text(L.newStockItemToolbar) } icon: { Image(systemName: "plus") }
                }
                .help(Text(L.newStockItemHelp))
            }
        }
        .sheet(item: $stock.sheet) { sheet in
            sheetView(sheet)
        }
    }

    private var selectedName: String? {
        selection.flatMap { stock.state(id: $0)?.item.name }
    }

    // Item · On Hand · Reorder At · Counted (§2n).
    private func table(_ rows: [StockRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(Text(L.colItem), value: \.name, comparator: .localizedStandard) { row in
                Text(verbatim: row.name).textRole(.body)
            }
            TableColumn(Text(L.colOnHand), value: \.onHand) { row in
                HStack(spacing: Spacing.s) {
                    if row.isLow {
                        StatusBadge(style: .stockLow, compact: true)
                    }
                    Text(verbatim: StockFormat.quantity(row.onHand, unit: row.unit, locale: locale))
                        .textRole(.amount)
                        .foregroundStyle(row.onHand < 0 ? Color.secondary : Color.primary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .combine)
            }
            .width(min: 90, ideal: 120)
            .alignment(.trailing)
            TableColumn(Text(L.colReorderAt), value: \.reorderKey) { row in
                Text(verbatim: row.reorderLevel.map { StockFormat.number($0, locale: locale) } ?? "")
                    .textRole(.amount)
            }
            .width(min: 70, ideal: 90)
            .alignment(.trailing)
            TableColumn(Text(L.colCounted), value: \.countedKey) { row in
                Text(verbatim: StockDates.counted(row.lastCounted, locale: locale)).textRole(.body)
            }
            .width(min: 90, ideal: 120)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                Button { stock.sheet = .count(id) } label: { Text(L.stockCount) }
                Button { stock.sheet = .receive(id) } label: { Text(L.stockReceive) }
                Button { stock.sheet = .takeOut(id) } label: { Text(L.stockTakeOut) }
                Divider()
                if row.hasMovements {
                    Button { archive(id) } label: { Text(L.stockArchiveItem) }
                } else {
                    Button { delete(id) } label: { Text(L.delete) }
                }
            }
        } primaryAction: { ids in
            // ↩ and a double-click open Count… for the row (§2n keys).
            if ids.count == 1, let id = ids.first { stock.sheet = .count(id) }
        }
        .onDeleteCommand {
            if let id = deletableSelection { delete(id) }
        }
    }

    /// Edit ▸ Delete: only an item with no movements; one with movements is archived from the Stock menu.
    private var deletableSelection: String? {
        guard let id = selection, let state = stock.state(id: id), state.movementCount == 0 else { return nil }
        return id
    }

    private func delete(_ id: String) {
        if let problem = stock.delete(itemID: id, undoManager: undoManager) {
            report(problem)
        } else if selection == id {
            selection = nil
        }
    }

    private func archive(_ id: String) {
        if let problem = stock.archive(itemID: id, undoManager: undoManager) {
            report(problem)
        } else if selection == id {
            selection = nil
        }
    }

    @ViewBuilder private func sheetView(_ sheet: StockSheet) -> some View {
        switch sheet {
        case .newItem:
            NewStockItemSheet(stock: stock) { item in
                search = ""
                selection = item.id
            }
        case .count(let id):
            if let state = stock.state(id: id) { StockQuantitySheet(stock: stock, state: state, mode: .count) }
        case .receive(let id):
            if let state = stock.state(id: id) { StockQuantitySheet(stock: stock, state: state, mode: .receive) }
        case .takeOut(let id):
            if let state = stock.state(id: id) { StockQuantitySheet(stock: stock, state: state, mode: .takeOut) }
        }
    }
}

// MARK: - Item detail

/// The selected item: its header fields, edited in place; on hand; and its history, newest first. The content
/// has no buttons: Receive… and Count… are in the toolbar (§2n).
struct StockItemDetailView: View {
    let stock: StockModel
    let itemID: String
    /// Shows an issued document in Documents (a history line's ↩ or double-click).
    let openDocument: @MainActor (String) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        if let state = stock.state(id: itemID) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    StockItemHeader(stock: stock, item: state.item)
                        .id(state.item)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: StockFormat.quantity(state.onHand, unit: state.item.unit, locale: locale))
                            .textRole(.kpi)
                            .foregroundStyle(state.onHand < 0 ? Color.secondary : Color.primary)
                        Text(verbatim: countedLine(state)).textRole(.rowSecondary)
                    }
                    history(state)
                }
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar {
                ToolbarItem {
                    Button { stock.sheet = .receive(itemID) } label: { Text(L.stockReceive) }
                        .help(Text(L.stockReceiveHelp))
                }
                ToolbarItem {
                    Button { stock.sheet = .count(itemID) } label: { Text(L.stockCount) }
                        .buttonStyle(.borderedProminent)
                        .help(Text(L.stockCountHelp))
                }
            }
        } else {
            ContentUnavailableView { Text(L.stockSelectItem) }
        }
    }

    private func countedLine(_ state: StockItemState) -> String {
        guard let day = state.lastCounted else { return String(localized: L.stockNeverCounted) }
        return String(localized: L.stockCountedAgo(StockDates.relative(day, locale: locale)))
    }

    private func history(_ state: StockItemState) -> some View {
        let movements = stock.movements(itemID: itemID)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.stockHistory).textRole(.sectionTitle)
            if movements.isEmpty {
                Text(L.stockNoHistory).textRole(.rowSecondary)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(movements) { movement in
                        historyLine(movement, unit: state.item.unit)
                    }
                }
            }
        }
    }

    @ViewBuilder private func historyLine(_ movement: StockMovement, unit: String) -> some View {
        let text = Text(verbatim: line(movement)).textRole(.body)
        if let documentID = movement.documentID {
            Button { openDocument(documentID) } label: { text }
                .buttonStyle(.plain)
                .help(Text(L.showDocument))
        } else {
            text.textSelection(.enabled)
        }
    }

    /// "4. 11. · −25 · FV 2026-0042 · Acme GmbH", "2. 11. · −2 · Taken out · sample",
    /// "1. 11. · +50 · Received · order 118", "28. 10. · Counted 40 (app had 46)".
    private func line(_ movement: StockMovement) -> String {
        let day = StockDates.short(movement.day, locale: locale)
        var parts = [day]
        switch movement.kind {
        case .count:
            let counted = StockFormat.number(movement.quantity, locale: locale)
            if let had = movement.previousOnHand {
                parts.append(String(localized: L.stockCountedHad(counted, StockFormat.number(had, locale: locale))))
            } else {
                parts.append(String(localized: L.stockCounted(counted)))
            }
        case .received:
            parts.append(StockFormat.change(movement.quantity, sign: 1, locale: locale))
            parts.append(String(localized: L.stockReceived))
        case .takenOut:
            parts.append(StockFormat.change(movement.quantity, sign: -1, locale: locale))
            if let number = movement.documentNumber {
                parts.append(number)
                if let client = movement.customerName { parts.append(client) }
            } else {
                parts.append(String(localized: L.stockTakenOut))
            }
        }
        if let note = movement.note { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// Name, unit and reorder level, each committed on ↩ or when focus leaves; an invalid name returns to the
/// stored one and says why.
private struct StockItemHeader: View {
    let stock: StockModel
    let item: StockItem

    private enum Field: Hashable { case name, unit, reorder }

    @State private var name: String
    @State private var unit: String
    @State private var reorder: String
    @State private var problem: String?
    @FocusState private var focus: Field?
    @Environment(\.locale) private var locale
    @Environment(\.undoManager) private var undoManager

    init(stock: StockModel, item: StockItem) {
        self.stock = stock
        self.item = item
        _name = State(initialValue: item.name)
        _unit = State(initialValue: item.unit)
        _reorder = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            TextField(text: $name) { Text(L.fieldName) }
                .textFieldStyle(.plain)
                .textRole(.screenTitle)
                .focused($focus, equals: .name)
                .onSubmit(commit)
            Form {
                TextField(text: $unit) { Text(L.stockUnit) }
                    .focused($focus, equals: .unit)
                    .onSubmit(commit)
                TextField(text: $reorder) { Text(L.stockReorderAt) }
                    .focused($focus, equals: .reorder)
                    .onSubmit(commit)
            }
            .formStyle(.grouped)
            if let problem {
                InlineMessage(problem)
            }
        }
        .onAppear { reorder = item.reorderLevel.map { StockFormat.number($0, locale: locale) } ?? "" }
        .onChange(of: focus) { old, _ in
            if old != nil { commit() }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let trimmedReorder = reorder.trimmingCharacters(in: .whitespacesAndNewlines)
        var level: Decimal? = nil
        if !trimmedReorder.isEmpty {
            guard let parsed = DecimalInput.parse(trimmedReorder, locale: locale), parsed >= 0 else {
                problem = String(localized: L.stockQuantityZeroOrMore)
                return
            }
            level = parsed
        }
        var updated = item
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.reorderLevel = level
        do {
            try stock.update(updated, undoManager: undoManager)
            problem = nil
        } catch {
            // The field returns to the stored name and says why.
            name = item.name
            problem = ErrorText.message(error, locale: locale)
        }
    }
}

// MARK: - Sheets

/// Count…, Receive… and Take Out…: one sheet shape. Each closes on ↩; the new figure and history line show
/// the result in place, so there is no result line (§2n).
struct StockQuantitySheet: View {
    enum Mode { case count, receive, takeOut }

    let stock: StockModel
    let state: StockItemState
    let mode: Mode

    @State private var quantity: String
    @State private var date = Date()
    @State private var note = ""
    @State private var problem: String?
    @FocusState private var quantityFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.undoManager) private var undoManager

    init(stock: StockModel, state: StockItemState, mode: Mode) {
        self.stock = stock
        self.state = state
        self.mode = mode
        // Count… is prefilled with the app's figure, so typing replaces it; the others start empty.
        _quantity = State(initialValue: mode == .count ? StockFormat.number(max(state.onHand, 0), locale: .current) : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).textRole(.screenTitle)
                Text(verbatim: state.item.name).textRole(.rowSecondary)
            }
            Form {
                LabeledContent {
                    HStack(spacing: Spacing.s) {
                        TextField(text: $quantity) { Text(quantityLabel) }
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .textRole(.amount)
                            .focused($quantityFocused)
                            .frame(maxWidth: 120)
                        Text(verbatim: state.item.unit).textRole(.body)
                    }
                } label: {
                    Text(quantityLabel)
                }
                // A count can't be in the future; Receive… and Take Out… take any day.
                if mode == .count {
                    DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) { Text(L.stockCountedOn) }
                } else {
                    DatePicker(selection: $date, displayedComponents: .date) { Text(L.stockOnDay) }
                    TextField(text: $note) { Text(L.stockNote) }
                }
                if let problem {
                    InlineMessage(problem)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { save() } label: { Text(saveTitle) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 420, maxWidth: 520)
        .onAppear { quantityFocused = true }
    }

    private var title: LocalizedStringResource {
        switch mode {
        case .count: L.stockCountTitle
        case .receive: L.stockReceiveTitle
        case .takeOut: L.stockTakeOutTitle
        }
    }

    private var quantityLabel: LocalizedStringResource {
        switch mode {
        case .count: L.stockOnHandField
        case .receive: L.stockReceivedField
        case .takeOut: L.stockTakenOutField
        }
    }

    private var saveTitle: LocalizedStringResource {
        switch mode {
        case .count: L.stockSaveCount
        case .receive: L.stockReceiveButton
        case .takeOut: L.stockTakeOutButton
        }
    }

    private func save() {
        let parsed = DecimalInput.parse(quantity, locale: locale)
        let day = CalendarDay(date, in: .current)
        do {
            switch mode {
            case .count:
                guard let parsed, parsed >= 0 else {
                    problem = String(localized: L.stockQuantityZeroOrMore)
                    return
                }
                try stock.count(itemID: state.id, onHand: parsed, day: day, undoManager: undoManager)
            case .receive:
                guard let parsed, parsed > 0 else {
                    problem = String(localized: L.stockQuantityMoreThanZero)
                    return
                }
                try stock.receive(itemID: state.id, quantity: parsed, day: day, note: note, undoManager: undoManager)
            case .takeOut:
                guard let parsed, parsed > 0 else {
                    problem = String(localized: L.stockQuantityMoreThanZero)
                    return
                }
                try stock.takeOut(itemID: state.id, quantity: parsed, day: day, note: note, undoManager: undoManager)
            }
            dismiss()
        } catch {
            problem = ErrorText.message(error, locale: locale)
        }
    }
}

/// New Stock Item…: name, unit, on hand now (a count for today) and reorder at.
struct NewStockItemSheet: View {
    let stock: StockModel
    /// The item was added: the list selects it.
    let added: @MainActor (StockItem) -> Void

    @State private var name = ""
    @State private var unit = "ks"
    @State private var onHand = ""
    @State private var reorder = ""
    @State private var problem: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.newStockItemTitle).textRole(.screenTitle)
            Form {
                TextField(text: $name) { Text(L.fieldName) }
                    .focused($nameFocused)
                if let duplicate = duplicateName {
                    InlineMessage(L.stockNameTaken(duplicate))
                }
                TextField(text: $unit) { Text(L.stockUnit) }
                TextField(text: $onHand) { Text(L.stockOnHandNow) }
                TextField(text: $reorder) { Text(L.stockReorderAt) }
                if let problem {
                    InlineMessage(problem)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { add() } label: { Text(L.stockAddItem) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(duplicateName != nil)
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 420, maxWidth: 520)
        .onAppear { nameFocused = true }
    }

    /// A name a listed item already has, ignoring case, keeps Add Item disabled (§2n).
    private var duplicateName: String? {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        return stock.states.first { $0.item.name.compare(typed, options: [.caseInsensitive]) == .orderedSame }?.item.name
    }

    /// An empty optional field is nil; anything else must be a number of 0 or more.
    private func optionalNumber(_ text: String) -> Decimal?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = DecimalInput.parse(trimmed, locale: locale), value >= 0 else { return nil }
        return .some(value)
    }

    private func add() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            problem = String(localized: L.nameRequired)
            return
        }
        guard let count = optionalNumber(onHand), let level = optionalNumber(reorder) else {
            problem = String(localized: L.stockQuantityZeroOrMore)
            return
        }
        do {
            let item = try stock.add(name: name, unit: unit, reorderLevel: level, onHand: count, undoManager: undoManager)
            dismiss()
            added(item)
        } catch {
            problem = ErrorText.message(error, locale: locale)
        }
    }
}
