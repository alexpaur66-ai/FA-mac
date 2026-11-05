import CoreGraphics
import CoreText
import Foundation

/// A Core Text font for the PDF. Helvetica is on every Mac, embeds as a subset and has the Czech glyphs;
/// the PDF has its own sizes and does not follow the HIG text styles (design-system.md §3).
struct PDFFont {
    let ctFont: CTFont
    let size: CGFloat

    init(name: String, size: CGFloat) {
        ctFont = CTFontCreateWithName(name as CFString, size, nil)
        self.size = size
    }

    static func regular(_ size: CGFloat) -> PDFFont { PDFFont(name: "Helvetica", size: size) }
    static func bold(_ size: CGFloat) -> PDFFont { PDFFont(name: "Helvetica-Bold", size: size) }

    var ascent: CGFloat { CTFontGetAscent(ctFont) }
    var descent: CGFloat { CTFontGetDescent(ctFont) }
    /// The natural height of one line (Helvetica has no built-in leading, so blocks add their own spacing).
    var lineHeight: CGFloat { ceil(ascent + descent + CTFontGetLeading(ctFont)) }
}

struct PDFTextStyle {
    let font: PDFFont
    let color: CGColor
}

enum PDFAlignment {
    case left, right, center
}

/// Writes pages into a PDF graphics context with a cursor measured from the top edge, so the layout code
/// reads top-down while Core Graphics keeps its bottom-left origin. Every drawing call takes `top`
/// coordinates and converts them once, here.
final class PDFPageWriter {
    let context: CGContext
    let pageSize: CGSize
    let marginLeft: CGFloat
    let marginRight: CGFloat
    let marginTop: CGFloat
    let marginBottom: CGFloat
    /// Space kept free above the bottom margin for the running footer.
    var footerHeight: CGFloat = 22

    /// The cursor: distance from the top edge of the current page.
    private(set) var y: CGFloat = 0
    /// 1-based number of the current page; 0 before the first page.
    private(set) var page = 0

    /// Called when a page starts, with the page number; draws the watermark and the continuation header.
    var onPageStart: ((PDFPageWriter, Int) -> Void)?
    /// Called before a page ends, with the page number; draws the footer.
    var onPageEnd: ((PDFPageWriter, Int) -> Void)?

    init(context: CGContext, pageSize: CGSize, marginLeft: CGFloat, marginRight: CGFloat, marginTop: CGFloat, marginBottom: CGFloat) {
        self.context = context
        self.pageSize = pageSize
        self.marginLeft = marginLeft
        self.marginRight = marginRight
        self.marginTop = marginTop
        self.marginBottom = marginBottom
    }

    var contentLeft: CGFloat { marginLeft }
    var contentRight: CGFloat { pageSize.width - marginRight }
    var contentWidth: CGFloat { contentRight - contentLeft }
    /// The lowest `top` coordinate content may reach on a page.
    var bottomLimit: CGFloat { pageSize.height - marginBottom - footerHeight }
    var remainingHeight: CGFloat { bottomLimit - y }

    func startPage() {
        context.beginPDFPage(nil)
        page += 1
        y = marginTop
        onPageStart?(self, page)
    }

    func finishPage() {
        onPageEnd?(self, page)
        context.endPDFPage()
    }

    /// Starts a new page when `height` does not fit below the cursor. Returns true when it did.
    @discardableResult
    func ensure(_ height: CGFloat) -> Bool {
        guard y + height > bottomLimit else { return false }
        finishPage()
        startPage()
        return true
    }

    func move(_ dy: CGFloat) { y += dy }
    func moveTo(_ top: CGFloat) { y = top }

    // MARK: Text

    private func attributed(_ text: String, _ style: PDFTextStyle) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): style.font.ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color,
        ])
    }

    /// The width of `text` set on one line.
    func width(of text: String, _ style: PDFTextStyle) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(text, style))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Draws one line of text at `top`, truncated with an ellipsis when it is wider than `width`.
    /// Returns the line height.
    @discardableResult
    func text(_ text: String, _ style: PDFTextStyle, x: CGFloat, top: CGFloat, width: CGFloat, alignment: PDFAlignment = .left) -> CGFloat {
        guard !text.isEmpty else { return style.font.lineHeight }
        var line = CTLineCreateWithAttributedString(attributed(text, style))
        var lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if lineWidth > width, let truncated = CTLineCreateTruncatedLine(line, Double(width), .end, nil) {
            line = truncated
            lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        let startX: CGFloat
        switch alignment {
        case .left: startX = x
        case .right: startX = x + width - lineWidth
        case .center: startX = x + (width - lineWidth) / 2
        }
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: startX, y: pageSize.height - top - style.font.ascent)
        CTLineDraw(line, context)
        context.restoreGState()
        return style.font.lineHeight
    }

    /// The height `text` needs when wrapped to `width`.
    func height(of text: String, _ style: PDFTextStyle, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(attributed(text, style))
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(size.height) + 1
    }

    /// Draws `text` wrapped to `width` with its first line at `top`. Returns the height used.
    @discardableResult
    func paragraph(_ text: String, _ style: PDFTextStyle, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let setter = CTFramesetterCreateWithAttributedString(attributed(text, style))
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        let height = ceil(size.height) + 1
        let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
        return height
    }

    /// Large text across the page centre, rising at 45°: the draft watermark.
    func watermark(_ text: String, _ style: PDFTextStyle) {
        let line = CTLineCreateWithAttributedString(attributed(text, style))
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.translateBy(x: pageSize.width / 2, y: pageSize.height / 2)
        context.rotate(by: .pi / 4)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -lineWidth / 2, y: -style.font.size / 3)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: Shapes

    /// A horizontal rule at `top`.
    func rule(top: CGFloat, x: CGFloat, width: CGFloat, color: CGColor, lineWidth: CGFloat = 0.5) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        let lineY = pageSize.height - top
        context.move(to: CGPoint(x: x, y: lineY))
        context.addLine(to: CGPoint(x: x + width, y: lineY))
        context.strokePath()
        context.restoreGState()
    }

    /// Fills a rectangle given in top coordinates.
    func fill(_ rect: CGRect, color: CGColor) {
        context.saveGState()
        context.setFillColor(color)
        context.fill(flipped(rect))
        context.restoreGState()
    }

    /// Strokes a dashed rectangle given in top coordinates (the QR placeholder of a draft).
    func dashedBox(_ rect: CGRect, color: CGColor) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(0.75)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.stroke(flipped(rect))
        context.restoreGState()
    }

    /// Draws a QR code as filled squares, one per dark module, so it stays sharp at any zoom and in print.
    func qrCode(_ modules: QRModules, in rect: CGRect, color: CGColor) {
        let module = rect.width / CGFloat(modules.size)
        var squares: [CGRect] = []
        squares.reserveCapacity(modules.size * modules.size / 2)
        for row in 0..<modules.size {
            for column in 0..<modules.size where modules.isDark(row: row, column: column) {
                let top = rect.minY + CGFloat(row) * module
                let x = rect.minX + CGFloat(column) * module
                // A hair of overlap, so viewers draw no light seams between neighbouring squares.
                squares.append(CGRect(x: x, y: pageSize.height - top - module - 0.05, width: module + 0.05, height: module + 0.05))
            }
        }
        context.saveGState()
        context.setFillColor(color)
        context.fill(squares)
        context.restoreGState()
    }

    private func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: pageSize.height - rect.minY - rect.height, width: rect.width, height: rect.height)
    }
}
