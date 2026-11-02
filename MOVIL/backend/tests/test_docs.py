from scripts.api_docs import OUTPUT, build_markdown


def test_generated_api_reference_is_up_to_date():
    """Fails when endpoints, permissions or states change without regenerating
    `docs/api-reference.md` (run `python -m scripts.api_docs`)."""
    current = OUTPUT.read_text(encoding="utf-8").replace("\r\n", "\n")
    assert current == build_markdown()


def test_reference_lists_every_role_permission_and_state():
    text = build_markdown()
    for token in (
        "ADMIN",
        "SUPERVISOR",
        "TECHNICIAN",
        "EMPLOYEE",
        "AUDITOR",
        "auditoria:ver",
    ):
        assert token in text
    for state in ("submitted", "in_progress", "resolved", "cancelled"):
        assert f"`{state}`" in text
    assert "images/flujo-estados-ticket.png" in text
