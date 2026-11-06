// The menu bar (screens-flows.md §1.4): FA, File, Edit, View, Document, Window, Help; there is no Client
// menu. The main window publishes what it can do through `focusedSceneValue`, so the menus follow the key
// window and its selection; an item whose action is nil is disabled, never hidden. The editor of the
// selected draft is published too, so the Document menu edits the draft from the keyboard (lines, type,
// currency, language, VAT treatment, rate).

import AppKit
import InvoicingCore
import InvoicingData
import SwiftUI

/// What one document offers: the Document menu for the selected one, the context menu for any row.
struct DocumentActions {
    var recordPayment: (@MainActor () -> Void)?
    var recordRefund: (@MainActor () -> Void)?
    var deleteDraft: (@MainActor () -> Void)?
    var closeAdvanceUnpaid: (@MainActor () -> Void)?
    var markForCreditNote: (@MainActor () -> Void)?
    var reopen: (@MainActor () -> Void)?
    /// Which closing event Reopen takes back: "Reopen Advance" or "Remove Credit Note Mark".
    var reopenKind: DocumentClosureKind?
    var issue: (@MainActor () -> Void)?
    var duplicate: (@MainActor () -> Void)?
    /// The number of the issued document Duplicate would copy: "Duplicate FV-2026-007 as Draft".
    var duplicateSourceNumber: String?
    var createFinalInvoice: (@MainActor () -> Void)?
    var createTaxDocument: (@MainActor () -> Void)?
    var savePDF: (@MainActor () -> Void)?
    var showPDFInFinder: (@MainActor () -> Void)?
    var printDocument: (@MainActor () -> Void)?
    /// Selects the document's client in Clients.
    var showClient: (@MainActor () -> Void)?

    /// Reopen of a closed advance: the Close Advance as Unpaid… row reads "Reopen Advance" (§1.4).
    var reopenAdvance: (@MainActor () -> Void)? { reopenKind == .closedUnpaid ? reopen : nil }
    /// Reopen of a marked document: the Mark for Credit Note… row reads "Remove Credit Note Mark".
    var removeCreditNoteMark: (@MainActor () -> Void)? { reopenKind == .markedForCreditNote ? reopen : nil }

    /// One ⌘R row: Record Payment…, or Record Refund… on an overpaid document.
    var paymentAction: (@MainActor () -> Void)? { recordPayment ?? recordRefund }
    var paymentTitle: LocalizedStringResource { recordPayment == nil && recordRefund != nil ? L.recordRefund : L.recordPayment }

    /// One row for closing an advance or reopening it.
    var closeAdvanceAction: (@MainActor () -> Void)? { reopenAdvance ?? closeAdvanceUnpaid }
    var closeAdvanceTitle: LocalizedStringResource { reopenAdvance != nil ? L.reopenAdvance : L.closeAdvanceUnpaid }

    /// One row for the credit note mark or its removal.
    var creditNoteAction: (@MainActor () -> Void)? { removeCreditNoteMark ?? markForCreditNote }
    var creditNoteTitle: LocalizedStringResource { removeCreditNoteMark != nil ? L.removeCreditNoteMark : L.markForCreditNote }
}

struct MainActions {
    var show: @MainActor (SidebarItem) -> Void
    var newDocument: @MainActor (DocumentKind) -> Void
    var newClient: @MainActor () -> Void
    /// File ▸ Exchange Rates: the read-only rates sheet.
    var showExchangeRates: @MainActor () -> Void
    /// File ▸ Import ČNB Rates…: the file importer over the current section.
    var importRates: @MainActor () -> Void
    /// Help ▸ Getting Started: the Overview with the setup card shown again.
    var showGettingStarted: @MainActor () -> Void
    var showDataFolder: (@MainActor () -> Void)?
    /// The Documents filter shown, for the checkmark in View ▸ Filter ▸; nil outside Documents.
    var currentFilter: DocumentSmartFilter?
    /// Client context (the Clients section with a client selected): File ▸ New Invoice reads
    /// "New Invoice for Acme GmbH" and prefills that client.
    var newDocumentClientName: String?
    /// File ▸ Edit Client “…”…: the client selected in Clients, or the client of the selected document.
    var editClientName: String?
    var editClient: (@MainActor () -> Void)?
    /// View ▸ Show/Hide Preview on a draft in the editor; `previewShown` picks the title.
    var togglePreview: (@MainActor () -> Void)?
    var previewShown = false
    /// The editor of the selected draft, for the Document menu's editing items.
    var editor: DraftEditorModel?
    /// The selected document's own items.
    var document = DocumentActions()
}

private struct MainActionsKey: FocusedValueKey {
    typealias Value = MainActions
}

extension FocusedValues {
    var mainActions: MainActions? {
        get { self[MainActionsKey.self] }
        set { self[MainActionsKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.mainActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // File ▸ New replaces the system group, so File ▸ New Window never appears (§1.1). Duplicate makes
        // a new draft, so it lives here (⌘D) and names what it copies. The order is screens-flows.md §1.4.
        CommandGroup(replacing: .newItem) {
            let client = actions?.newDocumentClientName
            Button { actions?.newDocument(.invoice) } label: { Text(client.map { L.newInvoiceFor($0) } ?? L.newInvoice) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button { actions?.newDocument(.advanceRequest) } label: { Text(client.map { L.newAdvanceFor($0) } ?? L.newAdvance) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            // No shortcut: ⌥⌘N is unassigned in v0.1 (§3.1).
            Button { actions?.newClient() } label: { Text(L.newClient) }
                .disabled(actions == nil)
            Divider()
            Button { actions?.document.duplicate?() } label: {
                Text(actions?.document.duplicateSourceNumber.map { L.duplicateNumbered($0) } ?? L.duplicateAsDraft)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(actions?.document.duplicate == nil)
            Button { actions?.editClient?() } label: {
                Text(actions?.editClientName.map { L.editClientNamed($0) } ?? L.editClientEmpty)
            }
            .disabled(actions?.editClient == nil)
            Divider()
            Button { actions?.showExchangeRates() } label: { Text(L.menuRates) }
                .disabled(actions == nil)
            Button { actions?.importRates() } label: { Text(L.importRates) }
                .disabled(actions == nil)
            // The export step brings it (screens-flows.md §2h); listed, disabled, until then.
            Button {} label: { Text(L.menuExportAccountant) }
                .disabled(true)
            Divider()
            // The backup step brings these two; listed, disabled, until then. Show Data Folder is the one
            // place the data file is reachable from.
            Button {} label: { Text(L.backUpNow) }
                .disabled(true)
            Button {} label: { Text(L.restoreFromBackup) }
                .disabled(true)
            Button { actions?.showDataFolder?() } label: { Text(L.showDataFolder) }
                .disabled(actions?.showDataFolder == nil)
        }

        // File ▸ Save PDF…, Show PDF in Finder and Print… (⌘P) follow the selected document (§1.4); ⌘S
        // stays unbound, drafts autosave.
        CommandGroup(after: .newItem) {
            Divider()
            Button { actions?.document.savePDF?() } label: { Text(L.savePDF) }
                .disabled(actions?.document.savePDF == nil)
            Button { actions?.document.showPDFInFinder?() } label: { Text(L.showPDFInFinder) }
                .disabled(actions?.document.showPDFInFinder == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button { actions?.document.printDocument?() } label: { Text(L.printDocument) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions?.document.printDocument == nil)
        }

        SidebarCommands()
        ToolbarCommands()

        // View: the sections ⌘1 … ⌘4, the Documents filters, the draft preview and the text scale. There is
        // no inspector: ⌥⌘I is never bound (§3.1).
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(AppSection.allCases) { section in
                Button { actions?.show(.section(section)) } label: { Text(section.title) }
                    .keyboardShortcut(section.shortcutKey, modifiers: .command)
                    .disabled(actions == nil)
            }
            Divider()
            // Always enabled: a pick switches to Documents; the checkmark only while Documents is shown.
            Picker(selection: Binding(
                get: { actions?.currentFilter },
                set: { filter in if let filter { actions?.show(.filter(filter)) } })) {
                ForEach(DocumentSmartFilter.allCases) { filter in
                    Text(filter.menuTitle).tag(Optional(filter))
                }
            } label: {
                Text(L.menuFilter)
            }
            .disabled(actions == nil)
            Divider()
            // A draft in the editor: its detail swaps between the editor and the live PDF preview (§2c).
            Button { actions?.togglePreview?() } label: { Text(actions?.previewShown == true ? L.hidePreview : L.showPreview) }
                .disabled(actions?.togglePreview == nil)
            Divider()
            Button { model.stepTextScale(1) } label: { Text(L.biggerText) }
                .keyboardShortcut("+", modifiers: .command)
            Button { model.stepTextScale(-1) } label: { Text(L.smallerText) }
                .keyboardShortcut("-", modifiers: .command)
            Button { model.setTextScale(1) } label: { Text(L.actualSize) }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu(Text(L.menuDocument)) {
            let document = actions?.document
            Button { document?.issue?() } label: { Text(L.issue) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(document?.issue == nil)
            // One ⌘R row; on an overpaid document it reads Record Refund….
            Button { document?.paymentAction?() } label: { Text(document?.paymentTitle ?? L.recordPayment) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(document?.paymentAction == nil)
            Button { document?.createTaxDocument?() } label: { Text(L.createTaxDocumentForPayment) }
                .disabled(document?.createTaxDocument == nil)
            Button { document?.createFinalInvoice?() } label: { Text(L.createFinalInvoice) }
                .disabled(document?.createFinalInvoice == nil)
            Divider()
            editingItems
            Divider()
            // Each closing row reads its reopening on a closed or marked document, which acts at once.
            Button { document?.closeAdvanceAction?() } label: { Text(document?.closeAdvanceTitle ?? L.closeAdvanceUnpaid) }
                .disabled(document?.closeAdvanceAction == nil)
            Button { document?.creditNoteAction?() } label: { Text(document?.creditNoteTitle ?? L.markForCreditNote) }
                .disabled(document?.creditNoteAction == nil)
            Divider()
            Button { document?.showClient?() } label: { Text(L.showClient) }
                .disabled(document?.showClient == nil)
            Divider()
            Button { document?.deleteDraft?() } label: { Text(L.deleteDraft) }
                .disabled(document?.deleteDraft == nil)
        }

        // Window ▸ Main Window brings the main window to the front, or reopens it when it was closed (§1.1).
        CommandGroup(after: .windowArrangement) {
            Button { showMainWindow() } label: { Text(L.mainWindow) }
        }

        // Help ▸ Getting Started shows the setup card again once it has hidden itself (§2j).
        CommandGroup(after: .help) {
            Button { actions?.showGettingStarted() } label: { Text(L.gettingStartedMenu) }
                .disabled(actions == nil)
        }
    }

    /// The one main window, or a second one when there is none (closing the last window keeps the app
    /// running). The Settings window is never the main window.
    private func showMainWindow() {
        if let window = Self.existingMainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"

    private static func existingMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard !(window is NSPanel), window.styleMask.contains(.titled), window.canBecomeMain,
                  window.identifier?.rawValue != settingsWindowIdentifier else { return false }
            return window.isVisible || window.isMiniaturized
        }
    }

    /// The items that edit the selected draft (screens-flows.md §2c keyboard): lines, then the header
    /// choices as submenus with the current value checked. Disabled without an editor; the type and the
    /// currency of a payment tax document are those of its payment.
    @ViewBuilder private var editingItems: some View {
        let editor = actions?.editor
        let document = editor?.document
        let isReceipt = document?.kind == .paymentTaxDocument
        Button { editor?.addLineAndFocus() } label: { Text(L.addLine) }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(editor == nil)
        Button { editor?.deleteFocusedLine() } label: { Text(L.deleteLine) }
            .disabled(editor?.focusedLineID == nil)
        // No shortcuts for Delete Line and Move Line: screens-flows.md §1.4 keeps custom shortcuts few.
        Button { editor?.moveFocusedLine(by: -1) } label: { Text(L.moveLineUp) }
            .disabled(editor?.focusedLineID == nil)
        Button { editor?.moveFocusedLine(by: 1) } label: { Text(L.moveLineDown) }
            .disabled(editor?.focusedLineID == nil)
        Divider()
        Picker(selection: Binding(get: { document?.kind ?? .invoice }, set: { kind in editor?.setKind(kind) })) {
            ForEach(DraftEditorModel.kindOptions(for: document?.kind ?? .invoice), id: \.self) { kind in
                Text(kind.menuTitle).tag(kind)
            }
        } label: {
            Text(L.menuChangeType)
        }
        .disabled(editor == nil || isReceipt)
        Picker(selection: Binding(get: { document?.currency ?? .czk }, set: { currency in editor?.setCurrency(currency) })) {
            ForEach(Self.currencies(document?.currency), id: \.code) { currency in
                Text(verbatim: currency.code).tag(currency)
            }
        } label: {
            Text(L.menuCurrency)
        }
        .disabled(editor == nil || isReceipt)
        Picker(selection: Binding(get: { document?.language ?? .czech }, set: { language in editor?.setLanguage(language) })) {
            Text(L.languageCzech).tag(DocumentLanguage.czech)
            Text(L.languageEnglish).tag(DocumentLanguage.english)
        } label: {
            Text(L.menuDocumentLanguage)
        }
        .disabled(editor == nil)
        Picker(selection: Binding(get: { editor?.treatmentChoice ?? .czechVAT }, set: { choice in editor?.setTreatment(choice) })) {
            ForEach(TreatmentChoice.euChoices) { choice in
                Text(choice.menuTitle).tag(choice)
            }
            Divider()
            ForEach(TreatmentChoice.otherChoices) { choice in
                Text(choice.menuTitle).tag(choice)
            }
        } label: {
            Text(L.menuVATTreatment)
        }
        .disabled(editor == nil)
        Button {
            // The preview hides the rate form: the editor comes back first and takes the request (recheck N06).
            if actions?.previewShown == true { actions?.togglePreview?() }
            editor?.requestRateFocus()
        } label: { Text(L.menuEnterRate) }
            .disabled(editor?.needsExchangeRate != true)
    }

    /// The currencies the editor's header offers, plus the draft's own when it is another one.
    static func currencies(_ current: Currency?) -> [Currency] {
        var list: [Currency] = [.eur, .czk, .usd]
        if let current, !list.contains(current) { list.append(current) }
        return list
    }
}
