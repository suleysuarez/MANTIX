"""Excel renderer (openpyxl), the Mantix layout shared by every report: a banner with the logo
and the title, a metadata band, «Resumen» with summary cards and native charts (a doughnut and
bars), and «Detalle» with a dark-header table, coloured status pills, a totals row of formulas
and a footer band, plus any extra sheet.

Numbers, dates and money are written as real values with number formats, never as text.
"""

import io
from datetime import UTC, datetime
from typing import Any

from openpyxl import Workbook
from openpyxl.chart import BarChart, DoughnutChart, Reference
from openpyxl.chart.label import DataLabelList
from openpyxl.chart.series import DataPoint
from openpyxl.drawing.image import Image
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.worksheet import Worksheet

from app.exports import theme
from app.exports.formatting import local, status_tone
from app.exports.model import ExportColumn, ReportExport, Tone
from app.services.exporters import neutralise_formula

FONT = "Calibri"
_NUMBER_FORMATS = {
    "date": theme.XLSX_DATE,
    "datetime": theme.XLSX_DATETIME,
    "money": theme.XLSX_MONEY,
    "number": theme.XLSX_NUMBER,
    "int": theme.XLSX_INTEGER,
}
_THIN = Side(style="thin", color=theme.GREY)
_HEADER_FILL = PatternFill("solid", fgColor=theme.ACCENT_LIGHT)
_ZEBRA_FILL = PatternFill("solid", fgColor=theme.ZEBRA)
_TOTAL_FILL = PatternFill("solid", fgColor=theme.ACCENT_LIGHT)
#: Rows above the table: logo and title (1-3), metadata (4-6), a blank row (7).
HEADER_ROW = 8
LOGO_HEIGHT_PX = 44


def _cell_value(value: Any, column: ExportColumn) -> Any:
    """A value Excel can store: text is neutralised against formulas, dates are naive local time."""
    if value is None or value == "":
        return None
    if column.kind == "bool":
        return "Sí" if value else "No"
    if column.kind in ("date", "datetime") and isinstance(value, datetime):
        return local(value).replace(tzinfo=None)
    if column.kind == "money":
        return float(value)
    if isinstance(value, str):
        return neutralise_formula(value)
    return value


def _logo(sheet: Worksheet) -> None:
    image = Image(str(theme.LOGO_PATH))
    ratio = theme.LOGO_SIZE[0] / theme.LOGO_SIZE[1]
    image.height = LOGO_HEIGHT_PX
    image.width = int(LOGO_HEIGHT_PX * ratio)
    sheet.add_image(image, "A1")
    for row in (1, 2):
        sheet.row_dimensions[row].height = 20


BAND = "E6F1FB"  # pale blue behind the logo and the metadata
CARD_BORDER = "C9DCEE"


def _tone_fills(tone: Tone) -> tuple[PatternFill, str, str]:
    background, text, accent = theme.TONES[tone]
    return PatternFill("solid", fgColor=background), text, accent


def _title_block(
    sheet: Worksheet,
    export: ReportExport,
    title: str,
    span: int,
    right_column: int | None = None,
) -> None:
    """Clean header used by every sheet: the logo on top-left, the title large beside it, a thin
    rule and the metadata (label in the palette's blue, value in ink) in two blocks."""
    _logo(sheet)
    last = max(span, 4)
    sheet.merge_cells(start_row=1, start_column=3, end_row=2, end_column=last)
    cell = sheet.cell(row=1, column=3, value=title)
    cell.font = Font(name=FONT, size=20, bold=True, color=theme.DEEP)
    cell.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    for column in range(1, last + 1):
        sheet.cell(row=3, column=column).border = Border(
            bottom=Side(style="medium", color=theme.ACCENT_SKY)
        )
    rows = max(len(export.meta_left), len(export.meta_right))
    right = right_column or max(last // 2, 2) + 1
    for index in range(rows):
        for items, column in ((export.meta_left, 1), (export.meta_right, right)):
            if index < len(items):
                label = sheet.cell(
                    row=4 + index, column=column, value=items[index].label
                )
                label.font = Font(name=FONT, size=10, bold=True, color=theme.DEEP)
                value = sheet.cell(
                    row=4 + index,
                    column=column + 1,
                    value=neutralise_formula(items[index].value),
                )
                value.font = Font(name=FONT, size=10, color=theme.INK)


def _footer(sheet: Worksheet, row: int, span: int) -> None:
    """A pale band closing the sheet, with the system name."""
    last = max(span, 4)
    for column in range(1, last + 1):
        sheet.cell(row=row, column=column).fill = PatternFill("solid", fgColor=BAND)
    sheet.row_dimensions[row].height = 26
    cell = sheet.cell(row=row, column=1, value=theme.FOOTER_TEXT)
    cell.font = Font(name=FONT, size=10, bold=True, color=theme.DEEP)
    cell.alignment = Alignment(vertical="center")


def _write_table(
    sheet: Worksheet,
    columns: list[ExportColumn],
    rows: list[dict[str, Any]],
    *,
    header_row: int,
    totals_label: str = "Total",
) -> int:
    """Header, rows with real formats, autofilter, freeze panes and a totals row of formulas."""
    for index, column in enumerate(columns, start=1):
        cell = sheet.cell(row=header_row, column=index, value=column.header)
        cell.font = Font(name=FONT, size=11, bold=True, color=theme.DEEP)
        cell.fill = _HEADER_FILL
        cell.alignment = Alignment(
            horizontal="center", vertical="center", wrap_text=True
        )
        sheet.column_dimensions[get_column_letter(index)].width = column.width
    sheet.row_dimensions[header_row].height = 28

    first = header_row + 1
    for offset, row in enumerate(rows):
        r = first + offset
        for index, column in enumerate(columns, start=1):
            cell = sheet.cell(
                row=r, column=index, value=_cell_value(row.get(column.key), column)
            )
            cell.font = Font(name=FONT, size=10, color=theme.INK)
            cell.alignment = Alignment(
                horizontal=column.alignment,
                vertical="center",
                wrap_text=column.kind == "text",
            )
            if column.kind in _NUMBER_FORMATS:
                cell.number_format = _NUMBER_FORMATS[column.kind]
            cell.border = Border(bottom=_THIN)
            if offset % 2 == 1:
                cell.fill = _ZEBRA_FILL
            if column.pill and cell.value:
                fill, text_color, _accent = _tone_fills(status_tone(str(cell.value)))
                cell.fill = fill
                cell.font = Font(name=FONT, size=10, bold=True, color=text_color)
                cell.alignment = Alignment(horizontal="center", vertical="center")
    last = first + len(rows) - 1
    if rows:
        sheet.auto_filter.ref = f"A{header_row}:{get_column_letter(len(columns))}{last}"
    sheet.freeze_panes = f"A{first}"

    if rows and any(column.total for column in columns):
        total_row = last + 1
        for index, column in enumerate(columns, start=1):
            letter = get_column_letter(index)
            cell = sheet.cell(row=total_row, column=index)
            if column.total == "sum":
                cell.value = f"=SUBTOTAL(109,{letter}{first}:{letter}{last})"
            elif column.total == "avg":
                cell.value = (
                    f'=IFERROR(SUBTOTAL(101,{letter}{first}:{letter}{last}),"")'
                )
            elif column.total == "share_true":
                rng = f"{letter}{first}:{letter}{last}"
                cell.value = f'=IFERROR(COUNTIF({rng},"Sí")/(COUNTIF({rng},"Sí")+COUNTIF({rng},"No")),"")'
            elif column.total == "count":
                formula = f"SUBTOTAL(103,{letter}{first}:{letter}{last})"
                cell.value = (
                    f'="{totals_label}: "&{formula}' if index == 1 else f"={formula}"
                )
            elif index == 1:
                cell.value = totals_label
            cell.font = Font(name=FONT, size=10, bold=True, color=theme.DEEP)
            cell.fill = _TOTAL_FILL
            cell.border = Border(top=Side(style="medium", color=theme.DEEP))
            cell.alignment = Alignment(horizontal=column.alignment)
            if column.total == "share_true":
                cell.number_format = "0.0%"
            if column.kind in _NUMBER_FORMATS and column.total in ("sum", "avg"):
                cell.number_format = _NUMBER_FORMATS[column.kind]
            elif column.total == "count":
                cell.number_format = theme.XLSX_INTEGER
    return last


#: Summary grid: two blocks per row, each one A-B-C or D-E-F wide. A chart is as wide as its
#: block (never wider, so neighbours cannot overlap) and takes a fixed number of rows.
BLOCK_COLUMNS = {0: 1, 1: 4}  # first column of the left and right block
COLUMN_WIDTHS = (32, 14, 3, 32, 14, 3)
CHART_WIDTH_CM = 9.2
CHART_HEIGHT_CM = 7.0
CHART_ROWS = 15  # 7 cm at the default row height, plus breathing room


def _style_chart(chart: BarChart | DoughnutChart, title: str) -> None:
    chart.title = title
    chart.width, chart.height = CHART_WIDTH_CM, CHART_HEIGHT_CM
    if isinstance(chart, BarChart):
        chart.legend = None


def _write_group(sheet: Worksheet, group: Any, row: int, column: int) -> int:
    """A titled two-column table at (row, column); returns its last row."""
    head = sheet.cell(row=row, column=column, value=group.title)
    head.font = Font(name=FONT, size=11, bold=True, color=theme.DEEP)
    head.fill = _HEADER_FILL
    sheet.cell(row=row, column=column + 1).fill = _HEADER_FILL
    sheet.row_dimensions[row].height = 22
    for index, line in enumerate(group.lines, start=1):
        label = sheet.cell(
            row=row + index, column=column, value=neutralise_formula(line.label)
        )
        label.font = Font(name=FONT, size=10, color=theme.INK)
        value = sheet.cell(row=row + index, column=column + 1, value=line.value)
        value.font = Font(name=FONT, size=10, bold=True, color=theme.DEEP)
        value.alignment = Alignment(horizontal="right")
        if isinstance(line.value, float):
            value.number_format = theme.XLSX_NUMBER
        label.border = value.border = Border(bottom=_THIN)
    return row + len(group.lines)


def _summary_sheet(book: Workbook, export: ReportExport, include_charts: bool) -> None:
    """KPIs on top, then the breakdown tables, then the charts in a tidy two-per-row grid."""
    sheet = book.active
    sheet.title = "Resumen"
    sheet.sheet_view.showGridLines = False
    for letter, width in zip("ABCDEF", COLUMN_WIDTHS, strict=True):
        sheet.column_dimensions[letter].width = width
    _title_block(sheet, export, export.title, 5, right_column=4)

    row = HEADER_ROW
    kpis = [group for group in export.summary if group.kpi]
    others = [group for group in export.summary if not group.kpi]
    for group in kpis:
        # Summary cards: two columns of cards (one per block), each one a tinted box with the
        # label, a big figure and a caption.
        head = sheet.cell(row=row, column=1, value=group.title)
        head.font = Font(name=FONT, size=11, bold=True, color=theme.DEEP)
        row += 1
        stack = [0, 0]
        for index, line in enumerate(group.lines):
            side = index % 2
            column = BLOCK_COLUMNS[side]
            top = row + stack[side] * 4
            fill, text_color, accent = _tone_fills(line.tone)
            side_line = Side(style="thin", color=accent)
            for offset in range(3):
                sheet.merge_cells(
                    start_row=top + offset,
                    start_column=column,
                    end_row=top + offset,
                    end_column=column + 1,
                )
                for col in (column, column + 1):
                    cell = sheet.cell(row=top + offset, column=col)
                    cell.fill = fill
                    cell.border = Border(
                        left=side_line if col == column else None,
                        right=side_line if col == column + 1 else None,
                        top=side_line if offset == 0 else None,
                        bottom=side_line if offset == 2 else None,
                    )
            label = sheet.cell(
                row=top, column=column, value=neutralise_formula(line.label)
            )
            label.font = Font(name=FONT, size=10, bold=True, color=text_color)
            label.alignment = Alignment(horizontal="left", indent=1, vertical="center")
            value = sheet.cell(row=top + 1, column=column, value=line.value)
            value.font = Font(name=FONT, size=22, bold=True, color=theme.DEEP)
            value.alignment = Alignment(horizontal="left", indent=1, vertical="center")
            if isinstance(line.value, float):
                value.number_format = theme.XLSX_NUMBER
            if line.note:
                note = sheet.cell(row=top + 2, column=column, value=line.note)
                note.font = Font(name=FONT, size=9, color=theme.SLATE)
                note.alignment = Alignment(
                    horizontal="left", indent=1, vertical="center"
                )
            sheet.row_dimensions[top + 1].height = 32
            stack[side] += 1
        row += max(stack) * 4 + 1

    placed: list[tuple[Any, int, int, int]] = []  # group, header row, last row, column
    for pair_start in range(0, len(others), 2):
        pair = others[pair_start : pair_start + 2]
        for offset, group in enumerate(pair):
            column = BLOCK_COLUMNS[offset]
            last = _write_group(sheet, group, row, column)
            placed.append((group, row, last, column))
        row += max(len(group.lines) for group in pair) + 3

    if include_charts:
        slot = 0
        for group, first, last, column in placed:
            if group.chart is None or last <= first:
                continue
            labels = Reference(sheet, min_col=column, min_row=first + 1, max_row=last)
            values = Reference(sheet, min_col=column + 1, min_row=first, max_row=last)
            chart: BarChart | DoughnutChart
            if group.chart == "bar":
                chart = BarChart()
                chart.type = "col"
                chart.add_data(values, titles_from_data=False)
                chart.set_categories(labels)
                chart.series[0].graphicalProperties.solidFill = theme.ACCENT_SKY
                chart.dataLabels = DataLabelList()
                chart.dataLabels.showVal = True
                chart.y_axis.majorGridlines = None
            else:
                chart = DoughnutChart()
                chart.holeSize = 55
                chart.add_data(values, titles_from_data=False)
                chart.set_categories(labels)
                for index in range(last - first):
                    point = DataPoint(idx=index)
                    point.graphicalProperties.solidFill = theme.CHART_COLORS[
                        index % len(theme.CHART_COLORS)
                    ]
                    chart.series[0].dPt.append(point)
                chart.dataLabels = DataLabelList()
                chart.dataLabels.showPercent = True
            _style_chart(chart, group.title)
            anchor = f"{'A' if slot % 2 == 0 else 'D'}{row + (slot // 2) * CHART_ROWS}"
            sheet.add_chart(chart, anchor)
            slot += 1


def _detail_sheet(book: Workbook, export: ReportExport) -> None:
    sheet = book.create_sheet(export.sheet_name)
    sheet.sheet_view.showGridLines = False
    columns = list(export.columns)
    _title_block(sheet, export, export.title, len(columns))
    last = _write_table(sheet, columns, list(export.rows), header_row=HEADER_ROW)
    has_totals = bool(export.rows) and any(column.total for column in columns)
    _footer(sheet, max(last, HEADER_ROW) + (3 if has_totals else 2), len(columns))
    sheet.page_setup.orientation = "landscape"
    sheet.page_setup.fitToWidth = 1
    sheet.page_setup.fitToHeight = 0
    sheet.sheet_properties.pageSetUpPr.fitToPage = True
    sheet.print_title_rows = f"{HEADER_ROW}:{HEADER_ROW}"


def _extra_sheet(book: Workbook, export: ReportExport, extra: Any) -> None:
    sheet = book.create_sheet(extra.name)
    sheet.sheet_view.showGridLines = False
    columns = list(extra.columns)
    _title_block(sheet, export, extra.title, len(columns))
    _write_table(sheet, columns, list(extra.rows), header_row=HEADER_ROW)


def render_xlsx(
    export: ReportExport,
    *,
    include_summary: bool = True,
    include_charts: bool = True,
    generated_at: datetime | None = None,
) -> bytes:
    book = Workbook()
    if include_summary and export.summary:
        _summary_sheet(book, export, include_charts)
        _detail_sheet(book, export)
    else:
        sheet = book.active
        book.remove(sheet)
        _detail_sheet(book, export)
    for extra in export.extra_sheets:
        _extra_sheet(book, export, extra)
    book.properties.title = export.title.title()
    book.properties.creator = theme.SYSTEM_NAME
    book.properties.created = (generated_at or datetime.now(UTC)).replace(tzinfo=None)
    buffer = io.BytesIO()
    book.save(buffer)
    return buffer.getvalue()
