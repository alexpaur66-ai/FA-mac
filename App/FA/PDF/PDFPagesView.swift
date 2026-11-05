// The pages of a PDF as white paper on the under-page background (design-system.md §4.1), stacked so
// they scroll with the surrounding content. PDFKit draws each page at twice its size for Retina displays.

import PDFKit
import SwiftUI

struct PDFPagesView: View {
    let data: Data

    @State private var pages: [NSImage] = []
    @State private var failed = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            if failed {
                HStack(spacing: Spacing.m) {
                    Text(L.pdfPreviewUnavailable).textRole(.rowSecondary)
                    Button { render() } label: { Text(L.retry) }
                }
            }
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                Image(nsImage: page)
                    .resizable()
                    .aspectRatio(page.size.width / max(page.size.height, 1), contentMode: .fit)
                    .background(Color.white)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .accessibilityLabel(Text(L.pdfPageOfPages(index + 1, pages.count)))
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .task(id: data) { render() }
    }

    private func render() {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            pages = []
            failed = true
            return
        }
        var images: [NSImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            images.append(page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox))
        }
        pages = images
        failed = false
    }
}
