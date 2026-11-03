"""Los códigos de error son un contrato con la app móvil: este archivo lo vigila."""

import ast
import re
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core import exceptions
from app.core.error_codes import ERROR_CODES
from app.core.errors import _STATUS_CODES, register_exception_handlers
from scripts.error_codes_doc import OUTPUT, build_markdown

APP_DIR = Path(__file__).resolve().parents[1] / "app"
ERROR_CLASSES = {
    name: cls
    for name, cls in vars(exceptions).items()
    if isinstance(cls, type) and issubclass(cls, exceptions.AppError)
}


def _codes_used_in_app() -> list[tuple[str, int, str, str]]:
    """(archivo, línea, tipo de error, código) de cada `XxxError(..., code="...")`."""
    found = []
    for path in APP_DIR.rglob("*.py"):
        for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            if not (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Name)
                and node.func.id in ERROR_CLASSES
            ):
                continue
            for keyword in node.keywords:
                if keyword.arg != "code":
                    continue
                where = f"{path.relative_to(APP_DIR)}:{node.lineno}"
                assert isinstance(keyword.value, ast.Constant) and isinstance(
                    keyword.value.value, str
                ), f"{where}: `code=` debe ser un texto literal"
                found.append((where, node.lineno, node.func.id, keyword.value.value))
    return found


def test_the_app_assigns_specific_codes() -> None:
    assert len(_codes_used_in_app()) >= 100


def test_every_code_is_snake_case() -> None:
    for code in ERROR_CODES:
        assert re.fullmatch(r"[a-z][a-z0-9_]*", code), code


def test_every_code_used_in_the_app_is_registered() -> None:
    unknown = [
        (where, code)
        for where, _, _, code in _codes_used_in_app()
        if code not in ERROR_CODES
    ]
    assert unknown == []


def test_a_code_matches_the_http_status_of_its_error_type() -> None:
    mismatched = []
    for where, _, class_name, code in _codes_used_in_app():
        expected = ERROR_CLASSES[class_name].status_code
        if code in ERROR_CODES and ERROR_CODES[code].status != expected:
            mismatched.append((where, code, ERROR_CODES[code].status, expected))
    assert mismatched == []


def test_every_specific_code_is_used_somewhere() -> None:
    used = {code for *_, code in _codes_used_in_app()}
    unused = sorted(
        code
        for code, info in ERROR_CODES.items()
        if not info.generic and code not in used
    )
    assert unused == [], "códigos documentados que ningún error lanza"


def test_generic_codes_cover_the_fallbacks() -> None:
    fallbacks = set(_STATUS_CODES.values()) | {
        cls.code for cls in ERROR_CLASSES.values()
    }
    missing = sorted(
        code
        for code in fallbacks
        if code not in ERROR_CODES or not ERROR_CODES[code].generic
    )
    assert missing == []


def test_the_documentation_is_up_to_date() -> None:
    """Falla si cambia el registro sin regenerar `docs/error-codes.md`
    (ejecuta `python -m scripts.error_codes_doc`)."""
    assert OUTPUT.read_text(encoding="utf-8").replace("\r\n", "\n") == build_markdown()


def test_a_specific_code_only_changes_that_instance() -> None:
    specific = exceptions.NotFoundError("falta", code="ticket_not_found")
    plain = exceptions.NotFoundError("falta")
    assert specific.code == "ticket_not_found"
    assert plain.code == "not_found"
    assert exceptions.NotFoundError.code == "not_found"


def _client() -> TestClient:
    app = FastAPI()
    register_exception_handlers(app)

    @app.get("/specific")
    def specific() -> None:
        raise exceptions.NotFoundError("el ticket no existe", code="ticket_not_found")

    @app.get("/generic")
    def generic() -> None:
        raise exceptions.ConflictError("choca")

    @app.get("/transition")
    def transition() -> None:
        raise exceptions.InvalidTransitionError("no se puede")

    @app.get("/technician")
    def technician() -> None:
        raise exceptions.InvalidTransitionError(
            "sin técnico", code="ticket_requires_technician"
        )

    return TestClient(app)


def test_the_response_carries_the_specific_code() -> None:
    response = _client().get("/specific")
    assert response.status_code == 404
    body = response.json()
    assert body["code"] == "ticket_not_found"
    assert body["detail"] == "el ticket no existe"
    assert set(body) == {"detail", "code", "errors", "request_id"}


def test_the_response_keeps_the_generic_code_when_none_is_given() -> None:
    response = _client().get("/generic")
    assert (response.status_code, response.json()["code"]) == (409, "conflict")


def test_the_basic_transition_keeps_its_existing_code() -> None:
    client = _client()
    assert client.get("/transition").json()["code"] == "invalid_transition"
    assert client.get("/technician").json()["code"] == "ticket_requires_technician"
