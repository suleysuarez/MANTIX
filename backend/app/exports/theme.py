"""Identity shared by the PDF and Excel exports: one palette, one logo, one clock."""

from datetime import timedelta, timezone
from pathlib import Path

#: Mantix palette as `RRGGBB` (no `#`): the same tokens as the web app.
ACCENT_LIGHT = "ADD7F6"
ACCENT_SKY = "A2D2FF"
DEEP = "3E5C76"
SLATE = "778DA9"
GREY = "CED4DA"
MUSTARD = "E4B363"  # the logo's X
INK = "1D2B3A"
ZEBRA = "F1F6FB"
WHITE = "FFFFFF"

#: Series colors for charts, in order of use.
CHART_COLORS = (DEEP, ACCENT_SKY, MUSTARD, SLATE, ACCENT_LIGHT, GREY)

LOGO_PATH = Path(__file__).resolve().parent.parent / "assets" / "mantix-logo.png"
#: Pixel size of `mantix-logo.png` (width, height).
LOGO_SIZE = (720, 142)

SYSTEM_NAME = "Mantix · Gestión de mantenimiento"

#: Dates are shown in Colombia time (UTC-5, no daylight saving).
DISPLAY_TZ = timezone(timedelta(hours=-5))
DATE_FORMAT = "%d/%m/%Y"
DATETIME_FORMAT = "%d/%m/%Y %H:%M"

#: Excel number formats.
XLSX_DATE = "dd/mm/yyyy"
XLSX_DATETIME = "dd/mm/yyyy hh:mm"
XLSX_MONEY = '"$"#,##0.00'
XLSX_NUMBER = "#,##0.0"
XLSX_INTEGER = "#,##0"
