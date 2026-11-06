// The client page's Activity tab (screens-flows.md §2e, design-system.md §8.15): an "Add a note…" field at
// the top, then the client's notes and the events of their documents, newest first. ↩ in the field saves a
// note dated today (its day can be changed first); editing and deleting a note are undoable, ⌫ deletes the
// selected note, and ↩ or a double-click edits a note or shows an event's document. The model lives with the
// window, so an Undo still finds it after the page has changed.

import Foundation
import InvoicingCore
import InvoicingData
import Observation
import SwiftUI

/// One row of the Activity tab: a note, or an audit event of one of the client's documents.
struct ClientActivityEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case note(ClientNote)
        /// The event with the number and currency of its document.
        case event(AuditEvent, documentID: String, number: String, currency: Currency)
    }

    let id: String
    let kind: Kind
    /// Newest first: a note sorts at its day, at the time of day it was written; an event at its time.
    let sortDate: Date

    init(note: ClientNote) {
        id = "note:" + note.id
        kind = .note(note)
        sortDate = Self.sortDate(note)
    }

    init(event: AuditEvent, document: DocumentSummary) {
        id = "event:" + String(event.id)
        kind = .event(event, documentID: document.id, number: document.number ?? "", currency: document.currency)
        sortDate = (try? Date(event.at, strategy: .iso8601)) ?? .distantPast
    }

    var note: ClientNote? {
        if case .note(let note) = kind { return note }
        return nil
    }

    /// The note's day at the local time of day it was written, so notes of one day keep their order.
    private static func sortDate(_ note: ClientNote) -> Date {
        let midnight = note.day.midnight(in: .current)
        guard let written = try? Date(note.createdAt, strategy: .iso8601) else { return midnight }
        let writtenMidnight = CalendarDay(written, in: .current).midnight(in: .current)
        return midnight.addingTimeInterval(max(0, written.timeIntervalSince(writtenMidnight)))
    }

    /// Newest first; equal times by id, so the order never flickers. Two events by their audit row (the later
    /// one first), as numbers: "event:10" is newer than "event:9".
    static func newestFirst(_ lhs: ClientActivityEntry, _ rhs: ClientActivityEntry) -> Bool {
        if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
        if case .event(let left, _, _, _) = lhs.kind, case .event(let right, _, _, _) = rhs.kind, left.id != right.id {
            return left.id > right.id
        }
        return lhs.id > rhs.id
    }
}

@MainActor @Observable
final class ClientActivityModel {
    let stores: Stores
    /// What the last change could not do; cleared by the next one that works.
    private(set) var error: String?
    /// Bumped by every change and every Undo, so the shown tab reads the notes again.
    private(set) var version = 0
    /// The note a change or an Undo brought back: the tab selects it and scrolls to it (§8.15 "highlighted").
    private(set) var highlight: Highlight?
    /// File ▸ Add Note to “…”…: the client whose composer takes the focus when its tab shows.
    var pendingFocus: String?
    /// The window's undo manager, for the Redo an Undo registers.
    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var highlightToken = 0

    struct Highlight: Equatable {
        /// Changes with every highlight, so the same note twice is two events.
        let token: Int
        let entryID: String
    }

    init(stores: Stores) {
        self.stores = stores
    }

    private var notes: ClientNoteStore { stores.clientNotes }

    /// The client's notes and the events of `documents` (the client's), newest first.
    func entries(customerID: String, documents: [DocumentSummary]) throws -> [ClientActivityEntry] {
        let summaries = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = try notes.notes(customerID: customerID).map(ClientActivityEntry.init(note:))
        for event in try notes.documentEvents(documentIDs: summaries.keys.sorted()) {
            guard let summary = summaries[event.entityID] else { continue }
            result.append(ClientActivityEntry(event: event, document: summary))
        }
        return result.sorted(by: ClientActivityEntry.newestFirst)
    }

    // MARK: Changes, each undoable (screens-flows.md §2e)

    /// The composer's ↩: false when nothing was saved (the error says why, except for an empty field).
    @discardableResult
    func add(customerID: String, text: String, day: CalendarDay, undoManager: UndoManager?) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        self.undoManager = undoManager
        do {
            let note = try notes.add(customerID: customerID, text: text, day: day)
            changed()
            register(name: L.undoAddNote) { model in model.remove(note, name: L.undoAddNote) }
            return true
        } catch {
            self.error = ErrorText.message(error)
            return false
        }
    }

    /// The edit sheet's Save: nil when saved, else the reason for the sheet to show.
    func update(_ note: ClientNote, text: String, day: CalendarDay, undoManager: UndoManager?) -> String? {
        // Saved unchanged: nothing to write and nothing to undo (the stored text is already trimmed).
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == note.text && day == note.day { return nil }
        self.undoManager = undoManager
        do {
            try change(id: note.id, text: text, day: day)
            return nil
        } catch {
            return ErrorText.message(error)
        }
    }

    /// ⌫ or Delete Note: no confirmation, an Undo instead (screens-flows.md §4).
    func delete(_ note: ClientNote, undoManager: UndoManager?) {
        self.undoManager = undoManager
        remove(note, name: L.undoDeleteNote)
    }

    /// Writes the text and day; the Undo writes back what was there, and its Redo this again.
    private func change(id: String, text: String, day: CalendarDay) throws {
        let before = try notes.update(id: id, text: text, day: day)
        changed(highlighting: id)
        register(name: L.undoEditNote) { model in
            do {
                try model.change(id: before.id, text: before.text, day: before.day)
            } catch {
                model.error = ErrorText.message(error)
            }
        }
    }

    /// Deletes the note; `name` is the action the Undo or Redo this registers names (Add Note or Delete Note).
    private func remove(_ note: ClientNote, name: LocalizedStringResource) {
        do {
            try notes.delete(id: note.id)
            changed()
            register(name: name) { model in model.putBack(note, name: name) }
        } catch {
            self.error = ErrorText.message(error)
        }
    }

    /// Puts the note back; registers nothing when the store did not (its client is gone, or it is already there).
    private func putBack(_ note: ClientNote, name: LocalizedStringResource) {
        do {
            guard try notes.restore(note) else { return }
            changed(highlighting: note.id)
            register(name: name) { model in model.remove(note, name: name) }
        } catch {
            self.error = ErrorText.message(error)
        }
    }

    private func changed(highlighting noteID: String? = nil) {
        error = nil
        version += 1
        if let noteID {
            highlightToken += 1
            highlight = Highlight(token: highlightToken, entryID: "note:" + noteID)
        }
    }

    /// Registers `undo` on the window's undo manager. Registered while an Undo runs, it becomes the Redo.
    private func register(name: LocalizedStringResource, _ undo: @escaping @MainActor @Sendable (ClientActivityModel) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { undo(model) }
        }
        undoManager.setActionName(String(localized: name))
    }
}

struct ClientActivityView: View {
    let model: ClientActivityModel
    let customerID: String
    /// The client's documents: their events show here, and a change to them reads the tab again.
    let documents: [DocumentState]
    /// ↩ or a double-click on an event shows its document in Documents.
    var openDocument: (@MainActor (String) -> Void)? = nil

    @State private var entries: [ClientActivityEntry] = []
    @State private var loadError: String?
    @State private var draft = ""
    /// The composer's day; nil is today, whatever day it is when ↩ is pressed.
    @State private var pickedDay: Date?
    @State private var selection: Set<String> = []
    @State private var editing: ClientNote?
    /// The model's last highlight, applied by the reload that follows it, once the row is among `entries`.
    @State private var pendingHighlight: ClientActivityModel.Highlight?
    /// The row the list scrolls to once it shows the reloaded entries.
    @State private var scrollTarget: String?
    @FocusState private var composerFocused: Bool
    @Environment(\.undoManager) private var undoManager
    @Environment(\.locale) private var locale

    private struct LoadKey: Equatable {
        let customerID: String
        let version: Int
        let documents: [DocumentState]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            composer
            if let message = model.error ?? loadError {
                InlineMessage(message)
            }
            if entries.isEmpty {
                Text(L.noActivity).textRole(.rowSecondary)
                Spacer(minLength: 0)
            } else {
                timeline
            }
        }
        // Here rather than on the list, which is not there while the tab is empty (the Undo of its only note).
        .onChange(of: model.highlight) { _, highlight in
            pendingHighlight = highlight
        }
        .task(id: LoadKey(customerID: customerID, version: model.version, documents: documents)) { load() }
        .onChange(of: model.pendingFocus, initial: true) { _, client in
            guard client == customerID else { return }
            model.pendingFocus = nil
            // One turn later, so the field is in the window when the tab has only just been switched to.
            Task { @MainActor in composerFocused = true }
        }
        .sheet(item: $editing) { note in
            ClientNoteSheet(note: note) { text, day in
                model.update(note, text: text, day: day, undoManager: undoManager)
            }
        }
    }

    /// "Add a note…" and its day; ↩ saves.
    private var composer: some View {
        HStack(spacing: Spacing.s) {
            TextField(text: $draft, prompt: Text(L.addNotePrompt)) { Text(L.addNotePrompt) }
                .labelsHidden()
                .focused($composerFocused)
                .onSubmit(save)
            DatePicker(selection: Binding(get: { pickedDay ?? Date() }, set: { pickedDay = $0 }),
                       displayedComponents: .date) {
                Text(L.noteDay)
            }
            .labelsHidden()
            .fixedSize()
            .help(Text(L.noteDayHelp))
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(entries) { entry in
                    row(entry)
                        .tag(entry.id)
                        .id(entry.id)
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let note = note(in: ids) {
                    Button { editing = note } label: { Text(L.editNote) }
                    Button { model.delete(note, undoManager: undoManager) } label: { Text(L.deleteNote) }
                }
            } primaryAction: { ids in
                open(ids)
            }
            // ⌫ deletes the selected note; any other selection installs no action, so Delete is disabled.
            .onDeleteCommand(perform: deleteSelectedNote)
            // Set by the reload, so the row is in the list; initial, for a list that appears with it.
            .onChange(of: scrollTarget, initial: true) { _, target in
                guard let target else { return }
                scrollTarget = nil
                withAnimation { proxy.scrollTo(target) }
            }
        }
    }

    @ViewBuilder private func row(_ entry: ClientActivityEntry) -> some View {
        switch entry.kind {
        case .note(let note):
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: note.text).textRole(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: note.day.formatted(locale)).textRole(.caption)
            }
            .help(Text(verbatim: DocumentActivityList.timestamp(note.createdAt, locale: locale, full: true)))
            .accessibilityElement(children: .combine)
        case .event(let event, _, let number, let currency):
            // A system event: immutable, in the secondary style, starting with its document's number; a
            // Repair mode change carries the only Activity symbol (design-system.md §8.15).
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                if event.action == "repair" {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: Self.sentence(event, number: number, currency: currency, locale: locale))
                        .textRole(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: DocumentActivityList.timestamp(event.at, locale: locale)).textRole(.caption)
                }
            }
            .help(Text(verbatim: DocumentActivityList.timestamp(event.at, locale: locale, full: true)))
            .accessibilityElement(children: .combine)
        }
    }

    /// The issued view's sentence (design-system.md §8.15); "Issued as FV 2026-0042" already names the
    /// document, the others start with its number: "FV 2026-0042 · Received: 1 000,00 €".
    static func sentence(_ event: AuditEvent, number: String, currency: Currency, locale: Locale) -> String {
        let sentence = DocumentActivityList.sentence(event, currency: currency, locale: locale)
        guard event.action != "issue", !number.isEmpty else { return sentence }
        return String(localized: L.activityForDocument(number, sentence))
    }

    /// ⌫ on a selected note; nil for any other selection.
    private var deleteSelectedNote: (() -> Void)? {
        guard let note = note(in: selection) else { return nil }
        let model = model
        let undoManager = undoManager
        return { model.delete(note, undoManager: undoManager) }
    }

    /// The selected note, when exactly one note is selected.
    private func note(in ids: Set<String>) -> ClientNote? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return entries.first { $0.id == id }?.note
    }

    private func open(_ ids: Set<String>) {
        guard ids.count == 1, let id = ids.first, let entry = entries.first(where: { $0.id == id }) else { return }
        switch entry.kind {
        case .note(let note): editing = note
        case .event(_, let documentID, _, _): openDocument?(documentID)
        }
    }

    private func save() {
        let day = CalendarDay(pickedDay ?? Date(), in: .current)
        if model.add(customerID: customerID, text: draft, day: day, undoManager: undoManager) {
            draft = ""
            pickedDay = nil
        }
    }

    private func load() {
        do {
            entries = try model.entries(customerID: customerID, documents: documents.map(\.summary))
            loadError = nil
        } catch {
            loadError = ErrorText.message(error, locale: locale)
        }
        selection = selection.filter { id in entries.contains { $0.id == id } }
        // The note a change or an Undo brought back: selected and scrolled to now that it is a row (§8.15).
        if let highlight = pendingHighlight {
            pendingHighlight = nil
            if entries.contains(where: { $0.id == highlight.entryID }) {
                selection = [highlight.entryID]
                scrollTarget = highlight.entryID
            }
        }
    }
}

/// Edit Note…: the note's text and day.
struct ClientNoteSheet: View {
    let note: ClientNote
    /// nil when saved, else the reason to show.
    let save: @MainActor (String, CalendarDay) -> String?

    @State private var text: String
    @State private var day: Date
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    init(note: ClientNote, save: @escaping @MainActor (String, CalendarDay) -> String?) {
        self.note = note
        self.save = save
        _text = State(initialValue: note.text)
        _day = State(initialValue: note.day.midnight(in: .current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.editNoteTitle).textRole(.screenTitle)
            Form {
                TextField(text: $text) { Text(L.noteText) }
                DatePicker(selection: $day, displayedComponents: .date) { Text(L.noteDay) }
                if let problem {
                    InlineMessage(problem)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { commit() } label: { Text(L.save) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.xl)
        .formSheetSized(minWidth: 420, maxWidth: 560)
    }

    private func commit() {
        if let reason = save(text, CalendarDay(day, in: .current)) {
            problem = reason
        } else {
            dismiss()
        }
    }
}
