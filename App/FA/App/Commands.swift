// The menu bar (screens-flows.md §1.4). The main window publishes what it can do through
// `focusedSceneValue`, so the menus follow the key window and its selection; an item whose action is
// nil is disabled, never hidden. The editor of the selected draft is published too, so the Document menu
// edits the draft from the keyboard (lines, type, currency, language, VAT treatment, rate).

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

    var reopenTitle: LocalizedStringResource {
        reopenKind == .markedForCreditNote ? L.removeCreditNoteMark : L.reopenAdvance
    }
}

struct MainActions {
    var show: @MainActor (SidebarItem) -> Void
    var newDocument: @MainActor (DocumentKind) -> Void
    var newClient: @MainActor () -> Void
    /// File ▸ Import ČNB Rates…: shows Exchange rates and opens the file importer.
    var importRates: @MainActor () -> Void
    /// Help ▸ Getting Started: the Overview with the setup card shown again.
    var showGettingStarted: @MainActor () -> Void
    var showDataFolder: (@MainActor () -> Void)?
    /// Nil in the sections without an inspector (Exchange rates, Exports & Backup).
    var toggleInspector: (@MainActor () -> Void)?
    var inspectorShown = false
    /// The Client menu: the client selected in Clients, or the client of the selected document.
    var clientName: String?
    var newDocumentForClient: (@MainActor (DocumentKind) -> Void)?
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
        // a new draft, so it lives here (⌘D) and names what it copies.
        CommandGroup(replacing: .newItem) {
            Button { actions?.newDocument(.invoice) } label: { Text(L.newInvoice) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button { actions?.newDocument(.advanceRequest) } label: { Text(L.newAdvance) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button { actions?.newClient() } label: { Text(L.newClient) }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(actions == nil)
            Divider()
            Button { actions?.document.duplicate?() } label: {
                Text(actions?.document.duplicateSourceNumber.map { L.duplicateNumbered($0) } ?? L.duplicateAsDraft)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(actions?.document.duplicate == nil)
            Divider()
            Button { actions?.importRates() } label: { Text(L.importRates) }
                .disabled(actions == nil)
            Divider()
            // The export step brings these three (screens-flows.md §2h); they are listed, disabled, until then.
            Button {} label: { Text(L.menuExportAccountant) }
                .disabled(true)
            Button {} label: { Text(L.backUpNow) }
                .disabled(true)
            Button {} label: { Text(L.restoreFromBackup) }
                .disabled(true)
        }

        // File ▸ Save PDF…, Show PDF in Finder and Print… (⌘P) follow the selected document (§1.4); ⌘S
        // stays unbound, drafts autosave. Show Data Folder is the one place the data file is reachable from.
        CommandGroup(after: .newItem) {
            Divider()
            Button { actions?.document.savePDF?() } label: { Text(L.savePDF) }
                .disabled(actions?.document.savePDF == nil)
            Button { actions?.document.showPDFInFinder?() } label: { Text(L.showPDFInFinder) }
                .disabled(actions?.document.showPDFInFinder == nil)
            Divider()
            Button { actions?.showDataFolder?() } label: { Text(L.showDataFolder) }
                .disabled(actions?.showDataFolder == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button { actions?.document.printDocument?() } label: { Text(L.printDocument) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions?.document.printDocument == nil)
        }

        SidebarCommands()
        ToolbarCommands()

        // View: section navigation ⌘1 … ⌘6, the inspector (⌥⌘I, never ⌃⌘I) and the text scale.
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(AppSection.allCases) { section in
                Button { actions?.show(.section(section)) } label: { Text(section.menuTitle) }
                    .keyboardShortcut(section.shortcutKey, modifiers: .command)
                    .disabled(actions == nil)
            }
            Divider()
            Button { actions?.toggleInspector?() } label: { Text(actions?.inspectorShown == true ? L.hideInspector : L.showInspector) }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(actions?.toggleInspector == nil)
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
            Button { document?.recordPayment?() } label: { Text(L.recordPayment) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(document?.recordPayment == nil)
            Button { document?.recordRefund?() } label: { Text(L.recordRefund) }
                .disabled(document?.recordRefund == nil)
            Button { document?.createTaxDocument?() } label: { Text(L.createTaxDocumentForPayment) }
                .disabled(document?.createTaxDocument == nil)
            Button { document?.createFinalInvoice?() } label: { Text(L.createFinalInvoice) }
                .disabled(document?.createFinalInvoice == nil)
            Divider()
            editingItems
            Divider()
            Button { document?.showClient?() } label: { Text(L.showClient) }
                .disabled(document?.showClient == nil)
            Divider()
            Button { document?.closeAdvanceUnpaid?() } label: { Text(L.closeAdvanceUnpaid) }
                .disabled(document?.closeAdvanceUnpaid == nil)
            Button { document?.markForCreditNote?() } label: { Text(L.markForCreditNote) }
                .disabled(document?.markForCreditNote == nil)
            Button { document?.reopen?() } label: { Text(document?.reopenTitle ?? L.reopen) }
                .disabled(document?.reopen == nil)
            Divider()
            Button { document?.deleteDraft?() } label: { Text(L.deleteDraft) }
                .disabled(document?.deleteDraft == nil)
        }

        // Client: the New items prefilled with the selected client, and their details (§1.4).
        CommandMenu(Text(L.menuClient)) {
            let name = actions?.clientName ?? ""
            Button { actions?.newDocumentForClient?(.invoice) } label: { Text(L.newInvoiceFor(name)) }
                .disabled(actions?.newDocumentForClient == nil)
            Button { actions?.newDocumentForClient?(.advanceRequest) } label: { Text(L.newAdvanceFor(name)) }
                .disabled(actions?.newDocumentForClient == nil)
            Divider()
            Button { actions?.editClient?() } label: { Text(L.editClientDetails) }
                .disabled(actions?.editClient == nil)
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
