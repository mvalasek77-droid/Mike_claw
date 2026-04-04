#!/usr/bin/env python3
"""Generate a syntax-highlighted PDF of all AppClaw Swift source files."""

import os
import glob
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.colors import HexColor, white, black
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, HRFlowable, Table, TableStyle
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.pdfgen import canvas as pdfcanvas
from reportlab.platypus import BaseDocTemplate, PageTemplate, Frame

# ── Colour palette (matches OpenClaw theme) ────────────────────────────────
BG_PAGE       = HexColor("#0D1117")   # Midnight Navy
BG_CODE       = HexColor("#161B22")   # Deep Slate
BG_HEADER     = HexColor("#1C2128")   # Card layer
BORDER        = HexColor("#30363D")
PRIMARY       = HexColor("#2F81F7")   # Electric Blue
ACCENT        = HexColor("#FF9F0A")   # Amber Claw
TEXT_PRIMARY  = HexColor("#E6EDF3")
TEXT_SECONDARY= HexColor("#8B949E")
TEXT_MUTED    = HexColor("#484F58")
SUCCESS       = HexColor("#3FB950")
KEYWORD_CLR   = HexColor("#FF7B72")   # Swift keyword red
STRING_CLR    = HexColor("#A5D6FF")   # String blue
COMMENT_CLR   = HexColor("#8B949E")   # Muted grey
TYPE_CLR      = HexColor("#FFA657")   # Type orange
FUNC_CLR      = HexColor("#D2A8FF")   # Function purple

# ── Swift keyword highlighter (very lightweight) ───────────────────────────
import re

KEYWORDS = {
    "import","func","var","let","struct","class","enum","protocol","actor",
    "extension","init","return","throws","throw","try","await","async","guard",
    "else","if","for","in","while","switch","case","default","break","continue",
    "static","private","public","internal","final","override","mutating",
    "nonisolated","weak","lazy","defer","nil","true","false","self","Self",
    "where","typealias","associatedtype","inout","some","any","@discardableResult",
    "@MainActor","@Published","@ViewBuilder","@escaping",
}

def escape_xml(s):
    return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

def highlight_line(line):
    """Return a ReportLab XML-annotated string for one Swift source line."""
    # Comments
    stripped = line.rstrip()
    if re.match(r'^\s*//', stripped):
        return f'<font color="#{COMMENT_CLR.hexval()}">{escape_xml(stripped)}</font>'

    result = []
    i = 0
    raw = stripped

    while i < len(raw):
        # String literal
        if raw[i] == '"':
            j = i + 1
            while j < len(raw) and (raw[j] != '"' or (j > 0 and raw[j-1] == '\\')):
                j += 1
            token = raw[i:j+1]
            result.append(f'<font color="#{STRING_CLR.hexval()}">{escape_xml(token)}</font>')
            i = j + 1
            continue

        # Word token
        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', raw[i:])
        if m:
            word = m.group()
            if word in KEYWORDS:
                result.append(f'<font color="#{KEYWORD_CLR.hexval()}">{escape_xml(word)}</font>')
            elif word[0].isupper():
                result.append(f'<font color="#{TYPE_CLR.hexval()}">{escape_xml(word)}</font>')
            else:
                result.append(escape_xml(word))
            i += len(word)
            continue

        result.append(escape_xml(raw[i]))
        i += 1

    return "".join(result)

# ── Page template with dark background ────────────────────────────────────

class DarkCanvas:
    """Mixin that paints the page background before content."""
    def __init__(self, bg=BG_PAGE):
        self.bg = bg

    def on_page(self, cnv, doc):
        cnv.saveState()
        cnv.setFillColor(self.bg)
        cnv.rect(0, 0, A4[0], A4[1], fill=1, stroke=0)
        # Footer
        cnv.setFillColor(TEXT_MUTED)
        cnv.setFont("Courier", 7)
        cnv.drawCentredString(A4[0]/2, 10*mm,
            f"AppClaw / OpenClaw  •  page {doc.page}  •  Hermes Agent Layer")
        # Top accent line
        cnv.setStrokeColor(ACCENT)
        cnv.setLineWidth(1.5)
        cnv.line(15*mm, A4[1]-12*mm, A4[0]-15*mm, A4[1]-12*mm)
        cnv.restoreState()


def build_pdf(output_path, source_dir):
    swift_files = sorted(glob.glob(os.path.join(source_dir, "*.swift")))

    dc = DarkCanvas()

    doc = SimpleDocTemplate(
        output_path,
        pagesize=A4,
        leftMargin=15*mm, rightMargin=15*mm,
        topMargin=18*mm, bottomMargin=18*mm,
        title="AppClaw — OpenClaw Hermes Agent Layer",
        author="OpenClaw",
    )

    # Override page callbacks
    doc.build  # keep reference

    code_font   = "Courier"
    code_size   = 6.5
    header_font = "Courier-Bold"

    story = []

    # ── Cover page ──────────────────────────────────────────────────────────
    cover_style = ParagraphStyle(
        "Cover", fontName="Courier-Bold", fontSize=26,
        textColor=ACCENT, alignment=TA_CENTER, spaceAfter=6,
    )
    sub_style = ParagraphStyle(
        "Sub", fontName="Courier", fontSize=13,
        textColor=PRIMARY, alignment=TA_CENTER, spaceAfter=4,
    )
    meta_style = ParagraphStyle(
        "Meta", fontName="Courier", fontSize=9,
        textColor=TEXT_SECONDARY, alignment=TA_CENTER, spaceAfter=3,
    )

    story.append(Spacer(1, 40*mm))
    story.append(Paragraph("🐻 OpenClaw", cover_style))
    story.append(Spacer(1, 4*mm))
    story.append(Paragraph("AppClaw — Hermes Agent Layer", sub_style))
    story.append(Spacer(1, 6*mm))
    story.append(HRFlowable(width="80%", thickness=1, color=ACCENT, spaceAfter=6*mm))
    story.append(Paragraph("Complete Swift Source Code", meta_style))
    story.append(Paragraph(f"{len(swift_files)} source files", meta_style))
    story.append(Spacer(1, 8*mm))

    # File index table
    tdata = [["File", "Description"]]
    descriptions = {
        "BearLogoView.swift":       "OpenClaw bear head logo (SwiftUI)",
        "HermesTheme.swift":        "OpenClaw colour palette & typography",
        "HermesMemory.swift":       "On-device memory store + MemoryIndex",
        "HermesIntegration.swift":  "High-level logging API",
        "HermesContextTracker.swift":"Sliding-window topic & intent detector",
        "HermesDreamEngine.swift":  "Autodream consolidation (5 phases)",
        "HermesProactiveEngine.swift":"Always-on suggestion engine",
        "HermesKairos.swift":       "15s budget proactive observer",
        "HermesToolRegistry.swift": "Metadata-first registry + 18-module security",
        "HermesSessionState.swift": "Crash-safe state, workflow, token budget",
        "HermesAgentHarness.swift": "Agent roles, harness, typed event stream",
    }
    for f in swift_files:
        name = os.path.basename(f)
        tdata.append([name, descriptions.get(name, "")])

    ts = TableStyle([
        ("BACKGROUND",  (0,0), (-1,0),  BG_HEADER),
        ("TEXTCOLOR",   (0,0), (-1,0),  ACCENT),
        ("TEXTCOLOR",   (0,1), (-1,-1), TEXT_PRIMARY),
        ("FONTNAME",    (0,0), (-1,-1), "Courier"),
        ("FONTNAME",    (0,0), (-1,0),  "Courier-Bold"),
        ("FONTSIZE",    (0,0), (-1,-1), 8),
        ("ROWBACKGROUNDS",(0,1),(-1,-1),[BG_CODE, BG_HEADER]),
        ("GRID",        (0,0), (-1,-1), 0.4, BORDER),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING",(0,0), (-1,-1), 6),
        ("TOPPADDING",  (0,0), (-1,-1), 3),
        ("BOTTOMPADDING",(0,0),(-1,-1), 3),
    ])
    col_w = [75*mm, 85*mm]
    t = Table(tdata, colWidths=col_w)
    t.setStyle(ts)
    story.append(t)
    story.append(PageBreak())

    # ── Source files ─────────────────────────────────────────────────────────
    file_header_style = ParagraphStyle(
        "FileHeader", fontName="Courier-Bold", fontSize=10,
        textColor=ACCENT, spaceAfter=2, spaceBefore=4,
        backColor=BG_HEADER, borderPad=4, leading=14,
    )
    code_style = ParagraphStyle(
        "Code", fontName=code_font, fontSize=code_size,
        textColor=TEXT_PRIMARY, leading=code_size * 1.45,
        spaceAfter=0, spaceBefore=0,
        backColor=BG_CODE, borderPad=0,
    )

    for filepath in swift_files:
        filename = os.path.basename(filepath)
        with open(filepath, encoding="utf-8") as fh:
            lines = fh.readlines()

        # File header bar
        story.append(Paragraph(f"  ◆  {filename}  ({len(lines)} lines)", file_header_style))
        story.append(HRFlowable(width="100%", thickness=0.5, color=BORDER, spaceAfter=1))

        for lineno, line in enumerate(lines, 1):
            display = line.rstrip("\n")
            # Truncate very long lines
            if len(display) > 120:
                display = display[:117] + "…"
            # Line number gutter
            gutter = f'<font color="#{TEXT_MUTED.hexval()}" size="{code_size-0.5}">{lineno:4d} </font>'
            hl = highlight_line(display) if display.strip() else escape_xml(display)
            para_xml = gutter + hl
            try:
                story.append(Paragraph(para_xml, code_style))
            except Exception:
                # Fall back to plain text if XML parsing fails
                safe = f'{lineno:4d} {escape_xml(display)}'
                story.append(Paragraph(safe, code_style))

        story.append(Spacer(1, 3*mm))
        story.append(PageBreak())

    # Build with dark background on every page
    dc_inst = DarkCanvas()
    doc.build(story, onFirstPage=dc_inst.on_page, onLaterPages=dc_inst.on_page)
    print(f"✅  PDF written to: {output_path}")
    print(f"   {len(swift_files)} files  •  {sum(len(open(f).readlines()) for f in swift_files)} total lines")


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    build_pdf(
        output_path=os.path.join(here, "AppClaw_SourceCode.pdf"),
        source_dir=os.path.join(here, "AppClaw"),
    )
