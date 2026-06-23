import Foundation

/// Exports a screenplay to Final Draft's `.fdx` (FDX is XML). This is the
/// format professional production needs, so round-tripping to Final Draft is
/// table stakes for a "pro level" claim.
enum FDXExporter {
    static func export(_ screenplay: Screenplay) -> String {
        var paragraphs = ""
        for element in screenplay.elements {
            guard let fdxType = fdxType(for: element.type) else {
                if element.type == .pageBreak {
                    paragraphs += "    <Paragraph Type=\"Action\"><Text></Text></Paragraph>\n"
                }
                continue
            }
            let text = escape(element.formattedText)
            if let color = element.revisionColor {
                paragraphs += "    <Paragraph Type=\"\(fdxType)\" Revised=\"Yes\" RevisionColor=\"\(escape(color))\"><Text>\(text)</Text></Paragraph>\n"
            } else {
                paragraphs += "    <Paragraph Type=\"\(fdxType)\"><Text>\(text)</Text></Paragraph>\n"
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <FinalDraft DocumentType="Script" Template="No" Version="5">
          <Content>
        \(paragraphs)  </Content>
          <TitlePage>
            <Content>
              <Paragraph Alignment="Center"><Text>\(escape(screenplay.titlePage.title.isEmpty ? screenplay.title : screenplay.titlePage.title))</Text></Paragraph>
              <Paragraph Alignment="Center"><Text>\(escape(screenplay.titlePage.credit))</Text></Paragraph>
              <Paragraph Alignment="Center"><Text>\(escape(screenplay.titlePage.author))</Text></Paragraph>
            </Content>
          </TitlePage>
        </FinalDraft>
        """
    }

    private static func fdxType(for type: ElementType) -> String? {
        switch type {
        case .sceneHeading: return "Scene Heading"
        case .action: return "Action"
        case .character: return "Character"
        case .parenthetical: return "Parenthetical"
        case .dialogue: return "Dialogue"
        case .transition: return "Transition"
        case .shot: return "Shot"
        case .centered: return "Action"
        case .lyric: return "Action"
        case .section, .synopsis, .pageBreak: return nil
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
