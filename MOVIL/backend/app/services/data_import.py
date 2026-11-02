from pydantic import ValidationError

from app.core.authz import AuthContext
from app.repositories.equipment import EquipmentRepository
from app.schemas.equipment import EquipmentCreate
from app.schemas.report import ImportResult, ImportRowError
from app.services.audit import AuditService

#: Accepted spreadsheet columns; `equipment_type` is the type *code* (e.g. LAPTOP).
IMPORT_FIELDS = (
    "asset_tag",
    "serial_number",
    "equipment_type",
    "brand",
    "model",
    "description",
    "status",
    "purchase_date",
    "purchase_cost",
    "warranty_start_date",
    "warranty_end_date",
)
REQUIRED = ("asset_tag", "equipment_type", "brand", "model")


class EquipmentImportService:
    """Bulk-creates equipment from parsed spreadsheet rows, all-or-nothing.

    Every row is validated with the same Pydantic schema as the single-create
    endpoint, plus duplicate checks against the file and the database. If any
    row fails nothing is written, so a fixed file can simply be re-uploaded.
    """

    def __init__(self, repository: EquipmentRepository, audit: AuditService):
        self.repository = repository
        self.audit = audit

    async def import_equipment(
        self,
        rows: list[dict[str, str]],
        actor: AuthContext,
        *,
        dry_run: bool,
    ) -> ImportResult:
        errors: list[ImportRowError] = []
        missing_columns = [c for c in REQUIRED if rows and c not in rows[0]]
        if missing_columns:
            errors.append(
                ImportRowError(
                    row=1,
                    field=None,
                    message="missing required column(s): " + ", ".join(missing_columns),
                )
            )
            return self._result(rows, errors, created=0, dry_run=dry_run)

        types = await self.repository.active_type_ids_by_code()
        tags = {r.get("asset_tag", "").strip() for r in rows} - {""}
        serials = {r.get("serial_number", "").strip() for r in rows} - {""}
        taken_tags, taken_serials = await self.repository.find_existing_identifiers(
            tags, serials
        )

        payloads: list[EquipmentCreate] = []
        seen_tags: dict[str, int] = {}
        seen_serials: dict[str, int] = {}
        for index, row in enumerate(rows, start=2):
            payload, row_errors = self._parse_row(
                index, row, types, taken_tags, taken_serials, seen_tags, seen_serials
            )
            errors.extend(row_errors)
            if payload is not None:
                payloads.append(payload)

        if errors or dry_run:
            return self._result(rows, errors, created=0, dry_run=dry_run)

        for payload in payloads:
            equipment = await self.repository.create(payload)
            self.repository.record_status_change(
                equipment_id=equipment.id,
                from_status=None,
                to_status=equipment.status,
                changed_by_user_id=actor.id,
                reason="equipment imported",
            )
        self.audit.record(
            user_id=actor.id,
            action="equipment.imported",
            entity_type="equipment",
            entity_id=None,
            new_values={"created": len(payloads)},
        )
        await self.repository.commit()
        return self._result(rows, errors, created=len(payloads), dry_run=dry_run)

    @staticmethod
    def _parse_row(
        index: int,
        row: dict[str, str],
        types: dict[str, int],
        taken_tags: set[str],
        taken_serials: set[str],
        seen_tags: dict[str, int],
        seen_serials: dict[str, int],
    ) -> tuple[EquipmentCreate | None, list[ImportRowError]]:
        errors: list[ImportRowError] = []

        def fail(field: str | None, message: str) -> None:
            errors.append(ImportRowError(row=index, field=field, message=message))

        type_code = row.get("equipment_type", "").strip().upper()
        type_id = types.get(type_code)
        if type_id is None:
            fail("equipment_type", f"unknown equipment type '{type_code}'")

        data: dict[str, object] = {"equipment_type_id": type_id or 0}
        for name in IMPORT_FIELDS:
            if name == "equipment_type":
                continue
            value = row.get(name, "").strip()
            if value != "":
                data[name] = value
        try:
            payload = EquipmentCreate.model_validate(data)
        except ValidationError as exc:
            for problem in exc.errors():
                location = problem["loc"][0] if problem["loc"] else None
                if location == "equipment_type_id":
                    continue  # already reported as equipment_type
                fail(str(location) if location else None, str(problem["msg"]))
            return None, errors

        tag = payload.asset_tag
        if tag in taken_tags:
            fail("asset_tag", f"asset_tag '{tag}' already exists")
        elif tag in seen_tags:
            fail("asset_tag", f"asset_tag '{tag}' repeats row {seen_tags[tag]}")
        seen_tags.setdefault(tag, index)
        serial = payload.serial_number
        if serial:
            if serial in taken_serials:
                fail("serial_number", f"serial_number '{serial}' already exists")
            elif serial in seen_serials:
                fail(
                    "serial_number",
                    f"serial_number '{serial}' repeats row {seen_serials[serial]}",
                )
            seen_serials.setdefault(serial, index)
        return (None if errors else payload), errors

    @staticmethod
    def _result(
        rows: list[dict[str, str]],
        errors: list[ImportRowError],
        *,
        created: int,
        dry_run: bool,
    ) -> ImportResult:
        return ImportResult(
            dry_run=dry_run,
            success=not errors,
            total_rows=len(rows),
            created=created,
            errors=errors,
        )
