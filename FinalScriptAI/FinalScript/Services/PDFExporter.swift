import UIKit

/// Renders a screenplay to a properly laid-out US-Letter PDF in 12pt Courier
/// with industry-standard margins and per-element indentation. This is what a
/// writer hands to readers and what the share sheet / Files export produces.
enum PDFExporter {
    private static let pageSize = CGSize(width: 612, height: 792) // US Letter, 72dpi
    private static let charWidth: CGFloat = 7.2  // 12pt Courier @ 10 cpi
    private static let lineHeight: CGFloat = 12.0
    private static let topMargin: CGFloat = 72
    private static let bottomMargin: CGFloat = 72

    /// Left indent + text block width (in points) per element type.
    private static func layout(for type: ElementType) -> (indent: CGFloat, width: CGFloat) {
        switch type {
        case .sceneHeading, .action, .shot: return (108, 432) // 1.5" .. 7.5"
        case .character: return (266, 230)
        case .parenthetical: return (223, 200)
        case .dialogue: return (180, 252)
        case .transition: return (396, 144)
        case .centered: return (108, 432)
        default: return (108, 432)
        }
    }

    static func makePDF(for screenplay: Screenplay) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            var y = topMargin

            drawTitlePageIfNeeded(screenplay, context: context, y: &y)

            for element in screenplay.elements {
                if element.type == .pageBreak {
                    context.beginPage()
                    y = topMargin
                    continue
                }
                if element.type == .section || element.type == .synopsis { continue }

                let (indent, width) = layout(for: element.type)
                let text = element.formattedText
                let charsPerLine = max(1, Int(width / charWidth))
                let wrapped = wrap(text, charsPerLine: charsPerLine)
                let blockHeight = CGFloat(wrapped.count) * lineHeight + leadingSpace(for: element.type)

                if y + blockHeight > pageSize.height - bottomMargin {
                    context.beginPage()
                    y = topMargin
                }

                y += leadingSpace(for: element.type)
                let attrs = attributes(for: element.type)
                for lineText in wrapped {
                    if element.type == .transition {
                        let lineWidth = CGFloat(lineText.count) * charWidth
                        let x = indent + (width - lineWidth)
                        lineText.draw(at: CGPoint(x: max(108, x), y: y), withAttributes: attrs)
                    } else if element.type == .centered {
                        let lineWidth = CGFloat(lineText.count) * charWidth
                        let x = (pageSize.width - lineWidth) / 2
                        lineText.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
                    } else {
                        lineText.draw(at: CGPoint(x: indent, y: y), withAttributes: attrs)
                    }
                    y += lineHeight
                }
            }
        }
    }

    private static func drawTitlePageIfNeeded(_ screenplay: Screenplay,
                                              context: UIGraphicsPDFRendererContext,
                                              y: inout CGFloat) {
        let page = screenplay.titlePage
        let title = page.title.isEmpty ? screenplay.title : page.title
        guard !title.isEmpty else { return }

        let titleFont = UIFont(name: "Courier-Bold", size: 18) ?? .systemFont(ofSize: 18)
        let bodyFont = UIFont(name: "Courier", size: 12) ?? .systemFont(ofSize: 12)
        let center = NSMutableParagraphStyle(); center.alignment = .center

        func centered(_ s: String, font: UIFont, atY: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: center]
            let rect = CGRect(x: 72, y: atY, width: pageSize.width - 144, height: 30)
            s.draw(in: rect, withAttributes: attrs)
        }

        centered(title.uppercased(), font: titleFont, atY: 300)
        centered(page.credit, font: bodyFont, atY: 340)
        centered(page.author, font: bodyFont, atY: 360)
        if !page.source.isEmpty { centered(page.source, font: bodyFont, atY: 390) }
        if !page.contact.isEmpty { centered(page.contact, font: bodyFont, atY: 700) }

        context.beginPage()
        y = topMargin
    }

    private static func leadingSpace(for type: ElementType) -> CGFloat {
        switch type {
        case .sceneHeading, .action, .character, .transition, .shot: return lineHeight
        default: return 0
        }
    }

    private static func attributes(for type: ElementType) -> [NSAttributedString.Key: Any] {
        let bold = type == .sceneHeading
        let font = UIFont(name: bold ? "Courier-Bold" : "Courier", size: 12)
            ?? .monospacedSystemFont(ofSize: 12, weight: bold ? .bold : .regular)
        return [.font: font, .foregroundColor: UIColor.black]
    }

    /// Greedy word-wrap at a fixed column count, preserving hard line breaks.
    private static func wrap(_ text: String, charsPerLine: Int) -> [String] {
        guard !text.isEmpty else { return [""] }
        var result: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
                let candidate = current.isEmpty ? String(word) : current + " " + word
                if candidate.count <= charsPerLine {
                    current = candidate
                } else {
                    if !current.isEmpty { result.append(current) }
                    if word.count > charsPerLine {
                        // Break an over-long token.
                        var chunk = String(word)
                        while chunk.count > charsPerLine {
                            result.append(String(chunk.prefix(charsPerLine)))
                            chunk = String(chunk.dropFirst(charsPerLine))
                        }
                        current = chunk
                    } else {
                        current = String(word)
                    }
                }
            }
            result.append(current)
        }
        return result
    }
}
