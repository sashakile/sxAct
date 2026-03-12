"""Unit tests for the Layer 2 property runner (no oracle required)."""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from sxact.runner.property_runner import (
    GeneratorSpec,
    PropertyFile,
    PropertyLoadError,
    _fresh_symbol,
    _generate_value,
    _substitute,
    load_property_file,
    run_property_file,
)
from sxact.cli.property import _apply_cross_adapter_diff


# ---------------------------------------------------------------------------
# _fresh_symbol
# ---------------------------------------------------------------------------


class TestFreshSymbol:
    def test_zero_index(self):
        sym = _fresh_symbol("px", 0)
        assert sym.startswith("px")
        assert len(sym) > 2

    def test_different_indices_differ(self):
        syms = {_fresh_symbol("px", i) for i in range(20)}
        assert len(syms) == 20

    def test_deterministic(self):
        assert _fresh_symbol("px", 5) == _fresh_symbol("px", 5)

    def test_no_special_chars(self):
        for i in range(50):
            sym = _fresh_symbol("px", i)
            assert sym.isidentifier(), f"{sym!r} is not a valid identifier"


# ---------------------------------------------------------------------------
# _generate_value
# ---------------------------------------------------------------------------


class TestGenerateValue:
    def test_fresh_symbol_produces_identifier(self):
        gen = GeneratorSpec(name="s", type="Symbol", strategy="fresh_symbol")
        val = _generate_value(gen, "T", 0)
        assert val.isidentifier()

    def test_fresh_symbol_unique_across_samples(self):
        gen = GeneratorSpec(name="s", type="Symbol", strategy="fresh_symbol")
        vals = {_generate_value(gen, "T", i) for i in range(10)}
        assert len(vals) == 10

    def test_symbol_list_produces_list(self):
        gen = GeneratorSpec(
            name="lst", type="SymbolList", strategy="symbol_list", length=3
        )
        val = _generate_value(gen, "T", 0)
        assert val.startswith("{") and val.endswith("}")

    def test_symbol_list_correct_length(self):
        gen = GeneratorSpec(
            name="lst", type="SymbolList", strategy="symbol_list", length=4
        )
        val = _generate_value(gen, "T", 0)
        # Count commas: N elements have N-1 commas
        inner = val[1:-1]
        assert len(inner.split(",")) == 4

    def test_unknown_strategy_raises(self):
        gen = GeneratorSpec(name="s", type="Symbol", strategy="unknown_strategy")
        with pytest.raises(PropertyLoadError):
            _generate_value(gen, "T", 0)


# ---------------------------------------------------------------------------
# _substitute
# ---------------------------------------------------------------------------


class TestSubstitute:
    def test_simple_substitution(self):
        result = _substitute("f[$x]", {"x": "mySymbol"})
        assert result == "f[mySymbol]"

    def test_multiple_vars(self):
        result = _substitute("$a + $b", {"a": "sx", "b": "sy"})
        assert result == "sx + sy"

    def test_repeated_var(self):
        result = _substitute("$s === $s", {"s": "symA"})
        assert result == "symA === symA"

    def test_unbound_raises(self):
        with pytest.raises(KeyError):
            _substitute("$missing", {})


# ---------------------------------------------------------------------------
# load_property_file
# ---------------------------------------------------------------------------


class TestLoadPropertyFile:
    def test_load_xcore_symbol_laws(self):
        path = Path("tests/properties/xcore_symbol_laws.toml")
        if not path.exists():
            pytest.skip("property TOML not found")
        pf = load_property_file(path)
        assert pf.description
        assert len(pf.properties) > 0
        assert pf.properties[0].id == "dagger_involution"

    def test_load_non_property_file_raises(self, tmp_path):
        toml = tmp_path / "test.toml"
        toml.write_text('[meta]\nid = "foo"\nlayer = 1\n')
        with pytest.raises(PropertyLoadError, match="not a property file"):
            load_property_file(toml)

    def test_load_minimal_property_file(self, tmp_path):
        toml = tmp_path / "prop.toml"
        toml.write_text(
            textwrap.dedent("""\
            version = "1.0"
            layer = "property"
            description = "test"

            [[properties]]
            id = "p1"
            name = "test prop"

            [properties.forall]
            [[properties.forall.generators]]
            name = "s"
            type = "Symbol"
            strategy = "fresh_symbol"

            [properties.law]
            lhs = "$s === $s"
            rhs = "True"
            equivalence_type = "identical"

            [properties.verification]
            num_samples = 2
            random_seed = 0
        """)
        )
        pf = load_property_file(toml)
        assert len(pf.properties) == 1
        assert pf.properties[0].num_samples == 2


# ---------------------------------------------------------------------------
# run_property_file — using a mock adapter
# ---------------------------------------------------------------------------


class MockContext:
    pass


class AlwaysTrueAdapter:
    """Adapter that always returns 'True' for Evaluate, no-op otherwise."""

    def initialize(self):
        return MockContext()

    def teardown(self, ctx):
        pass

    def execute(self, ctx, action, args):
        from sxact.oracle.result import Result

        if action == "Evaluate":
            return Result(status="ok", type="Bool", repr="True", normalized="True")
        return Result(status="ok", type="", repr="", normalized="")

    def supported_actions(self):
        return {"Evaluate", "Assert", "DefManifold", "DefTensor", "DefMetric"}


class AlwaysFalseAdapter:
    """Adapter that always returns 'False' for Evaluate."""

    def initialize(self):
        return MockContext()

    def teardown(self, ctx):
        pass

    def execute(self, ctx, action, args):
        from sxact.oracle.result import Result

        if action == "Evaluate":
            return Result(status="ok", type="Bool", repr="False", normalized="False")
        return Result(status="ok", type="", repr="", normalized="")

    def supported_actions(self):
        return {"Evaluate", "Assert"}


class FirstSamplePassesAdapter:
    """Adapter that returns 'True' for the first Evaluate call, 'False' thereafter."""

    def __init__(self):
        self._call_count = 0

    def initialize(self):
        return MockContext()

    def teardown(self, ctx):
        pass

    def execute(self, ctx, action, args):
        from sxact.oracle.result import Result

        if action == "Evaluate":
            self._call_count += 1
            val = "True" if self._call_count == 1 else "False"
            return Result(status="ok", type="Bool", repr=val, normalized=val)
        return Result(status="ok", type="", repr="", normalized="")

    def supported_actions(self):
        return {"Evaluate", "Assert"}


class ErrorAdapter:
    """Adapter that returns error Results."""

    def initialize(self):
        return MockContext()

    def teardown(self, ctx):
        pass

    def execute(self, ctx, action, args):
        from sxact.oracle.result import Result

        return Result(status="error", type="", repr="", normalized="", error="boom")

    def supported_actions(self):
        return {"Evaluate"}


def _make_minimal_prop_file(tmp_path, num_samples=3) -> PropertyFile:
    toml = tmp_path / "prop.toml"
    toml.write_text(
        textwrap.dedent(f"""\
        version = "1.0"
        layer = "property"
        description = "minimal"

        [[properties]]
        id = "p1"
        name = "prop 1"

        [properties.forall]
        [[properties.forall.generators]]
        name = "s"
        type = "Symbol"
        strategy = "fresh_symbol"

        [properties.law]
        lhs = "$s === $s"
        rhs = "True"
        equivalence_type = "identical"

        [properties.verification]
        num_samples = {num_samples}
        random_seed = 0
    """)
    )
    return load_property_file(toml)


class TestRunPropertyFile:
    def test_all_pass(self, tmp_path):
        pf = _make_minimal_prop_file(tmp_path)
        result = run_property_file(pf, AlwaysTrueAdapter())
        assert len(result.results) == 1
        r = result.results[0]
        assert r.status == "pass"
        assert r.num_passed == r.num_samples
        assert r.confidence == 1.0

    def test_all_fail(self, tmp_path):
        pf = _make_minimal_prop_file(tmp_path)
        result = run_property_file(pf, AlwaysFalseAdapter())
        r = result.results[0]
        assert r.status == "fail"
        assert r.num_passed == 0
        assert r.confidence == 0.0
        assert r.counterexample is not None

    def test_partial_pass(self, tmp_path):
        """When some but not all samples pass, status is 'partial' with correct confidence."""
        pf = _make_minimal_prop_file(tmp_path, num_samples=3)
        result = run_property_file(pf, FirstSamplePassesAdapter())
        r = result.results[0]
        assert r.status == "partial"
        assert r.num_passed == 1
        assert r.num_samples == 3
        assert abs(r.confidence - 1 / 3) < 1e-9
        assert r.counterexample is not None  # first failing sample captured

    def test_counterexample_has_bindings(self, tmp_path):
        pf = _make_minimal_prop_file(tmp_path)
        result = run_property_file(pf, AlwaysFalseAdapter())
        cx = result.results[0].counterexample
        assert cx is not None
        assert "s" in cx.bindings
        assert cx.lhs_expr
        assert cx.rhs_expr

    def test_adapter_error_reported(self, tmp_path):
        pf = _make_minimal_prop_file(tmp_path)
        result = run_property_file(pf, ErrorAdapter())
        r = result.results[0]
        assert r.status == "error"

    def test_tag_filter_skips_unmatched(self, tmp_path):
        toml = tmp_path / "prop.toml"
        toml.write_text(
            textwrap.dedent("""\
            version = "1.0"
            layer = "property"
            description = "tag test"

            [[properties]]
            id = "tagged"
            name = "tagged"
            tags = ["critical"]

            [properties.forall]
            [[properties.forall.generators]]
            name = "s"
            type = "Symbol"
            strategy = "fresh_symbol"

            [properties.law]
            lhs = "$s === $s"
            rhs = "True"
            equivalence_type = "identical"

            [properties.verification]
            num_samples = 2
            random_seed = 0

            [[properties]]
            id = "untagged"
            name = "untagged"
            tags = ["other"]

            [properties.forall]
            [[properties.forall.generators]]
            name = "s"
            type = "Symbol"
            strategy = "fresh_symbol"

            [properties.law]
            lhs = "$s === $s"
            rhs = "True"
            equivalence_type = "identical"

            [properties.verification]
            num_samples = 2
            random_seed = 1
        """)
        )
        pf = load_property_file(toml)
        result = run_property_file(pf, AlwaysTrueAdapter(), tag_filter="critical")
        ids = [r.property_id for r in result.results]
        assert "tagged" in ids
        assert "untagged" not in ids

    def test_cross_adapter_diff_agree(self, tmp_path):
        """Both adapters pass → no cross_adapter_diff set."""
        pf = _make_minimal_prop_file(tmp_path)
        primary = run_property_file(pf, AlwaysTrueAdapter())
        secondary = run_property_file(pf, AlwaysTrueAdapter())
        _apply_cross_adapter_diff(primary, secondary, "julia", "python")
        assert all(r.cross_adapter_diff is None for r in primary.results)

    def test_cross_adapter_diff_disagree(self, tmp_path):
        """Primary passes, secondary fails → cross_adapter_diff populated."""
        pf = _make_minimal_prop_file(tmp_path)
        primary = run_property_file(pf, AlwaysTrueAdapter())
        secondary = run_property_file(pf, AlwaysFalseAdapter())
        _apply_cross_adapter_diff(primary, secondary, "julia", "python")
        r = primary.results[0]
        assert r.cross_adapter_diff is not None
        assert "julia" in r.cross_adapter_diff
        assert "python" in r.cross_adapter_diff
        assert "pass" in r.cross_adapter_diff["julia"]
        assert "fail" in r.cross_adapter_diff["python"]

    def test_cross_adapter_diff_missing_property(self, tmp_path):
        """Property missing from secondary run → cross_adapter_diff with 'missing'."""
        from sxact.runner.property_runner import PropertyFileResult

        pf = _make_minimal_prop_file(tmp_path)
        primary = run_property_file(pf, AlwaysTrueAdapter())
        # Secondary with no results (empty file result)
        secondary = PropertyFileResult(
            file_path=str(pf.path), description="", results=[]
        )
        _apply_cross_adapter_diff(primary, secondary, "julia", "python")
        r = primary.results[0]
        assert r.cross_adapter_diff is not None
        assert r.cross_adapter_diff.get("python") == "missing"

    def test_setup_executed_before_properties(self, tmp_path):
        """Setup actions should be executed; failure in setup marks all properties as error."""
        executed = []

        class TrackingAdapter:
            def initialize(self):
                return MockContext()

            def teardown(self, ctx):
                pass

            def execute(self, ctx, action, args):
                from sxact.oracle.result import Result

                executed.append(action)
                return Result(status="ok", type="", repr="True", normalized="True")

            def supported_actions(self):
                return {"Evaluate", "DefManifold"}

        toml = tmp_path / "prop.toml"
        toml.write_text(
            textwrap.dedent("""\
            version = "1.0"
            layer = "property"
            description = "setup test"

            [[setup]]
            action = "DefManifold"
            [setup.args]
            name = "M4"
            dimension = 4

            [[properties]]
            id = "p1"
            name = "p1"
            tags = []

            [properties.forall]
            [[properties.forall.generators]]
            name = "s"
            type = "Symbol"
            strategy = "fresh_symbol"

            [properties.law]
            lhs = "$s === $s"
            rhs = "True"
            equivalence_type = "identical"

            [properties.verification]
            num_samples = 1
            random_seed = 0
        """)
        )
        pf = load_property_file(toml)
        run_property_file(pf, TrackingAdapter())
        assert "DefManifold" in executed
