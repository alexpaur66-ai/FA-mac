// The menu bar (screens-flows.md §1.4). The main window publishes what it can do through
// `focusedSceneValue`, so the menus follow the key window and its selection; an item whose action is
// nil is disabled, never hidden. The editor of the selected draft is published too, so the Document menu
// edits the draft from the keyboard (lines, type, currency, language, VAT treatment, rate).

import InvoicingCore
import SwiftUI

struct MainActions {
    var show: @MainActor (SidebarItem) -> Void
    var newDocument: @MainActor (DocumentKind) -> Void
    var newClient: @MainActor () -> Void
    var toggleInspector: @MainActor () -> Void
    var recordPayment: (@MainActor () -> Void)?
    var deleteDraft: (@MainActor () -> Void)?
    var closeAdvanceUnpaid: (@MainActor () -> Void)?
    var markForCreditNote: (@MainActor () -> Void)?
    var reopen: (@MainActor () -> Void)?
    var issue: (@MainActor () -> Void)?
    var duplicate: (@MainActor () -> Void)?
    /// The number of the issued document Duplicate would copy: "Duplicate FV-2026-007 as Draft".
    var duplicateSourceNumber: String?
    var createFinalInvoice: (@MainActor () -> Void)?
    var createTaxDocument: (@MainActor () -> Void)?
    var savePDF: (@MainActor () -> Void)?
    var showPDFInFinder: (@MainActor () -> Void)?
    var printDocument: (@MainActor () -> Void)?
    /// View ▸ Show/Hide Preview on a draft in the editor; `previewShown` picks the title.
    var togglePreview: (@MainActor () -> Void)?
    var previewShown = false
    /// The editor of the selected draft, for the Document menu's editing items.
    var editor: DraftEditorModel?
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
            Button { actions?.duplicate?() } label: {
                Text(actions?.duplicateSourceNumber.map { L.duplicateNumbered($0) } ?? L.duplicate)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(actions?.duplicate == nil)
        }

        // File ▸ Save PDF…, Show PDF in Finder and Print… (⌘P) follow the selected document (§1.4); ⌘S
        // stays unbound, drafts autosave.
        CommandGroup(after: .newItem) {
            Divider()
            Button { actions?.savePDF?() } label: { Text(L.savePDF) }
                .disabled(actions?.savePDF == nil)
            Button { actions?.showPDFInFinder?() } label: { Text(L.showPDFInFinder) }
                .disabled(actions?.showPDFInFinder == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button { actions?.printDocument?() } label: { Text(L.printDocument) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(actions?.printDocument == nil)
        }

        SidebarCommands()
        ToolbarCommands()

        // View: section navigation ⌘1 … ⌘6, the inspector (⌥⌘I, never ⌃⌘I) and the text scale.
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(AppSection.allCases) { section in
                Button { actions?.show(.section(section)) } label: { Text(section.title) }
                    .keyboardShortcut(section.shortcutKey, modifiers: .command)
                    .disabled(actions == nil)
            }
            Divider()
            Button { actions?.toggleInspector() } label: { Text(L.toggleInspector) }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(actions == nil)
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
            Button { actions?.issue?() } label: { Text(L.issue) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(actions?.issue == nil)
            Button { actions?.recordPayment?() } label: { Text(L.recordPayment) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions?.recordPayment == nil)
            Button { actions?.createTaxDocument?() } label: { Text(L.createTaxDocumentForPayment) }
                .disabled(actions?.createTaxDocument == nil)
            Button { actions?.createFinalInvoice?() } label: { Text(L.createFinalInvoice) }
                .disabled(actions?.createFinalInvoice == nil)
            Divider()
            editingItems
            Divider()
            Button { actions?.closeAdvanceUnpaid?() } label: { Text(L.closeAdvanceUnpaid) }
                .disabled(actions?.closeAdvanceUnpaid == nil)
            Button { actions?.markForCreditNote?() } label: { Text(L.markForCreditNote) }
                .disabled(actions?.markForCreditNote == nil)
            Button { actions?.reopen?() } label: { Text(L.reopen) }
                .disabled(actions?.reopen == nil)
            Divider()
            Button { actions?.deleteDraft?() } label: { Text(L.deleteDraft) }
                .disabled(actions?.deleteDraft == nil)
        }

        // Window ▸ Main Window reopens the main window when it was closed (§1.1).
        CommandGroup(after: .windowList) {
            Button { openWindow(id: "main") } label: { Text(L.mainWindow) }
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
                Text(verbatim: kind.pickerTitle).tag(kind)
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
            ForEach(TreatmentChoice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        } label: {
            Text(L.menuVATTreatment)
        }
        .disabled(editor == nil)
        Button { editor?.requestRateFocus() } label: { Text(L.menuEnterRate) }
            .disabled(editor?.needsExchangeRate != true)
    }

    /// The currencies the editor's header offers, plus the draft's own when it is another one.
    private static func currencies(_ current: Currency?) -> [Currency] {
        var list: [Currency] = [.eur, .czk, .usd]
        if let current, !list.contains(current) { list.append(current) }
        return list
    }
}
