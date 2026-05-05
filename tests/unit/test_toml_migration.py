"""Validate that all sxAct TOML test files load via elegua.bridge.load_test_file().

Files under tests/properties/ use the [[properties]] schema (property-runner format)
which is intentionally incompatible with the elegua bridge — they are consumed by
sxact's property runner, not the elegua bridge.  All other *.toml files must load
cleanly.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from elegua.bridge import TestFile, load_test_file
from elegua.errors import SchemaError

TESTS_ROOT = Path(__file__).parent.parent

# Files under this directory use [[properties]] schema — excluded from bridge loading.
_PROPERTY_RUNNER_DIR = TESTS_ROOT / "properties"


def _all_test_toml_files() -> list[Path]:
    return sorted(
        p
        for p in TESTS_ROOT.rglob("*.toml")
        if not p.is_relative_to(_PROPERTY_RUNNER_DIR)
    )


def test_toml_file_collection_is_nonempty() -> None:
    assert len(_all_test_toml_files()) > 0, f"Expected at least one TOML file under {TESTS_ROOT}"


@pytest.mark.parametrize("path", _all_test_toml_files(), ids=lambda p: p.relative_to(TESTS_ROOT).as_posix())
def test_load_test_file_succeeds(path: Path) -> None:
    tf = load_test_file(path)
    assert isinstance(tf, TestFile)
    assert tf.meta.id, f"{path}: meta.id must not be empty"
    assert tf.meta.description, f"{path}: meta.description must not be empty"
    assert tf.setup or tf.tests, f"{path}: must have at least one setup op or test case"


def test_property_files_fail_schema_validation() -> None:
    """Property files must not accidentally load as elegua bridge format."""
    property_files = sorted(_PROPERTY_RUNNER_DIR.glob("*.toml"))
    assert property_files, f"Expected property files under {_PROPERTY_RUNNER_DIR}"
    for path in property_files:
        with pytest.raises(SchemaError, match="missing required 'meta'"):
            load_test_file(path)
