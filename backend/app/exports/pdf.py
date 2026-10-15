"""PDF renderer (ReportLab), the Mantix report layout shared by every report: logo and title
on every page, a metadata box with icons, the table with a dark header, zebra rows and
coloured status pills, a «Resumen general» of four-per-row cards, and a footer with
«Página X de Y». No charts here (Excel keeps them)."""

import io
from datetime import UTC, datetime
from typing import Any
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas as pdf_canvas
from reportlab.platypus import (
    BaseDocTemplate,
    Flowable,
    Frame,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from app.exports import theme
from app.exports.formatting import EMPTY, format_value, status_tone, total_text
from app.exports.model import ExportColumn, ReportExport, SummaryLine, Tone

MARGIN = 10 * mm
HEADER_HEIGHT = 32 * mm
FOOTER_HEIGHT = 14 * mm
#: A table with more columns than this is printed on a landscape page.
LANDSCAPE_FROM = 6
FONT_SIZE = 7.5
#: Horizontal padding inside a cell (left + right), in points.
CELL_PAD = 8
MAX_TEXT_COLUMN = 70 * mm
MIN_TEXT_COLUMN = 24 * mm


def _color(hex_value: str) -> colors.Color:
    return colors.HexColor(f"#{hex_value}")


DEEP, SLATE, GREY, ZEBRA = (
    _color(theme.DEEP),
    _color(theme.SLATE),
    _color(theme.GREY),
    _color(theme.ZEBRA),
)
INK = _color(theme.INK)

_ALIGN = {"left": TA_LEFT, "right": TA_RIGHT, "center": TA_CENTER}
_BASE = ParagraphStyle(
    "base", fontName="Helvetica", fontSize=8, leading=10, textColor=INK
)
CELL = {
    name: ParagraphStyle(
        f"cell-{name}", parent=_BASE, fontSize=FONT_SIZE, leading=9, alignment=value
    )
    for name, value in _ALIGN.items()
}
HEAD = {
    name: ParagraphStyle(
        f"head-{name}",
        parent=CELL[name],
        fontName="Helvetica-Bold",
        textColor=colors.white,
    )
    for name in _ALIGN
}
SECTION = ParagraphStyle(
    "section",
    parent=_BASE,
    fontName="Helvetica-Bold",
    fontSize=10,
    leading=13,
    textColor=DEEP,
    spaceBefore=10,
)
SUBSECTION = ParagraphStyle(
    "subsection",
    parent=_BASE,
    fontName="Helvetica-Bold",
    fontSize=8.5,
    textColor=SLATE,
    spaceBefore=6,
    spaceAfter=2,
)


class _NumberedCanvas(pdf_canvas.Canvas):  # type: ignore[misc]
    """Keeps every page until the end so the footer can say "Página X de Y"."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._states: list[dict[str, Any]] = []

    def showPage(self) -> None:
        self._states.append(dict(self.__dict__))
        self._startPage()

    def save(self) -> None:
        total = len(self._states)
        for state in self._states:
            self.__dict__.update(state)
            self._footer(total)
            super().showPage()
        super().save()

    def _footer(self, total: int) -> None:
        width = self._pagesize[0]
        self.setStrokeColor(GREY)
        self.setLineWidth(0.5)
        self.line(
            MARGIN, FOOTER_HEIGHT - 3 * mm, width - MARGIN, FOOTER_HEIGHT - 3 * mm
        )
        self.setFont("Helvetica", 7.5)
        self.setFillColor(SLATE)
        self.drawString(MARGIN, FOOTER_HEIGHT - 7 * mm, theme.FOOTER_TEXT)
        self.drawRightString(
            width - MARGIN,
            FOOTER_HEIGHT - 7 * mm,
            f"Página {self._pageNumber} de {total}",
        )


def _tone(name: Tone) -> tuple[colors.Color, colors.Color, colors.Color]:
    background, text, accent = theme.TONES[name]
    return _color(background), _color(text), _color(accent)


def _fit(text: str, font: str, size: float, width: float) -> str:
    """`text` cut with an ellipsis so it never runs past `width`."""
    if stringWidth(text, font, size) <= width:
        return text
    while text and stringWidth(text + "…", font, size) > width:
        text = text[:-1]
    return text + "…"


def _icon(
    canvas: pdf_canvas.Canvas, kind: str, cx: float, cy: float, color: colors.Color
) -> None:
    """Small line icons (document, calendar, person, database, filter, check, clock, warning)."""
    canvas.saveState()
    canvas.setStrokeColor(color)
    canvas.setFillColor(color)
    canvas.setLineWidth(1)
    if kind == "calendar":
        canvas.roundRect(cx - 4.5, cy - 4, 9, 8.5, 1.2, stroke=1, fill=0)
        canvas.line(cx - 4.5, cy + 1.5, cx + 4.5, cy + 1.5)
        canvas.line(cx - 2, cy + 3.2, cx - 2, cy + 5.2)
        canvas.line(cx + 2, cy + 3.2, cx + 2, cy + 5.2)
    elif kind == "person":
        canvas.circle(cx, cy + 2, 2.2, stroke=1, fill=0)
        canvas.arc(cx - 4.2, cy - 6, cx + 4.2, cy + 1, 0, 180)
    elif kind == "database":
        for step in (3.0, 0.0, -3.0):
            canvas.ellipse(
                cx - 4, cy + step - 1.4, cx + 4, cy + step + 1.4, stroke=1, fill=0
            )
    elif kind == "check":
        path = canvas.beginPath()
        path.moveTo(cx - 4, cy)
        path.lineTo(cx - 1, cy - 3)
        path.lineTo(cx + 4.5, cy + 3.5)
        canvas.setLineWidth(1.6)
        canvas.drawPath(path, stroke=1, fill=0)
    elif kind == "clock":
        canvas.circle(cx, cy, 4.5, stroke=1, fill=0)
        canvas.line(cx, cy, cx, cy + 2.8)
        canvas.line(cx, cy, cx + 2.4, cy - 1.2)
    elif kind == "warning":
        path = canvas.beginPath()
        path.moveTo(cx, cy + 5)
        path.lineTo(cx + 5, cy - 4)
        path.lineTo(cx - 5, cy - 4)
        path.close()
        canvas.drawPath(path, stroke=1, fill=0)
        canvas.line(cx, cy + 2, cx, cy - 1)
        canvas.circle(cx, cy - 2.6, 0.5, stroke=0, fill=1)
    elif kind == "list":
        for dy in (3.5, 0, -3.5):
            canvas.circle(cx - 3.8, cy + dy, 0.7, stroke=0, fill=1)
            canvas.line(cx - 2, cy + dy, cx + 4.5, cy + dy)
    elif kind == "chart":
        for index, height in enumerate((3, 6, 9)):
            canvas.rect(cx - 5 + index * 4, cy - 4, 2.6, height, stroke=0, fill=1)
    else:  # document
        canvas.roundRect(cx - 3.8, cy - 5, 7.6, 10, 1, stroke=1, fill=0)
        canvas.line(cx - 1.8, cy + 1.5, cx + 1.8, cy + 1.5)
        canvas.line(cx - 1.8, cy - 0.8, cx + 1.8, cy - 0.8)
    canvas.restoreState()


_META_ICONS = {
    "reporte": "document",
    "fecha": "calendar",
    "periodo": "calendar",
    "generado": "person",
    "registros": "database",
    "filtros": "list",
}


def _meta_icon(label: str) -> str:
    lowered = label.casefold()
    return next(
        (icon for word, icon in _META_ICONS.items() if lowered.startswith(word)),
        "document",
    )


def _draw_header(title: str, subtitle: str):  # type: ignore[no-untyped-def]
    def draw(canvas: pdf_canvas.Canvas, doc: BaseDocTemplate) -> None:
        width, height = doc.pagesize
        logo_h = 14 * mm
        logo_w = logo_h * theme.LOGO_SIZE[0] / theme.LOGO_SIZE[1]
        canvas.drawImage(
            str(theme.LOGO_PATH),
            MARGIN,
            height - 7 * mm - logo_h,
            width=logo_w,
            height=logo_h,
            mask="auto",
        )
        canvas.setFont("Helvetica-Bold", 17)
        canvas.setFillColor(DEEP)
        canvas.drawRightString(width - MARGIN, height - 14 * mm, title)
        canvas.setFont("Helvetica", 10)
        canvas.setFillColor(SLATE)
        canvas.drawRightString(width - MARGIN, height - 20 * mm, subtitle)
        canvas.setStrokeColor(_color(theme.ACCENT_LIGHT))
        canvas.setLineWidth(1)
        canvas.line(MARGIN, height - 26 * mm, width - MARGIN, height - 26 * mm)

    return draw


class _MetaCell(Flowable):  # type: ignore[misc]
    """One metadata entry: an icon in a pale circle, the label above and the value below."""

    def __init__(self, label: str, value: str) -> None:
        super().__init__()
        self.label, self.value = label, value
        self.height = 30

    def wrap(self, avail_width: float, avail_height: float) -> tuple[float, float]:
        self.width = avail_width
        return avail_width, self.height

    def draw(self) -> None:
        canvas = self.canv
        canvas.setFillColor(_color(theme.ACCENT_LIGHT))
        canvas.setFillAlpha(0.45)
        canvas.circle(13, 15, 12, stroke=0, fill=1)
        canvas.setFillAlpha(1)
        _icon(canvas, _meta_icon(self.label), 13, 15, DEEP)
        room = self.width - 34
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(SLATE)
        canvas.drawString(32, 19, _fit(self.label, "Helvetica", 7.5, room))
        canvas.setFont("Helvetica-Bold", 9)
        canvas.setFillColor(INK)
        canvas.drawString(32, 7, _fit(self.value, "Helvetica-Bold", 9, room))


def _meta_block(export: ReportExport, width: float) -> Table:
    items = [*export.meta_left, *export.meta_right]
    per_row = 3
    rows = [items[i : i + per_row] for i in range(0, len(items), per_row)]
    data = [
        [_MetaCell(item.label, item.value) for item in row]
        + [""] * (per_row - len(row))
        for row in rows
    ]
    table = Table(data, colWidths=[width / per_row] * per_row)
    last = len(data) - 1
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("BOX", (0, 0), (-1, -1), 0.8, _color(theme.ACCENT_LIGHT)),
                ("ROUNDEDCORNERS", [6, 6, 6, 6]),
                (
                    "LINEAFTER",
                    (0, 0),
                    (per_row - 2, -1),
                    0.6,
                    _color(theme.ACCENT_LIGHT),
                ),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, 0), 9),
                ("BOTTOMPADDING", (0, last), (-1, last), 9),
            ]
        )
    )
    return table


class _SectionTitle(Flowable):  # type: ignore[misc]
    """`≡ TITLE` with an optional rule to the right, like «RESUMEN GENERAL ————»."""

    def __init__(self, text: str, icon: str, *, rule: bool = False) -> None:
        super().__init__()
        self.text, self.icon, self.rule = text.upper(), icon, rule
        self.height = 28

    def wrap(self, avail_width: float, avail_height: float) -> tuple[float, float]:
        self.width = avail_width
        return avail_width, self.height

    def draw(self) -> None:
        canvas = self.canv
        _icon(canvas, self.icon, 9, 10, DEEP)
        canvas.setFont("Helvetica-Bold", 11.5)
        canvas.setFillColor(DEEP)
        canvas.drawString(24, 6, self.text)
        if self.rule:
            start = 24 + stringWidth(self.text, "Helvetica-Bold", 11.5) + 8
            canvas.setStrokeColor(_color(theme.ACCENT_LIGHT))
            canvas.setLineWidth(1)
            canvas.line(start, 9, self.width, 9)


def _section(text: str, icon: str = "list", *, rule: bool = False) -> list[Flowable]:
    return [Spacer(1, 8), _SectionTitle(text, icon, rule=rule)]


class _Pill(Flowable):  # type: ignore[misc]
    """A status as a rounded pill with a dot, coloured by what it says."""

    def __init__(self, text: str, size: float = FONT_SIZE) -> None:
        super().__init__()
        self.text, self.size = text, size
        self.tone = status_tone(text)

    def wrap(self, avail_width: float, avail_height: float) -> tuple[float, float]:
        label = _fit(self.text, "Helvetica-Bold", self.size, max(avail_width - 20, 10))
        self.label = label
        self.width = min(
            stringWidth(label, "Helvetica-Bold", self.size) + 20, avail_width
        )
        self.height = self.size + 7
        return self.width, self.height

    def draw(self) -> None:
        background, text, accent = _tone(self.tone)
        canvas = self.canv
        canvas.setFillColor(background)
        canvas.roundRect(
            0, 0, self.width, self.height, self.height / 2, stroke=0, fill=1
        )
        canvas.setFillColor(accent)
        canvas.circle(7, self.height / 2, 2, stroke=0, fill=1)
        canvas.setFillColor(text)
        canvas.setFont("Helvetica-Bold", self.size)
        canvas.drawString(13, (self.height - self.size) / 2 + 1.4, self.label)


def _text_width(text: str, font: str = "Helvetica") -> float:
    return float(stringWidth(text, font, FONT_SIZE))


def column_widths(
    columns: list[ExportColumn], rows: list[dict[str, Any]], width: float
) -> list[float]:
    """Width of each column from what it holds: the table fills the page, numbers and
    dates take what they need and long text takes the rest and wraps."""
    preferred: list[float] = []
    minimum: list[float] = []
    for column in columns:
        words = column.header.split()
        longest_word = max((_text_width(w, "Helvetica-Bold") for w in words), default=0)
        header = _text_width(column.header, "Helvetica-Bold")
        body = max(
            (
                _text_width(format_value(row.get(column.key), column.kind))
                for row in rows[:400]
            ),
            default=0,
        )
        if column.pill:
            body += 20  # the pill's dot and rounded ends
        if column.total:
            body = max(body, _text_width(total_text(column, rows), "Helvetica-Bold"))
        is_text = column.kind == "text"
        body = min(body, MAX_TEXT_COLUMN) if is_text else body
        # A header may wrap onto two lines, so it asks for less than its full width.
        asked = max(longest_word, min(header, 28 * mm), body)
        preferred.append(asked + CELL_PAD)
        minimum.append(
            max(longest_word, min(body, MIN_TEXT_COLUMN) if is_text else body)
            + CELL_PAD
        )
    total = sum(preferred)
    if total <= width:
        extra = width - total
        return [p + extra * p / total for p in preferred]
    # Too wide: only text columns shrink (they wrap), down to their minimum.
    widths = list(preferred)
    for _ in range(4):
        excess = sum(widths) - width
        if excess <= 0.01:
            break
        room = [
            (w - m) if columns[i].kind == "text" else 0.0
            for i, (w, m) in enumerate(zip(widths, minimum, strict=True))
        ]
        total_room = sum(room)
        if total_room <= 0:
            break
        take = min(excess, total_room)
        widths = [w - take * r / total_room for w, r in zip(widths, room, strict=True)]
    scale = width / sum(widths)
    return [w * scale for w in widths]


def _data_table(
    columns: list[ExportColumn], rows: list[dict[str, Any]], widths: list[float]
) -> Table:
    header = [Paragraph(escape(c.header), HEAD[c.alignment]) for c in columns]

    def cell(column: ExportColumn, row: dict[str, Any]) -> Flowable:
        text = format_value(row.get(column.key), column.kind)
        if column.pill and text != EMPTY:
            return _Pill(text)
        return Paragraph(escape(text), CELL[column.alignment])

    body = [[cell(c, row) for c in columns] for row in rows]
    data = [header, *body]
    last = len(data) - 1
    has_totals = any(c.total for c in columns)
    if has_totals:
        totals = []
        for index, column in enumerate(columns):
            text = total_text(column, rows) if column.total else ""
            if index == 0:
                text = f"Total: {text}" if text else "Total"
            totals.append(Paragraph(f"<b>{escape(text)}</b>", CELL[column.alignment]))
        data.append(totals)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), DEEP),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), CELL_PAD / 2),
        ("RIGHTPADDING", (0, 0), (-1, -1), CELL_PAD / 2),
        ("TOPPADDING", (0, 0), (-1, 0), 6),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
        ("ROUNDEDCORNERS", [4, 4, 4, 4]),
    ]
    if last >= 1:
        style.append(("ROWBACKGROUNDS", (0, 1), (-1, last), [colors.white, ZEBRA]))
    if has_totals:
        style += [
            ("BACKGROUND", (0, last + 1), (-1, last + 1), _color(theme.ACCENT_LIGHT)),
            ("LINEABOVE", (0, last + 1), (-1, last + 1), 1, DEEP),
        ]
    table = Table(data, colWidths=widths, repeatRows=1)
    table.setStyle(TableStyle(style))
    return table


RED = colors.HexColor("#C0392B")


class _DotLeader(Flowable):  # type: ignore[misc]
    """`Label ............ value` on one line with dotted guides, and an optional small note
    under it. A line that is bad news (overdue, negative) is written in red; the closing
    total is bold and in capitals."""

    def __init__(self, line: SummaryLine, *, total: bool = False) -> None:
        super().__init__()
        self.line, self.total = line, total
        self.height = 24 if line.note else 16

    def wrap(self, avail_width: float, avail_height: float) -> tuple[float, float]:
        self.width = avail_width
        return avail_width, self.height

    def draw(self) -> None:
        canvas = self.canv
        bad = self.line.tone == "bad"
        label = f"{self.line.label.upper()}:" if self.total else self.line.label
        font = "Helvetica-Bold" if self.total else "Helvetica"
        top = self.height - 11
        ink = RED if bad else INK
        canvas.setFont(font, 9.5)
        canvas.setFillColor(ink)
        canvas.drawString(0, top, label)
        canvas.setFont("Helvetica-Bold" if self.total else "Helvetica", 9.5)
        canvas.drawRightString(self.width, top, self.line.text)
        start = stringWidth(label, font, 9.5) + 6
        end = self.width - stringWidth(self.line.text, canvas._fontname, 9.5) - 6
        canvas.setStrokeColor(RED if bad else _color(theme.ACCENT_SKY))
        canvas.setLineWidth(0.7)
        canvas.setDash(0.7, 2.6)
        canvas.line(start, top + 2.5, end, top + 2.5)
        canvas.setDash()
        if self.line.note:
            canvas.setFont("Helvetica", 7)
            canvas.setFillColor(SLATE)
            canvas.drawString(0, top - 9, self.line.note)


def _summary(export: ReportExport, width: float) -> list[Flowable]:
    """«Resumen general»: the headline lines one under the other, label ........ value, ending
    with the total in bold capitals."""
    lines = [line for group in export.summary if group.kpi for line in group.lines]
    if not lines:
        return []
    ordered = [*lines[1:], lines[0]]  # the first line is the total: it closes the block
    flow: list[Flowable] = [
        _DotLeader(line, total=index == len(ordered) - 1)
        for index, line in enumerate(ordered)
    ]
    return [*_section("Resumen general", "chart", rule=True), Spacer(1, 4), *flow]


def render_pdf(
    export: ReportExport,
    *,
    include_summary: bool = True,
    generated_at: datetime | None = None,
) -> bytes:
    generated_at = generated_at or datetime.now(UTC)
    page = landscape(A4) if len(export.columns) > LANDSCAPE_FROM else A4
    width = page[0] - 2 * MARGIN
    buffer = io.BytesIO()
    doc = BaseDocTemplate(
        buffer,
        pagesize=page,
        leftMargin=MARGIN,
        rightMargin=MARGIN,
        topMargin=HEADER_HEIGHT,
        bottomMargin=FOOTER_HEIGHT,
        title=export.title.title(),
        author=theme.SYSTEM_NAME,
        subject=export.section,
    )
    frame = Frame(
        MARGIN,
        FOOTER_HEIGHT,
        width,
        page[1] - HEADER_HEIGHT - FOOTER_HEIGHT,
        leftPadding=0,
        rightPadding=0,
        topPadding=0,
        bottomPadding=0,
        id="body",
    )
    doc.addPageTemplates(
        [
            PageTemplate(
                id="page",
                frames=[frame],
                onPage=_draw_header(export.title, export.subtitle),
            )
        ]
    )
    columns, rows = list(export.columns), list(export.rows)
    widths = column_widths(columns, rows, width) if columns else [width]
    story: list[Flowable] = [
        Spacer(1, 4),
        _meta_block(export, width),
        *_section(export.section),
    ]
    if rows and columns:
        story.append(_data_table(columns, rows, widths))
    else:
        story.append(Paragraph(f"Sin registros {EMPTY}", _BASE))
    if include_summary:
        story += _summary(export, width)

    doc.build(story, canvasmaker=_NumberedCanvas)
    return buffer.getvalue()
