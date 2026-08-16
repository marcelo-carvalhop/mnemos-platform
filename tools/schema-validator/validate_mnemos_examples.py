"""Validate public Mnemos schemas and the canonical networking fixture.

Requires:
    python -m pip install "jsonschema>=4" referencing

Run from repository root:
    python tools/schema-validator/validate_mnemos_examples.py
"""
from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_ROOT = ROOT / "spec" / "schemas"
EXAMPLE = ROOT / "spec" / "examples" / "networking" / "redes-10-cards.sync.json"

SCHEMA_FILES = {
    "card": SCHEMA_ROOT / "card" / "v1.json",
    "deck": SCHEMA_ROOT / "deck" / "v1.json",
    "card-state": SCHEMA_ROOT / "card-state" / "v1.json",
    "review": SCHEMA_ROOT / "review" / "v1.json",
    "review-batch": SCHEMA_ROOT / "review-batch" / "v1.json",
    "sync": SCHEMA_ROOT / "sync" / "v1.json",
    "provision": SCHEMA_ROOT / "provisioning" / "v1.json",
}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    resources: list[tuple[str, Resource]] = []
    loaded: dict[str, dict] = {}

    for name, path in SCHEMA_FILES.items():
        document = load(path)
        Draft202012Validator.check_schema(document)
        loaded[name] = document
        resources.append((document["$id"], Resource.from_contents(document)))

    registry = Registry().with_resources(resources)
    example = load(EXAMPLE)
    errors = sorted(
        Draft202012Validator(loaded["sync"], registry=registry).iter_errors(example),
        key=lambda error: list(error.absolute_path),
    )

    if errors:
        for error in errors:
            path = ".".join(str(value) for value in error.absolute_path) or "<root>"
            print(f"{path}: {error.message}")
        raise SystemExit(1)

    print(f"OK: {len(resources)} schemas validos.")
    print("OK: canonical networking snapshot satisfies mnemos.sync/v1.")
    print(f"OK: {len(example['decks'])} deck, {len(example['cards'])} cards, {len(example['states'])} states.")


if __name__ == "__main__":
    main()
