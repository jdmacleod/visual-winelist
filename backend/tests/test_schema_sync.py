"""
Unit test: verify the Python WineObject Pydantic model stays in sync with
shared/wine-schema.json.

Runs in CI without any live services (not marked integration).
Fails if a field is added to the schema but missing from the model, or vice versa.
When this test fails, update both the Python model AND the corresponding
Swift/TypeScript types — see CONTRIBUTING.md.
"""

import json
from pathlib import Path

from backend.models.wine import WineObject

SCHEMA_PATH = Path(__file__).parent.parent.parent / "shared" / "wine-schema.json"


def test_schema_file_exists() -> None:
    assert SCHEMA_PATH.exists(), (
        f"shared/wine-schema.json not found at {SCHEMA_PATH}. "
        "The file should exist at the repo root under shared/."
    )


def test_python_model_matches_schema() -> None:
    schema = json.loads(SCHEMA_PATH.read_text())
    schema_fields = set(schema["properties"].keys())
    schema_required = set(schema.get("required", []))

    model_fields = set(WineObject.model_fields.keys())

    missing_from_model = schema_fields - model_fields
    assert not missing_from_model, (
        f"Fields defined in wine-schema.json but absent from Python WineObject: "
        f"{missing_from_model}\n"
        "Add them to backend/backend/models/wine.py and mirror the change in "
        "WineObject.swift (macOS + iOS) and web/src/types/wine.ts."
    )

    extra_in_model = model_fields - schema_fields
    assert not extra_in_model, (
        f"Fields in Python WineObject but absent from wine-schema.json: "
        f"{extra_in_model}\n"
        "Add them to shared/wine-schema.json and mirror the change in "
        "WineObject.swift (macOS + iOS) and web/src/types/wine.ts."
    )

    for field_name in schema_required:
        field = WineObject.model_fields[field_name]
        assert field.is_required(), (
            f"Field '{field_name}' is required in wine-schema.json "
            f"but optional in Python WineObject. "
            "Either remove the default value in the Pydantic model or "
            "remove it from the schema's 'required' array."
        )
