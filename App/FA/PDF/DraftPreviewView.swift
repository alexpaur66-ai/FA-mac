// The live preview of a draft (screens-flows.md §2c, ADR 0010): the PDF as it will print, with the three
// draft markers, rendered again 300 ms after the last change.

import InvoicingCore
import SwiftUI

struct DraftPreviewView: View {
    let model: DraftEditorModel

    @State private var data: Data?
    @State private var error: String?
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            if let data {
                PDFPagesView(data: data)
            } else if let error {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(L.pdfPreviewUnavailable).textRole(.body)
                    Text(verbatim: error).textRole(.caption)
                    Button { render() } label: { Text(L.retry) }
                }
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().padding(Spacing.xl)
            }
        }
        // Every change restarts the task, so a burst of edits renders once, 300 ms after the last one.
        .task(id: model.document) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            render()
        }
    }

    private func render() {
        guard let document = model.document else { return }
        do {
            data = try DocumentPDFService.draftPreview(document, profile: model.profile)
            error = nil
        } catch {
            data = nil
            self.error = ErrorText.message(error, locale: locale)
        }
    }
}
