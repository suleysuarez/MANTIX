"""PDF renderer (ReportLab): header on every page, metadata, zebra table, executive
summary with dotted leaders, charts, and a "Página X de Y" footer."""

import io
from datetime import UTC, datetime
from typing import Any
from xml.sax.saxutils import escape

from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.graphics.charts.legends import Legend
from reportlab.graphics.charts.piecharts import Pie
from reportlab.graphics.shapes import Drawing, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
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
from app.exports.formatting import EMPTY, format_value, local, total_of
from app.exports.model import ExportColumn, ReportExport, SummaryGroup

MARGIN = 14 * mm
HEADER_HEIGHT = 26 * mm
FOOTER_HEIGHT = 14 * mm
#: A table wider than this many columns is printed on a landscape page.
LANDSCAPE_FROM = 7
MAX_LEADER = 125 * mm


def _color(hex_value: str) -> colors.Color:
    return colors.HexColor(f"#{hex_value}")


DEEP, SLATE, GREY, ZEBRA = (
    _color(theme.DEEP),
    _color(theme.SLATE),
    _color(theme.GREY),
    _color(theme.ZEBRA),
)
INK = _color(theme.INK)

_BASE = ParagraphStyle(
    "base", fontName="Helvetica", fontSize=8, leading=10, textColor=INK
)
CELL = ParagraphStyle("cell", parent=_BASE, fontSize=7.5, leading=9)
CELL_RIGHT = ParagraphStyle("cellr", parent=CELL, alignment=TA_RIGHT)
HEAD = ParagraphStyle(
    "head",
    parent=CELL,
    fontName="Helvetica-Bold",
    textColor=colors.white,
)
HEAD_RIGHT = ParagraphStyle("headr", parent=HEAD, alignment=TA_RIGHT)
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
        # Guides read better on a measure about half the page, like a printed ledger.
        self.width = min(avail_width, MAX_LEADER)
        return self.width, self.height

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


def _data_table(
    columns: list[ExportColumn], rows: list[dict[str, Any]], width: float
) -> Table:
    weights = [column.width for column in columns]
    col_widths = [width * w / sum(weights) for w in weights]
    header = [
        Paragraph(escape(c.header), HEAD_RIGHT if c.numeric else HEAD) for c in columns
    ]
    body = [
        [
            Paragraph(
                escape(format_value(row.get(c.key), c.kind)),
                CELL_RIGHT if c.numeric else CELL,
            )
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
            if column.total:
                text = format_value(total_of(column, rows), column.kind)
                if index == 0:
                    text = f"Total: {text}"
            else:
                text = "Total" if index == 0 else ""
            style = CELL_RIGHT if column.numeric else CELL
            totals.append(Paragraph(f"<b>{escape(text)}</b>", style))
        data.append(totals)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), DEEP),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("LINEBELOW", (0, 1), (-1, last), 0.3, GREY),
    ]
    if last >= 1:
        style.append(("ROWBACKGROUNDS", (0, 1), (-1, last), [colors.white, ZEBRA]))
    if has_totals:
        style += [
            ("BACKGROUND", (0, last + 1), (-1, last + 1), _color(theme.ACCENT_LIGHT)),
            ("LINEABOVE", (0, last + 1), (-1, last + 1), 1, DEEP),
        ]
    table = Table(data, colWidths=col_widths, repeatRows=1)
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


def _summary(
    export: ReportExport, width: float, *, include_charts: bool
) -> list[Flowable]:
    if not export.summary:
        return []
    flow: list[Flowable] = _section("Resumen ejecutivo")
    charts: list[Drawing] = []
    for group in export.summary:
        lines: list[Flowable] = [Paragraph(escape(group.title), SUBSECTION)]
        lines += [DotLeader(line.label, line.text) for line in group.lines]
        flow.append(KeepTogether(lines))
        if include_charts:
            chart = _chart(group, width / 2 - 6)
            if chart is not None:
                charts.append(chart)
    for start in range(0, len(charts), 2):
        pair = charts[start : start + 2]
        row = pair + [""] * (2 - len(pair))
        table = Table([row], colWidths=[width / 2, width / 2])
        table.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
        flow += [Spacer(1, 8), KeepTogether([table])]
    return flow


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
    story: list[Flowable] = [_meta_block(export, width), *_section(export.section)]
    if export.rows and export.columns:
        story.append(_data_table(list(export.columns), list(export.rows), width))
    else:
        story.append(Paragraph(f"Sin registros {EMPTY}", _BASE))
    if include_summary:
        story += _summary(export, width, include_charts=include_charts)

    footer = local(generated_at).strftime("%d/%m/%Y")

    class Canvas(_NumberedCanvas):
        footer_date = footer

    doc.build(story, canvasmaker=Canvas)
    return buffer.getvalue()
