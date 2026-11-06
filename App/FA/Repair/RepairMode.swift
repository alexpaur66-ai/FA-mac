// Repair mode (screens-flows.md §2m, design-system.md §8.18): the last resort for an issued record that is
// wrong, behind a reason and Touch ID or the password. While it is on, a banner says so in every main window;
// every change is written to the audit log with its reason; 10 minutes without a change end it, and so does
// quitting. There is no trace-free path: the store refuses a change to a locked record without its audit event.

import AppKit
import InvoicingCore
import InvoicingData
import InvoicingPDF
import LocalAuthentication
import Observation
import SwiftUI

@MainActor @Observable
final class RepairModeModel {
    private(set) var isOn = false
    /// The reason given when the mode was turned on; each change's reason starts from it.
    private(set) var reason = ""
    /// The changes logged since the mode was turned on.
    private(set) var changeCount = 0
    /// The mode ended by itself: the banner says so until it is closed (nothing changes silently, §2m).
    var endedByTimeout = false
    /// The result line for the windows when the mode ends: "Repair mode ended · 3 changes logged".
    private(set) var endedNotice: Notice?

    struct Notice: Equatable {
        /// Changes with every notice, so two endings in a row are two notices.
        let token: Int
        let text: String
    }

    /// 10 minutes without a change end the mode (§2m).
    static let idleLimit: Duration = .seconds(600)

    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var noticeToken = 0

    /// Asks for Touch ID, the Apple Watch or the password; on success the mode is on. False when the user
    /// cancelled or authentication failed: nothing unlocks.
    func turnOn(reason: String) async -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard await Self.authenticate(prompt: String(localized: L.repairAuthPrompt)) else { return false }
        self.reason = trimmed
        changeCount = 0
        endedByTimeout = false
        isOn = true
        restartTimer()
        return true
    }

    /// Counts logged changes and restarts the idle timer.
    func noteChanges(_ count: Int) {
        guard isOn else { return }
        changeCount += count
        restartTimer()
    }

    /// End Repair Mode (the banner, the File menu): the locks are back, the result line counts the changes.
    func end() {
        guard isOn else { return }
        isOn = false
        timer?.cancel()
        timer = nil
        noticeToken += 1
        let text = changeCount == 1 ? String(localized: L.repairEndedOne) : String(localized: L.repairEnded(changeCount))
        endedNotice = Notice(token: noticeToken, text: text)
    }

    /// A restore replaces the data: the mode ends without a result line.
    func endQuietly() {
        isOn = false
        timer?.cancel()
        timer = nil
    }

    private func restartTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLimit)
            guard !Task.isCancelled, let self, self.isOn else { return }
            self.end()
            self.endedByTimeout = true
        }
    }

    /// `LAPolicy.deviceOwnerAuthentication`: Touch ID first when it is set up, else the password; a fresh
    /// context each time, so an earlier unlock is never reused (§2m).
    nonisolated private static func authenticate(prompt: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: prompt)
        } catch {
            return false
        }
    }
}

/// File ▸ Repair Mode…: the reason, then Unlock…, which asks for Touch ID or the password.
struct RepairModeSheet: View {
    let repairMode: RepairModeModel

    @State private var reason = ""
    @State private var problem = false
    @State private var unlocking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.repairTurnOnTitle).textRole(.screenTitle)
            Text(L.repairTurnOnText).textRole(.body)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(text: $reason, prompt: Text(L.repairReasonPrompt)) { Text(L.repairReason) }
                    .onSubmit(unlock)
                if problem {
                    InlineMessage(L.repairNotUnlocked)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { unlock() } label: { Text(L.repairUnlock) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unlocking)
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 460, maxWidth: 560)
    }

    private func unlock() {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !unlocking else { return }
        problem = false
        unlocking = true
        let text = reason
        Task { @MainActor in
            let unlocked = await repairMode.turnOn(reason: text)
            unlocking = false
            if unlocked {
                dismiss()
            } else {
                problem = true
            }
        }
    }
}

/// The bar across the top of the content while the mode is on, or after it ended by itself (§2m, §8.18):
/// a symbol and the caution tone, never colour alone, and never hidden on a timer.
struct RepairModeBanner: View {
    let repairMode: RepairModeModel

    var body: some View {
        if repairMode.isOn {
            bar(text: Text(L.repairBanner)) {
                Button { repairMode.end() } label: { Text(L.repairEnd) }
                    .buttonStyle(.bordered)
            }
        } else if repairMode.endedByTimeout {
            bar(text: Text(L.repairEndedByTimeout)) {
                Button { repairMode.endedByTimeout = false } label: {
                    Label { Text(L.close) } icon: { Image(systemName: "xmark") }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(Text(L.close))
            }
        }
    }

    private func bar<Trailing: View>(text: Text, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "lock.open.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            text.textRole(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.m)
            trailing()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .accessibilityElement(children: .contain)
    }
}

/// Repair… on an issued document (§2m): the client's details as printed (or the client's current details),
/// the due date, the order reference and the note, with the change's reason. Save writes the change, its
/// audit events and a new PDF in one go; the old PDF stays.
struct DocumentRepairSheet: View {
    let document: Document
    /// The client as stored now; its details can replace the ones printed on the document.
    let currentCustomer: Customer?
    /// nil when saved, else the reason to show.
    let save: @MainActor (DocumentHeaderRepair, String) -> String?

    @State private var useCurrentDetails: Bool
    @State private var dueDate: Date
    @State private var orderReference: String
    @State private var note: String
    @State private var reason: String
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(document: Document, currentCustomer: Customer?, reason: String,
         save: @escaping @MainActor (DocumentHeaderRepair, String) -> String?) {
        self.document = document
        self.currentCustomer = currentCustomer
        self.save = save
        let differs = currentCustomer.map { $0.party != document.customer } ?? false
        _useCurrentDetails = State(initialValue: differs)
        _dueDate = State(initialValue: document.dueDate.midnight(in: .current))
        _orderReference = State(initialValue: document.orderReference ?? "")
        _note = State(initialValue: document.note ?? "")
        _reason = State(initialValue: reason)
    }

    private var currentDiffers: Bool {
        currentCustomer.map { $0.party != document.customer } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.repairDocumentTitle(document.number ?? "")).textRole(.screenTitle)
            Text(L.repairDocumentText).textRole(.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                Section {
                    LabeledContent {
                        Text(verbatim: Self.partyText(document.customer)).textRole(.body).textSelection(.enabled)
                    } label: {
                        Text(L.repairClientOnDocument)
                    }
                    if let currentCustomer, currentDiffers {
                        Toggle(isOn: $useCurrentDetails) { Text(L.repairUseCurrentDetails) }
                        LabeledContent {
                            Text(verbatim: Self.partyText(currentCustomer.party)).textRole(.body).textSelection(.enabled)
                        } label: {
                            Text(L.repairClientNow)
                        }
                    } else {
                        Text(L.repairClientHint).textRole(.rowSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    DatePicker(selection: $dueDate, displayedComponents: .date) { Text(L.dueOn) }
                    TextField(text: $orderReference) { Text(L.repairOrderReference) }
                    TextField(text: $note) { Text(L.repairNote) }
                }
                Section {
                    TextField(text: $reason, prompt: Text(L.repairReasonPrompt)) { Text(L.repairReason) }
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
                Button { commit() } label: { Text(L.repairSave) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 520, maxWidth: 660)
    }

    private func commit() {
        var repair = DocumentHeaderRepair(document)
        if useCurrentDetails, currentDiffers, let currentCustomer {
            repair.customer = currentCustomer.party
        }
        repair.dueDate = CalendarDay(dueDate, in: .current)
        repair.orderReference = orderReference
        repair.note = note
        if let message = save(repair, reason) {
            problem = message
        } else {
            dismiss()
        }
    }

    /// The name, the address lines, IČO and DIČ, one per line.
    static func partyText(_ party: Party) -> String {
        var lines = [party.name] + party.address.lines()
        if let ico = party.identificationNumber { lines.append("IČO " + ico.digits) }
        if let vat = party.vatIdentifier { lines.append("DIČ " + vat.value) }
        return lines.joined(separator: "\n")
    }
}

extension RepairField {
    /// The field's name in a repair event: "Client address: Krátká 1 → Nová 5 · Wrong address".
    var title: LocalizedStringResource {
        switch self {
        case .customerName: L.repairFieldClientName
        case .customerAddress: L.repairFieldClientAddress
        case .customerCompanyID: L.repairFieldClientCompanyID
        case .customerVATID: L.repairFieldClientVATID
        case .customerRegistry: L.repairFieldClientRegistry
        case .customerEmail: L.repairFieldClientEmail
        case .customerPhone: L.repairFieldClientPhone
        case .dueDate: L.dueOn
        case .orderReference: L.repairOrderReference
        case .note: L.repairNote
        }
    }
}

/// Stores the repairs of one window and registers their Undo. An Undo is itself a repair, logged with the
/// reason "Undo: ‹reason›", and its Redo repeats the change with the original reason (§2m). The window takes
/// these registrations off its stack when the mode ends.
@MainActor @Observable
final class DocumentRepairer {
    let stores: Stores
    let repairMode: RepairModeModel
    /// What the last repair or Undo did, for the window's result line; a new token each time.
    private(set) var outcome: Outcome?
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var token = 0

    struct Outcome: Equatable {
        let token: Int
        let text: String
        let isProblem: Bool
        /// The document whose PDF changed, so its view reloads it.
        let documentID: String?
    }

    init(stores: Stores, repairMode: RepairModeModel) {
        self.stores = stores
        self.repairMode = repairMode
    }

    /// Save Repair: nil when stored, else the reason for the sheet to show.
    func save(documentID: String, repair: DocumentHeaderRepair, reason: String, undoManager: UndoManager?) -> String? {
        self.undoManager = undoManager
        do {
            try perform(documentID: documentID, repair: repair, reason: reason, asUndo: false)
            return nil
        } catch {
            return ErrorText.message(error)
        }
    }

    /// The new PDF is rendered from the repaired document first; the change, its audit events and the PDF
    /// are then stored in one transaction.
    private func perform(documentID: String, repair: DocumentHeaderRepair, reason: String, asUndo: Bool) throws {
        guard repairMode.isOn else { throw RepairModeError.off }
        let logged = asUndo ? String(localized: L.repairUndoReason(reason)) : reason
        let preview = try stores.repairs.preview(documentID: documentID, repair: repair)
        let pdf = try DocumentPDF.render(preview)
        let result = try stores.repairs.repair(documentID: documentID, repair: repair, reason: logged, pdf: pdf)
        repairMode.noteChanges(result.changes.count)
        let number = result.document.number ?? ""
        let text = result.changes.count == 1
            ? String(localized: L.repairDoneOne(number)) : String(localized: L.repairDone(number, result.changes.count))
        report(text, isProblem: false, documentID: documentID)
        let before = result.before
        register { repairer in
            do {
                try repairer.perform(documentID: documentID, repair: before, reason: reason, asUndo: !asUndo)
            } catch {
                repairer.report(ErrorText.message(error), isProblem: true, documentID: nil)
            }
        }
    }

    private func report(_ text: String, isProblem: Bool, documentID: String?) {
        token += 1
        outcome = Outcome(token: token, text: text, isProblem: isProblem, documentID: documentID)
    }

    /// Registered while an Undo runs, it becomes the Redo.
    private func register(_ action: @escaping @MainActor @Sendable (DocumentRepairer) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { repairer in
            MainActor.assumeIsolated { action(repairer) }
        }
        undoManager.setActionName(String(localized: L.undoRepair))
    }

    /// The mode ended: its changes can no longer be undone from the Edit menu.
    func dropUndo() {
        undoManager?.removeAllActions(withTarget: self)
    }
}

enum RepairModeError: Error {
    /// The mode ended before the change was saved.
    case off
}
