"""PDF renderer (ReportLab): header on every page, metadata, zebra table sized to its
content, executive summary aligned with the table, charts, and a "Página X de Y" footer."""

import io
from datetime import UTC, datetime
from typing import Any
from xml.sax.saxutils import escape

from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.graphics.charts.legends import Legend
from reportlab.graphics.charts.piecharts import Pie
from reportlab.graphics.shapes import Drawing, String
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
    HRFlowable,
    KeepTogether,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from app.exports import theme
from app.exports.formatting import EMPTY, format_value, local, total_text
from app.exports.model import ExportColumn, ReportExport, SummaryGroup

MARGIN = 10 * mm
HEADER_HEIGHT = 26 * mm
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


class DotLeader(Flowable):  # type: ignore[misc]
    """`Label ............ value` on one line, with dotted guides in between."""

    def __init__(self, label: str, value: str, *, bold: bool = False) -> None:
        super().__init__()
        self.label, self.value, self.bold = label, value, bold
        self.height = 13

    def wrap(self, avail_width: float, avail_height: float) -> tuple[float, float]:
        self.width = avail_width
        return avail_width, self.height

    def draw(self) -> None:
        font = "Helvetica-Bold" if self.bold else "Helvetica"
        canvas = self.canv
        canvas.setFont(font, 8.5)
        canvas.setFillColor(INK)
        label_end = stringWidth(self.label, font, 8.5)
        value_start = self.width - stringWidth(self.value, "Helvetica-Bold", 8.5)
        canvas.drawString(0, 3, self.label)
        canvas.setFont("Helvetica-Bold", 8.5)
        canvas.drawRightString(self.width, 3, self.value)
        canvas.setStrokeColor(SLATE)
        canvas.setLineWidth(0.6)
        canvas.setDash(0.6, 2.4)
        canvas.line(label_end + 4, 4, value_start - 4, 4)
        canvas.setDash()


class _NumberedCanvas(pdf_canvas.Canvas):  # type: ignore[misc]
    """Keeps every page until the end so the footer can say "Página X de Y"."""

    footer_date = ""

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
        self.drawString(
            MARGIN, FOOTER_HEIGHT - 7 * mm, f"{theme.SYSTEM_NAME} · {self.footer_date}"
        )
        self.drawRightString(
            width - MARGIN,
            FOOTER_HEIGHT - 7 * mm,
            f"Página {self._pageNumber} de {total}",
        )


def _draw_header(title: str):  # type: ignore[no-untyped-def]
    def draw(canvas: pdf_canvas.Canvas, doc: BaseDocTemplate) -> None:
        width, height = doc.pagesize
        logo_h = 11 * mm
        logo_w = logo_h * theme.LOGO_SIZE[0] / theme.LOGO_SIZE[1]
        canvas.drawImage(
            str(theme.LOGO_PATH),
            MARGIN,
            height - 8 * mm - logo_h,
            width=logo_w,
            height=logo_h,
            mask="auto",
        )
        canvas.setFont("Helvetica-Bold", 14)
        canvas.setFillColor(DEEP)
        canvas.drawRightString(width - MARGIN, height - 15 * mm, title)
        canvas.setStrokeColor(_color(theme.ACCENT_SKY))
        canvas.setLineWidth(0.8)
        canvas.line(MARGIN, height - 22 * mm, width - MARGIN, height - 22 * mm)

    return draw


def _meta_block(export: ReportExport, width: float) -> Table:
    def cell(item: Any) -> Paragraph:
        return Paragraph(
            f"<b><font color='#{theme.DEEP}'>{escape(item.label)}:</font></b> "
            f"{escape(item.value)}",
            _BASE,
        )

    rows = max(len(export.meta_left), len(export.meta_right))
    data = [
        [
            cell(export.meta_left[i]) if i < len(export.meta_left) else "",
            cell(export.meta_right[i]) if i < len(export.meta_right) else "",
        ]
        for i in range(rows)
    ]
    table = Table(data, colWidths=[width / 2, width / 2])
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ("TOPPADDING", (0, 0), (-1, -1), 1),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    return table


def _section(text: str) -> list[Flowable]:
    return [
        Paragraph(escape(text.upper()), SECTION),
        HRFlowable(
            width="100%",
            thickness=1,
            color=_color(theme.ACCENT_LIGHT),
            spaceBefore=1,
            spaceAfter=6,
        ),
    ]


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
    body = [
        [
            Paragraph(escape(format_value(row.get(c.key), c.kind)), CELL[c.alignment])
            for c in columns
        ]
        for row in rows
    ]
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
        ("LINEBELOW", (0, 1), (-1, last), 0.3, GREY),
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


def _chart(group: SummaryGroup, width: float) -> Drawing | None:
    points = [(line.label, line.value) for line in group.lines if line.value]
    if not points or group.chart is None:
        return None
    height = 150
    drawing = Drawing(width, height)
    drawing.add(
        String(
            0,
            height - 10,
            group.title,
            fontName="Helvetica-Bold",
            fontSize=8.5,
            fillColor=DEEP,
        )
    )
    palette = [_color(c) for c in theme.CHART_COLORS]
    if group.chart == "bar":
        chart = VerticalBarChart()
        chart.x, chart.y = 24, 30
        chart.width, chart.height = width - 34, height - 56
        chart.data = [[float(value) for _, value in points]]
        chart.categoryAxis.categoryNames = [label for label, _ in points]
        chart.categoryAxis.labels.fontName = "Helvetica"
        chart.categoryAxis.labels.fontSize = 6.5
        chart.categoryAxis.labels.angle = 25
        chart.categoryAxis.labels.boxAnchor = "ne"
        chart.categoryAxis.labels.dy = -2
        chart.valueAxis.labels.fontName = "Helvetica"
        chart.valueAxis.labels.fontSize = 6.5
        chart.valueAxis.valueMin = 0
        chart.valueAxis.strokeColor = GREY
        chart.categoryAxis.strokeColor = GREY
        chart.bars[0].fillColor = DEEP
        chart.bars[0].strokeColor = None
        chart.barLabelFormat = "%d"
        chart.barLabels.fontName = "Helvetica"
        chart.barLabels.fontSize = 6.5
        chart.barLabels.nudge = 6
        chart.barSpacing = 2
        chart.groupSpacing = 6
        drawing.add(chart)
    else:
        pie = Pie()
        size = min(height - 40, width / 2 - 10)
        pie.x, pie.y, pie.width, pie.height = 10, 12, size, size
        pie.data = [float(value) for _, value in points]
        pie.labels = None
        pie.simpleLabels = 1
        pie.slices.strokeColor = colors.white
        pie.slices.strokeWidth = 0.8
        for index in range(len(points)):
            pie.slices[index].fillColor = palette[index % len(palette)]
        drawing.add(pie)
        legend = Legend()
        legend.x, legend.y = size + 24, height - 30
        legend.fontName, legend.fontSize = "Helvetica", 7
        legend.alignment = "right"
        legend.columnMaximum = 8
        legend.dxTextSpace = 4
        legend.colorNamePairs = [
            (palette[i % len(palette)], f"{label} ({int(value)})")
            for i, (label, value) in enumerate(points)
        ]
        drawing.add(legend)
    return drawing


def _split(widths: list[float]) -> int:
    """Column boundary closest to the middle of the table: the summary uses it as its own
    split, so its two halves start and end where table columns do."""
    total, running = sum(widths), 0.0
    best, gap = 1, total
    for index, width in enumerate(widths[:-1], start=1):
        running += width
        if abs(running - total / 2) < gap:
            best, gap = index, abs(running - total / 2)
    return best


def _summary(
    export: ReportExport, widths: list[float], *, include_charts: bool
) -> list[Flowable]:
    if not export.summary:
        return []
    split = _split(widths)
    left_w = sum(widths[:split])
    right_w = sum(widths[split:])
    sides = (left_w - 14, right_w - 14)
    # KPIs first, then each group goes to the shorter side so both halves stay balanced.
    ordered = sorted(export.summary, key=lambda group: not group.kpi)
    columns: list[list[SummaryGroup]] = [[], []]
    heights = [0, 0]
    for group in ordered:
        side = 0 if heights[0] <= heights[1] else 1
        columns[side].append(group)
        heights[side] += len(group.lines) + 2

    def cell(groups: list[SummaryGroup]) -> list[Flowable]:
        flow: list[Flowable] = []
        for group in groups:
            flow.append(Paragraph(escape(group.title), SUBSECTION))
            flow += [
                DotLeader(line.label, line.text, bold=group.kpi) for line in group.lines
            ]
        return flow

    story: list[Flowable] = _section("Resumen ejecutivo")
    layout = Table([[cell(columns[0]), cell(columns[1])]], colWidths=[left_w, right_w])
    layout.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
            ]
        )
    )
    story.append(KeepTogether([layout]))
    if include_charts:
        charts = [
            chart
            for group in export.summary
            if (chart := _chart(group, min(sides) - 4)) is not None
        ]
        for start in range(0, len(charts), 2):
            pair = charts[start : start + 2]
            row = pair + [""] * (2 - len(pair))
            table = Table([row], colWidths=[left_w, right_w])
            table.setStyle(
                TableStyle(
                    [
                        ("VALIGN", (0, 0), (-1, -1), "TOP"),
                        ("LEFTPADDING", (0, 0), (-1, -1), 4),
                    ]
                )
            )
            story += [Spacer(1, 8), KeepTogether([table])]
    return story


def render_pdf(
    export: ReportExport,
    *,
    include_summary: bool = True,
    include_charts: bool = True,
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
        [PageTemplate(id="page", frames=[frame], onPage=_draw_header(export.title))]
    )
    columns, rows = list(export.columns), list(export.rows)
    widths = column_widths(columns, rows, width) if columns else [width]
    story: list[Flowable] = [_meta_block(export, width), *_section(export.section)]
    if rows and columns:
        story.append(_data_table(columns, rows, widths))
    else:
        story.append(Paragraph(f"Sin registros {EMPTY}", _BASE))
    if include_summary:
        story += _summary(export, widths, include_charts=include_charts)

    footer = local(generated_at).strftime("%d/%m/%Y")

    class Canvas(_NumberedCanvas):
        footer_date = footer

    doc.build(story, canvasmaker=Canvas)
    return buffer.getvalue()
