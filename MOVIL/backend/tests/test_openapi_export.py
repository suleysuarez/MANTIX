import json
from pathlib import Path

from scripts.export_openapi import build_openapi, main

LEGACY_PERMISSIONS = (
    "equipment.manage",
    "equipment.read",
    "users.manage",
    "inventory.manage",
    "reports.read",
)


def test_the_schema_describes_the_api() -> None:
    schema = build_openapi()
    assert schema["info"]["title"]
    assert "/auth/me" in schema["paths"]
    assert "/equipment/{equipment_id}/attachments" in schema["paths"]


def test_the_description_lists_every_role_and_points_to_the_error_codes() -> None:
    description = build_openapi()["info"]["description"]
    for role in ("ADMIN", "SUPERVISOR", "TECHNICIAN", "EMPLOYEE", "AUDITOR"):
        assert role in description
    assert "docs/error-codes.md" in description
    assert "docs/api-reference.md" in description


def test_the_equipment_attachment_description_names_the_real_permission() -> None:
    post = build_openapi()["paths"]["/equipment/{equipment_id}/attachments"]["post"]
    assert "equipos:adjuntar" in post["description"]


def test_the_schema_has_no_legacy_permission_names() -> None:
    dumped = json.dumps(build_openapi(), ensure_ascii=False)
    present = [name for name in LEGACY_PERMISSIONS if name in dumped]
    assert present == []


def test_the_export_is_stable_valid_json(tmp_path: Path) -> None:
    output = tmp_path / "nested" / "openapi.json"
    assert main([str(output)]) == 0
    first = output.read_text(encoding="utf-8")
    assert json.loads(first)["openapi"].startswith("3.")
    assert main([str(output)]) == 0
    assert output.read_text(encoding="utf-8") == first
    assert first.endswith("}\n")
