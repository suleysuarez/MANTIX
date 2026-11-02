from pydantic import BaseModel, ConfigDict, Field


class ImportRowError(BaseModel):
    row: int = Field(description="Spreadsheet row number (the header is row 1)")
    field: str | None = Field(examples=["asset_tag"])
    message: str = Field(examples=["asset_tag already exists"])


class ImportResult(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "dry_run": True,
                "success": False,
                "total_rows": 3,
                "created": 0,
                "errors": [
                    {
                        "row": 3,
                        "field": "equipment_type",
                        "message": "unknown equipment type 'TOASTER'",
                    }
                ],
            }
        }
    )

    dry_run: bool
    success: bool = Field(description="True when every row is valid")
    total_rows: int
    created: int = Field(
        description="Rows persisted (always 0 on a dry run or failure)"
    )
    errors: list[ImportRowError]
    valid_rows: int | None = Field(
        default=None,
        description="Rows that passed validation (the summary before confirming)",
    )
    error_rows: int | None = Field(
        default=None, description="Distinct rows with at least one problem"
    )
