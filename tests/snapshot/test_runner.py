"""Unit tests for sxact.snapshot.runner.

All tests are oracle-free: the WolframAdapter is replaced by a lightweight
fake that returns pre-canned results without touching the network.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from sxact.oracle.result import Result
from sxact.runner.loader import (
    Operation,
    TestCase,
    TestFile,
    TestMeta,
)
from sxact.snapshot.runner import (
    FileSnapshot,
    TestSnapshot,
    _sub_refs,
    _substitute_bindings,
    compute_oracle_hash,
    run_file,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _ok_result(
    repr: str, normalized: str = "", properties: dict | None = None
) -> Result:
    return Result(
        status="ok",
        type="Expr",
        repr=repr,
        normalized=normalized or repr,
        properties=properties or {},
    )


def _make_test_file(
    meta_id: str = "xcore/basic",
    setup: list[Operation] | None = None,
    tests: list[TestCase] | None = None,
) -> TestFile:
    return TestFile(
        meta=TestMeta(id=meta_id, description="test"),
        setup=setup or [],
        tests=tests or [],
        source_path=Path("dummy.toml"),
    )


def _make_test_case(
    id: str = "tc_001",
    ops: list[Operation] | None = None,
    skip: str | None = None,
) -> TestCase:
    return TestCase(
        id=id,
        description="a test",
        operations=ops or [],
        skip=skip,
    )


def _make_adapter(results: list[Result]) -> MagicMock:
    """Return a fake WolframAdapter that returns *results* in order."""
    adapter = MagicMock()
    adapter.get_version.return_value = MagicMock(
        cas_version="14.0.0",
        extra={"xact_version": "1.2.0"},
    )
    adapter.initialize.return_value = MagicMock()
    adapter.teardown.return_value = None
    adapter._build_expr.side_effect = lambda action, args: f"{action}[...]"
    adapter.execute.side_effect = results
    return adapter


# ---------------------------------------------------------------------------
# compute_oracle_hash
# ---------------------------------------------------------------------------


class TestComputeOracleHash:
    def test_matches_spec_formula(self):
        """Hash must match the spec §5.6 formula exactly."""
        normalized = "T[-$1, -$2]"
        props = {"type": "Tensor", "rank": 2}
        canonical = json.dumps(
            {"normalized_output": normalized, "properties": props},
            sort_keys=True,
        )
        expected = f"sha256:{hashlib.sha256(canonical.encode()).hexdigest()[:12]}"
        assert compute_oracle_hash(normalized, props) == expected

    def test_empty_inputs(self):
        h = compute_oracle_hash("", {})
        assert h.startswith("sha256:")
        assert len(h) == len("sha256:") + 12

    def test_properties_order_independent(self):
        """sort_keys=True means property order must not affect hash."""
        props_a = {"rank": 2, "type": "Tensor"}
        props_b = {"type": "Tensor", "rank": 2}
        assert compute_oracle_hash("x", props_a) == compute_oracle_hash("x", props_b)

    def test_different_outputs_differ(self):
        assert compute_oracle_hash("a", {}) != compute_oracle_hash("b", {})


# ---------------------------------------------------------------------------
# _sub_refs / _substitute_bindings
# ---------------------------------------------------------------------------


class TestSubRefs:
    def test_no_refs(self):
        assert _sub_refs("ToCanonical[T[-a,-b]]", {}) == "ToCanonical[T[-a,-b]]"

    def test_single_ref(self):
        assert _sub_refs("$lhs", {"lhs": "T[-a,-b]"}) == "T[-a,-b]"

    def test_multiple_refs(self):
        bindings = {"a": "X", "b": "Y"}
        assert _sub_refs("$a + $b", bindings) == "X + Y"

    def test_missing_ref_preserved(self):
        assert _sub_refs("$missing", {}) == "$missing"

    def test_partial_word(self):
        # $lhs2 should not match $lhs
        assert _sub_refs("$lhs2", {"lhs": "X"}) == "$lhs2"

    def test_ref_in_middle(self):
        assert (
            _sub_refs("ToCanonical[$expr]", {"expr": "T[-a,-b]"})
            == "ToCanonical[T[-a,-b]]"
        )


class TestSubstituteBindings:
    def test_replaces_string_values(self):
        args = {"expression": "$lhs"}
        result = _substitute_bindings(args, {"lhs": "T[-a,-b]"})
        assert result == {"expression": "T[-a,-b]"}

    def test_leaves_non_string_values(self):
        args = {"dimension": 4, "indices": ["a", "b"]}
        result = _substitute_bindings(args, {"a": "X"})
        assert result == {"dimension": 4, "indices": ["a", "b"]}

    def test_original_not_mutated(self):
        args = {"expression": "$lhs"}
        _substitute_bindings(args, {"lhs": "T"})
        assert args["expression"] == "$lhs"


# ---------------------------------------------------------------------------
# run_file
# ---------------------------------------------------------------------------


class TestRunFile:
    def test_returns_file_snapshot(self):
        tc = _make_test_case(
            id="tc_001",
            ops=[Operation(action="Evaluate", args={"expression": "1+1"})],
        )
        tf = _make_test_file(tests=[tc])
        adapter = _make_adapter([_ok_result("2", "2")])

        snap = run_file(tf, adapter)

        assert isinstance(snap, FileSnapshot)
        assert snap.meta_id == "xcore/basic"
        assert len(snap.tests) == 1

    def test_test_snapshot_fields(self):
        tc = _make_test_case(
            id="my_test",
            ops=[Operation(action="Evaluate", args={"expression": "T[-a,-b]"})],
        )
        tf = _make_test_file(tests=[tc])
        adapter = _make_adapter([_ok_result("T[-a,-b]", "T[-$1,-$2]")])

        snap = run_file(tf, adapter)
        ts = snap.tests[0]

        assert isinstance(ts, TestSnapshot)
        assert ts.test_id == "my_test"
        assert ts.oracle_version == "xAct 1.2.0"
        assert ts.mathematica_version == "14.0.0"
        assert ts.raw_output == "T[-a,-b]"
        assert ts.normalized_output == "T[-$1,-$2]"
        assert ts.hash.startswith("sha256:")

    def test_skipped_tests_excluded(self):
        tc1 = _make_test_case(id="tc_ok")
        tc2 = _make_test_case(id="tc_skip", skip="not implemented")
        tc1.operations = [Operation(action="Evaluate", args={"expression": "1"})]

        tf = _make_test_file(tests=[tc1, tc2])
        adapter = _make_adapter([_ok_result("1", "1")])

        snap = run_file(tf, adapter)
        assert len(snap.tests) == 1
        assert snap.tests[0].test_id == "tc_ok"

    def test_setup_commands_included_in_test_commands(self):
        """The commands field must contain setup + test expressions."""
        setup_op = Operation(
            action="DefManifold", args={"name": "M", "dimension": 4, "indices": ["a"]}
        )
        test_op = Operation(action="Evaluate", args={"expression": "M"})
        tc = _make_test_case(id="tc", ops=[test_op])
        tf = _make_test_file(setup=[setup_op], tests=[tc])

        # Two results: one for setup, one for test
        adapter = _make_adapter(
            [
                _ok_result("M"),
                _ok_result("M", "M"),
            ]
        )
        # Let _build_expr return recognisable strings
        adapter._build_expr.side_effect = lambda action, args: (
            "DefManifold[M,4,{a}]" if action == "DefManifold" else "M"
        )

        snap = run_file(tf, adapter)
        commands = snap.tests[0].commands
        assert "DefManifold[M,4,{a}]" in commands
        assert "M" in commands

    def test_store_as_bindings_propagate(self):
        """store_as from one op should be substitutable in the next."""
        op1 = Operation(
            action="Evaluate", args={"expression": "T[-a,-b]"}, store_as="lhs"
        )
        op2 = Operation(action="ToCanonical", args={"expression": "$lhs"})

        tc = _make_test_case(id="tc", ops=[op1, op2])
        tf = _make_test_file(tests=[tc])

        # Capture what args were passed to execute
        captured_args: list[dict] = []

        def fake_execute(ctx, action, args):
            captured_args.append(dict(args))
            return _ok_result("result", "result")

        adapter = MagicMock()
        adapter.get_version.return_value = MagicMock(cas_version="14.0", extra={})
        adapter.initialize.return_value = MagicMock()
        adapter.teardown.return_value = None
        adapter._build_expr.side_effect = lambda action, args: f"{action}[...]"
        adapter.execute.side_effect = fake_execute

        run_file(tf, adapter)

        # Second call: $lhs should have been replaced with "result"
        assert captured_args[1]["expression"] == "result"

    def test_teardown_called_on_success(self):
        tc = _make_test_case(
            id="tc", ops=[Operation(action="Evaluate", args={"expression": "1"})]
        )
        tf = _make_test_file(tests=[tc])
        adapter = _make_adapter([_ok_result("1")])

        run_file(tf, adapter)
        adapter.teardown.assert_called_once()

    def test_teardown_called_on_adapter_error(self):
        """teardown must run even if execute raises."""
        tc = _make_test_case(
            id="tc", ops=[Operation(action="Evaluate", args={"expression": "1"})]
        )
        tf = _make_test_file(tests=[tc])

        adapter = MagicMock()
        adapter.get_version.return_value = MagicMock(cas_version="14.0", extra={})
        adapter.initialize.return_value = MagicMock()
        adapter._build_expr.return_value = "1"
        adapter.execute.side_effect = RuntimeError("boom")

        with pytest.raises(RuntimeError):
            run_file(tf, adapter)

        adapter.teardown.assert_called_once()

    def test_multiple_test_cases(self):
        tc1 = _make_test_case(
            id="t1", ops=[Operation(action="Evaluate", args={"expression": "1"})]
        )
        tc2 = _make_test_case(
            id="t2", ops=[Operation(action="Evaluate", args={"expression": "2"})]
        )
        tf = _make_test_file(tests=[tc1, tc2])
        adapter = _make_adapter([_ok_result("1", "1"), _ok_result("2", "2")])

        snap = run_file(tf, adapter)
        assert [ts.test_id for ts in snap.tests] == ["t1", "t2"]
        assert snap.tests[0].raw_output == "1"
        assert snap.tests[1].raw_output == "2"

    def test_last_ok_result_is_raw_output(self):
        """When multiple ops run, raw_output comes from the last ok result."""
        op1 = Operation(action="Evaluate", args={"expression": "first"})
        op2 = Operation(action="ToCanonical", args={"expression": "second"})
        tc = _make_test_case(id="tc", ops=[op1, op2])
        tf = _make_test_file(tests=[tc])
        adapter = _make_adapter(
            [
                _ok_result("first_result", "first_norm"),
                _ok_result("second_result", "second_norm"),
            ]
        )

        snap = run_file(tf, adapter)
        assert snap.tests[0].raw_output == "second_result"
        assert snap.tests[0].normalized_output == "second_norm"

    def test_empty_test_file(self):
        tf = _make_test_file(tests=[])
        adapter = _make_adapter([])

        snap = run_file(tf, adapter)
        assert snap.tests == []

    def test_meta_id_preserved(self):
        tf = _make_test_file(meta_id="xtensor/riemann")
        adapter = _make_adapter([])

        snap = run_file(tf, adapter)
        assert snap.meta_id == "xtensor/riemann"
