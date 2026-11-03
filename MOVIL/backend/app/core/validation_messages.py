"""Pydantic validation errors, said in Spanish and specifically (used by the import report,
where each row's problems are listed for a person to fix)."""

from typing import Any

_PREFIX = "Value error, "


def describe(error: dict[str, Any]) -> str:
    """One validation error as a short Spanish sentence; falls back to Pydantic's text."""
    kind = error.get("type", "")
    ctx = error.get("ctx") or {}
    message = str(error.get("msg", ""))
    simple = {
        "missing": "es obligatorio",
        "int_parsing": "debe ser un número entero",
        "int_from_float": "debe ser un número entero",
        "int_type": "debe ser un número entero",
        "decimal_parsing": "debe ser un número válido",
        "decimal_type": "debe ser un número válido",
        "string_pattern_mismatch": "tiene un formato no válido",
        "literal_error": "no es un valor permitido",
        "bool_parsing": "debe ser sí o no",
    }
    if kind in simple:
        return simple[kind]
    templates = {
        "greater_than_equal": "debe ser mayor o igual a {ge}",
        "greater_than": "debe ser mayor que {gt}",
        "less_than_equal": "debe ser menor o igual a {le}",
        "less_than": "debe ser menor que {lt}",
        "string_too_short": "debe tener al menos {min_length} caracteres",
        "string_too_long": "debe tener como máximo {max_length} caracteres",
        "decimal_max_places": "admite como máximo {decimal_places} decimales",
        "decimal_max_digits": "tiene demasiadas cifras",
    }
    if kind in templates:
        try:
            return templates[kind].format(**ctx)
        except KeyError:
            return message
    if kind == "value_error":
        return message.removeprefix(_PREFIX)
    return message
