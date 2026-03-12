"""Unit tests for sxact.runner.loader.

All tests are oracle-free: they exercise TOML parsing, schema validation, and
the data model without requiring a running CAS.
"""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from sxact.runner.loader import (
    Expected,
    ExpectedProperties,
    LoadError,
    Operation,
    TestCase,
    TestFile,
    load_test_file,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def write_toml(tmp_path: Path, content: str, name: str = "test.toml") -> Path:
    p = tmp_path / name
    p.write_text(textwrap.dedent(content))
    return p


# ---------------------------------------------------------------------------
# Happy-path: minimal valid file
# ---------------------------------------------------------------------------

MINIMAL_TOML = """\
    [meta]
    id          = "xcore/minimal"
    description = "Minimal valid test file"
"""


def test_minimal_file_loads(tmp_path: Path) -> None:
    p = write_toml(tmp_path, MINIMAL_TOML)
    tf = load_test_file(p)
    assert isinstance(tf, TestFile)
    assert tf.meta.id == "xcore/minimal"
    assert tf.meta.description == "Minimal valid test file"
    assert tf.setup == []
    assert tf.tests == []
    assert tf.source_path == p


def test_meta_defaults(tmp_path: Path) -> None:
    p = write_toml(tmp_path, MINIMAL_TOML)
    meta = load_test_file(p).meta
    assert meta.tags == []
    assert meta.layer == 1
    assert meta.oracle_is_axiom is True
    assert meta.skip is None


# ---------------------------------------------------------------------------
# Happy-path: full file with setup and tests
# ---------------------------------------------------------------------------

FULL_TOML = """\
    [meta]
    id              = "xcore/full"
    description     = "Full test file"
    tags            = ["xcore", "layer:1"]
    layer           = 2
    oracle_is_axiom = false
    skip            = "not yet implemented"

    [[setup]]
    action   = "DefManifold"
    store_as = "M"
    [setup.args]
    name      = "M"
    dimension = 4
    indices   = ["a", "b", "c", "d"]

    [[tests]]
    id          = "my-test"
    description = "My test case"
    tags        = ["critical"]
    dependencies = []

    [[tests.operations]]
    action   = "Evaluate"
    store_as = "result"
    [tests.operations.args]
    expression = "1 + 1"

    [[tests.operations]]
    action = "Assert"
    [tests.operations.args]
    condition = "$result == 2"
    message   = "1+1 should be 2"

    [tests.expected]
    is_zero         = false
    comparison_tier = 1
"""


def test_full_file_meta(tmp_path: Path) -> None:
    p = write_toml(tmp_path, FULL_TOML)
    tf = load_test_file(p)
    meta = tf.meta
    assert meta.id == "xcore/full"
    assert meta.tags == ["xcore", "layer:1"]
    assert meta.layer == 2
    assert meta.oracle_is_axiom is False
    assert meta.skip == "not yet implemented"


def test_full_file_setup(tmp_path: Path) -> None:
    p = write_toml(tmp_path, FULL_TOML)
    tf = load_test_file(p)
    assert len(tf.setup) == 1
    op = tf.setup[0]
    assert isinstance(op, Operation)
    assert op.action == "DefManifold"
    assert op.store_as == "M"
    assert op.args["name"] == "M"
    assert op.args["dimension"] == 4
    assert op.args["indices"] == ["a", "b", "c", "d"]


def test_full_file_tests(tmp_path: Path) -> None:
    p = write_toml(tmp_path, FULL_TOML)
    tf = load_test_file(p)
    assert len(tf.tests) == 1
    tc = tf.tests[0]
    assert isinstance(tc, TestCase)
    assert tc.id == "my-test"
    assert tc.description == "My test case"
    assert tc.tags == ["critical"]
    assert tc.dependencies == []
    assert len(tc.operations) == 2


def test_full_file_operations(tmp_path: Path) -> None:
    p = write_toml(tmp_path, FULL_TOML)
    tc = load_test_file(p).tests[0]
    eval_op, assert_op = tc.operations
    assert eval_op.action == "Evaluate"
    assert eval_op.store_as == "result"
    assert eval_op.args == {"expression": "1 + 1"}
    assert assert_op.action == "Assert"
    assert assert_op.store_as is None
    assert assert_op.args["condition"] == "$result == 2"
    assert assert_op.args["message"] == "1+1 should be 2"


def test_full_file_expected(tmp_path: Path) -> None:
    p = write_toml(tmp_path, FULL_TOML)
    exp = load_test_file(p).tests[0].expected
    assert isinstance(exp, Expected)
    assert exp.is_zero is False
    assert exp.comparison_tier == 1
    assert exp.expr is None
    assert exp.normalized is None
    assert exp.properties is None


# ---------------------------------------------------------------------------
# Happy-path: expected with properties
# ---------------------------------------------------------------------------

EXPECTED_PROPS_TOML = """\
    [meta]
    id          = "xcore/props"
    description = "Test with expected properties"

    [[tests]]
    id          = "rank-test"
    description = "Check tensor rank"

    [[tests.operations]]
    action = "Evaluate"
    [tests.operations.args]
    expression = "T[-a,-b]"

    [tests.expected]
    comparison_tier = 1
    [tests.expected.properties]
    rank = 2
    type = "Tensor"
    [tests.expected.properties.symmetry]
    type  = "Symmetric"
    slots = [0, 1]
"""


def test_expected_properties(tmp_path: Path) -> None:
    p = write_toml(tmp_path, EXPECTED_PROPS_TOML)
    exp = load_test_file(p).tests[0].expected
    assert exp is not None
    assert isinstance(exp.properties, ExpectedProperties)
    assert exp.properties.rank == 2
    assert exp.properties.type == "Tensor"
    assert exp.properties.symmetry == {"type": "Symmetric", "slots": [0, 1]}
    assert exp.properties.manifold is None


# ---------------------------------------------------------------------------
# Happy-path: no operations.store_as (optional field)
# ---------------------------------------------------------------------------


def test_operation_without_store_as(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "xcore/no-store"
        description = "Operations without store_as"

        [[tests]]
        id          = "t1"
        description = "No store_as"

        [[tests.operations]]
        action = "Assert"
        [tests.operations.args]
        condition = "True"
    """
    p = write_toml(tmp_path, toml)
    op = load_test_file(p).tests[0].operations[0]
    assert op.store_as is None


# ---------------------------------------------------------------------------
# Error: file not found
# ---------------------------------------------------------------------------


def test_file_not_found(tmp_path: Path) -> None:
    with pytest.raises(LoadError) as exc_info:
        load_test_file(tmp_path / "nonexistent.toml")
    assert "not found" in str(exc_info.value).lower()
    assert exc_info.value.path is not None


# ---------------------------------------------------------------------------
# Error: invalid TOML syntax
# ---------------------------------------------------------------------------


def test_invalid_toml_syntax(tmp_path: Path) -> None:
    p = tmp_path / "bad.toml"
    p.write_text("this is not = valid toml [[[")
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert "toml" in str(exc_info.value).lower()
    assert exc_info.value.path == p


# ---------------------------------------------------------------------------
# Error: missing required meta.id
# ---------------------------------------------------------------------------


def test_missing_meta_id(tmp_path: Path) -> None:
    toml = """\
        [meta]
        description = "Missing id"
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    err = exc_info.value
    assert err.field is not None
    assert "meta" in err.field or "id" in str(err)


# ---------------------------------------------------------------------------
# Error: missing required meta.description
# ---------------------------------------------------------------------------


def test_missing_meta_description(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id = "xcore/no-desc"
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert exc_info.value.field is not None


# ---------------------------------------------------------------------------
# Error: invalid meta.id pattern (uppercase not allowed)
# ---------------------------------------------------------------------------


def test_invalid_meta_id_pattern(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "InvalidID_With_Uppercase"
        description = "Bad id"
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert "$.meta.id" in str(exc_info.value) or "id" in str(exc_info.value)


# ---------------------------------------------------------------------------
# Error: invalid action name
# ---------------------------------------------------------------------------


def test_invalid_action_name(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "xcore/bad-action"
        description = "Bad action"

        [[setup]]
        action = "NotAnAction"
        [setup.args]
        name = "M"
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert exc_info.value.field is not None


# ---------------------------------------------------------------------------
# Error: invalid store_as pattern (spaces not allowed)
# ---------------------------------------------------------------------------


def test_invalid_store_as_pattern(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "xcore/bad-store"
        description = "Bad store_as"

        [[setup]]
        action   = "DefManifold"
        store_as = "bad name with spaces"
        [setup.args]
        name      = "M"
        dimension = 4
        indices   = ["a", "b"]
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert exc_info.value.field is not None


# ---------------------------------------------------------------------------
# Error: invalid meta.layer value
# ---------------------------------------------------------------------------


def test_invalid_layer_value(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "xcore/bad-layer"
        description = "Layer out of range"
        layer       = 99
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert exc_info.value.field is not None


# ---------------------------------------------------------------------------
# Error: test missing required id
# ---------------------------------------------------------------------------


def test_test_missing_id(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "xcore/test-no-id"
        description = "Test case without id"

        [[tests]]
        description = "No id here"

        [[tests.operations]]
        action = "Assert"
        [tests.operations.args]
        condition = "True"
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert exc_info.value.field is not None


# ---------------------------------------------------------------------------
# Error: additional properties rejected
# ---------------------------------------------------------------------------


def test_unknown_top_level_key(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "xcore/extra-key"
        description = "Extra key at top level"

        [unknown_key]
        foo = "bar"
    """
    p = write_toml(tmp_path, toml)
    with pytest.raises(LoadError) as exc_info:
        load_test_file(p)
    assert exc_info.value.path == p


# ---------------------------------------------------------------------------
# Smoke: load the bundled example file
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Happy-path: expected with expect_error
# ---------------------------------------------------------------------------

EXPECT_ERROR_TOML = """\
    [meta]
    id          = "xcore/error-test"
    description = "Test with expect_error"

    [[tests]]
    id          = "should-error"
    description = "This test expects an error"

    [[tests.operations]]
    action = "Evaluate"
    [tests.operations.args]
    expression = "bad_expr"

    [tests.expected]
    expect_error = true
"""


def test_expect_error_loads(tmp_path: Path) -> None:
    p = write_toml(tmp_path, EXPECT_ERROR_TOML)
    exp = load_test_file(p).tests[0].expected
    assert exp is not None
    assert exp.expect_error is True
    assert exp.expr is None


def test_expect_error_false_loads(tmp_path: Path) -> None:
    toml = """\
        [meta]
        id          = "xcore/no-error"
        description = "Test without expect_error"

        [[tests]]
        id          = "should-pass"
        description = "Normal test"

        [[tests.operations]]
        action = "Evaluate"
        [tests.operations.args]
        expression = "1+1"

        [tests.expected]
        expr = "2"
    """
    p = write_toml(tmp_path, toml)
    exp = load_test_file(p).tests[0].expected
    assert exp is not None
    assert exp.expect_error is None


# ---------------------------------------------------------------------------
# Smoke: load the bundled example file
# ---------------------------------------------------------------------------


def test_load_example_xcore_basic() -> None:
    example = Path(__file__).parent.parent / "examples" / "xcore_basic.toml"
    tf = load_test_file(example)
    assert tf.meta.id == "xcore/basic"
    assert len(tf.setup) == 5
    assert len(tf.tests) == 6
    for tc in tf.tests:
        assert tc.id
        assert tc.description
        assert len(tc.operations) >= 1
