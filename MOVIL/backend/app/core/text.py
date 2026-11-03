"""Text normalisation shared by every place that stores catalogue-like values.

One criterion everywhere (API, import, migration script): trim, collapse runs of
whitespace, then a case rule per kind of value. Uniqueness is compared on the
`fold` of a value, so «Bodega A», «bodega  a» and «BODEGA A» are the same one.
"""

import re
import unicodedata

#: Connectors kept in lower case inside a title («Cable de red», not «Cable De Red»). A lone
#: «A» stays capital: in «Bodega A» it is a name, not a preposition.
_SMALL_WORDS = frozenset(
    {
        "al",
        "con",
        "de",
        "del",
        "e",
        "el",
        "en",
        "la",
        "las",
        "lo",
        "los",
        "o",
        "para",
        "por",
        "sin",
        "u",
        "un",
        "una",
        "y",
    }
)
#: An all-capitals word up to this long is an acronym and is kept as typed (SSD, USB, HDMI, GB).
_ACRONYM_MAX = 4


def collapse(value: str) -> str:
    """Trim and collapse any run of whitespace into one space."""
    return re.sub(r"\s+", " ", value).strip()


def fold(value: str) -> str:
    """Comparison key: no accents, no case, no extra spaces."""
    decomposed = unicodedata.normalize("NFD", collapse(value))
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


def _title_word(word: str, first: bool) -> str:
    if any(ch.isdigit() for ch in word):
        return word  # models and sizes: «512», «X1», «DDR4»
    letters = re.sub(r"[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]", "", word)
    if letters.isupper() and len(letters) <= _ACRONYM_MAX and len(letters) > 1:
        return word  # SSD, USB, HDMI
    if not first and word.lower() in _SMALL_WORDS:
        return word.lower()
    # Capitalise after a hyphen or slash too: «usb-c» -> «Usb-C» would be wrong for
    # acronyms, so each part follows the same rules.
    parts = re.split(r"([-/])", word)
    return "".join(
        part if part in "-/" else (part[:1].upper() + part[1:].lower())
        for part in parts
    )


def title_case(value: str) -> str:
    """«cable  de RED» -> «Cable de Red»; digits and short acronyms are kept (SSD 512 GB)."""
    words = collapse(value).split(" ")
    return " ".join(_title_word(w, index == 0) for index, w in enumerate(words) if w)


def normalise_unit(value: str) -> str:
    """Units are lower case: «Unidad», «UNIDAD » and «unidad» are one."""
    return collapse(value).lower()


def slug(value: str) -> str:
    """Stable code from a name: «Equipo de red» -> `equipo_de_red`."""
    return re.sub(r"[^a-z0-9]+", "_", fold(value)).strip("_")
