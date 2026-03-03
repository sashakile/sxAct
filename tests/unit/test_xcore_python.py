"""Tests for the Python sxact.xcore boundary.

Covers:
1. Pure-Python utility functions (no Julia required).
2. Argument marshalling – str → Julia Symbol, list[str] → Vector{Symbol}.
3. Return-value conversion – Julia Symbol → str, Julia vector → list[str].
4. Exception propagation – JuliaError surfaces from Julia calls.
5. Performance – wrapper overhead vs direct Julia call (requires Julia).

These tests do NOT duplicate the L1 Julia unit tests in tests/xcore/*.toml.
"""

from __future__ import annotations

import time
from typing import Any
from unittest.mock import MagicMock, patch

import pytest


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _default_seval(code: str) -> Any:
    code = code.strip()
    if code == "Symbol[]":
        return []
    if code.startswith("Symbol["):
        return code  # opaque; callers just forward to Julia
    if "DaggerCharacter[]" in code and "=" not in code:
        return "†"
    if "LinkCharacter[]" in code and "=" not in code:
        return "_"
    if "WarningFrom[]" in code and "=" not in code:
        return "xAct"
    if "xActDirectory[]" in code and "=" not in code:
        return "/xact"
    if "xActDocDirectory[]" in code and "=" not in code:
        return "/xact/doc"
    return MagicMock()


@pytest.fixture
def mock_julia() -> MagicMock:
    """Minimal mock of the Julia Main module."""
    jl = MagicMock(name="julia_main")
    jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
    jl.seval.side_effect = _default_seval
    return jl


@pytest.fixture
def mock_xcore() -> MagicMock:
    """Minimal mock of the Julia XCore module."""
    xc = MagicMock(name="xcore_module")
    for attr in (
        "xPermNames", "xTensorNames", "xCoreNames",
        "xTableauNames", "xCobaNames", "InvarNames",
        "HarmonicsNames", "xPertNames", "SpinorsNames", "EMNames",
    ):
        setattr(xc, attr, [])
    return xc


@pytest.fixture
def patched(mock_julia: MagicMock, mock_xcore: MagicMock):
    """Patch get_julia/get_xcore for the duration of a test."""
    with (
        patch("sxact.xcore.get_julia", return_value=mock_julia),
        patch("sxact.xcore.get_xcore", return_value=mock_xcore),
    ):
        yield mock_julia, mock_xcore


# ---------------------------------------------------------------------------
# 1. Pure-Python utility functions (no Julia calls)
# ---------------------------------------------------------------------------


class TestPurePythonFunctions:
    """Functions that contain no Julia calls; no mocking required."""

    def test_check_options_dict(self) -> None:
        from sxact.xcore import check_options
        result = check_options({"a": 1, "b": 2})
        assert ("a", 1) in result
        assert ("b", 2) in result

    def test_check_options_tuple_pair(self) -> None:
        from sxact.xcore import check_options
        result = check_options(("x", 42))
        assert result == [("x", 42)]

    def test_check_options_list_of_pairs(self) -> None:
        from sxact.xcore import check_options
        result = check_options([("p", 1), ("q", 2)])
        assert result == [("p", 1), ("q", 2)]

    def test_check_options_multiple_args(self) -> None:
        from sxact.xcore import check_options
        result = check_options({"a": 1}, ("b", 2))
        assert ("a", 1) in result
        assert ("b", 2) in result

    def test_check_options_invalid_scalar_raises(self) -> None:
        from sxact.xcore import check_options
        with pytest.raises(ValueError, match="expected dict or"):
            check_options("not-a-valid-option")

    def test_check_options_list_with_invalid_item_raises(self) -> None:
        from sxact.xcore import check_options
        with pytest.raises(ValueError, match="expected .key, value. pair"):
            check_options(["not-a-pair"])

    def test_delete_duplicates_removes_dupes(self) -> None:
        from sxact.xcore import delete_duplicates
        assert delete_duplicates(["a", "b", "a", "c", "b"]) == ["a", "b", "c"]

    def test_delete_duplicates_preserves_order(self) -> None:
        from sxact.xcore import delete_duplicates
        assert delete_duplicates(["z", "a", "z", "b"]) == ["z", "a", "b"]

    def test_delete_duplicates_empty(self) -> None:
        from sxact.xcore import delete_duplicates
        assert delete_duplicates([]) == []

    def test_duplicate_free_q_true(self) -> None:
        from sxact.xcore import duplicate_free_q
        assert duplicate_free_q(["a", "b", "c"]) is True

    def test_duplicate_free_q_false(self) -> None:
        from sxact.xcore import duplicate_free_q
        assert duplicate_free_q(["a", "b", "a"]) is False

    def test_duplicate_free_q_empty(self) -> None:
        from sxact.xcore import duplicate_free_q
        assert duplicate_free_q([]) is True

    def test_push_unevaluated_appends_in_place(self) -> None:
        from sxact.xcore import push_unevaluated
        lst: list[int] = [1, 2]
        result = push_unevaluated(lst, 3)
        assert result == [1, 2, 3]
        assert result is lst  # mutates in place

    def test_x_evaluate_at_identity(self) -> None:
        from sxact.xcore import x_evaluate_at
        expr = object()
        assert x_evaluate_at(expr, [1, 2]) is expr

    def test_no_pattern_identity(self) -> None:
        from sxact.xcore import no_pattern
        expr = object()
        assert no_pattern(expr) is expr

    def test_report_set_option_noop(self) -> None:
        from sxact.xcore import report_set_option
        result = report_set_option("sym", ("key", "val"))
        assert result is None


# ---------------------------------------------------------------------------
# 2. String ↔ Symbol type conversions at the Python/Julia boundary
# ---------------------------------------------------------------------------


class TestTypeConversions:
    """Verify str↔Symbol and list[str]↔Vector{Symbol} marshalling."""

    def test_symbol_join_passes_args_and_returns_str(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_xc.SymbolJoin.return_value = "<JuliaSymbol:FooBar>"
        from sxact.xcore import symbol_join
        result = symbol_join("Foo", "Bar")
        assert isinstance(result, str)
        assert result == "<JuliaSymbol:FooBar>"

    def test_has_dagger_q_converts_str_to_symbol(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.return_value = "<JuliaSymbol:A†>"
        mock_xc.HasDaggerCharacterQ.return_value = True
        from sxact.xcore import has_dagger_character_q
        has_dagger_character_q("A†")
        mock_jl.Symbol.assert_called_once_with("A†")
        mock_xc.HasDaggerCharacterQ.assert_called_once_with("<JuliaSymbol:A†>")

    def test_make_dagger_symbol_returns_str(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.return_value = "<JuliaSymbol:A>"
        mock_xc.MakeDaggerSymbol.return_value = "<JuliaSymbol:A†>"
        from sxact.xcore import make_dagger_symbol
        result = make_dagger_symbol("A")
        assert isinstance(result, str)
        assert result == "<JuliaSymbol:A†>"

    def test_unlink_symbol_returns_list_of_str(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.return_value = "<JuliaSymbol:Foo_Bar>"
        mock_xc.UnlinkSymbol.return_value = ["<JuliaSymbol:Foo>", "<JuliaSymbol:Bar>"]
        from sxact.xcore import unlink_symbol
        result = unlink_symbol("Foo_Bar")
        assert isinstance(result, list)
        assert all(isinstance(s, str) for s in result)

    def test_link_symbols_uses_vector_via_seval(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.seval.return_value = "<JuliaVector:[Foo,Bar]>"
        mock_xc.LinkSymbols.return_value = "<JuliaSymbol:Foo_Bar>"
        from sxact.xcore import link_symbols
        result = link_symbols(["Foo", "Bar"])
        assert isinstance(result, str)
        seval_calls = [str(c.args[0]) for c in mock_jl.seval.call_args_list]
        assert any("Symbol[" in c for c in seval_calls)

    def test_link_symbols_empty_list_calls_empty_vector(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.seval.return_value = []
        from sxact.xcore import link_symbols
        link_symbols([])
        mock_jl.seval.assert_any_call("Symbol[]")

    def test_find_symbols_returns_list_of_str(self, patched: Any) -> None:
        _, mock_xc = patched
        mock_xc.FindSymbols.return_value = ["<JuliaSymbol:a>", "<JuliaSymbol:b>"]
        from sxact.xcore import find_symbols
        result = find_symbols(MagicMock())
        assert isinstance(result, list)
        assert all(isinstance(s, str) for s in result)


# ---------------------------------------------------------------------------
# 3. API forwarding – each Python function delegates to its Julia counterpart
# ---------------------------------------------------------------------------


class TestAPIForwarding:
    """Each Python wrapper must delegate to the corresponding Julia function."""

    def test_just_one_delegates(self, patched: Any) -> None:
        _, mock_xc = patched
        mock_xc.JustOne.return_value = 42
        from sxact.xcore import just_one
        lst = [42]
        result = just_one(lst)
        mock_xc.JustOne.assert_called_once_with(lst)
        assert result == 42

    def test_map_if_plus_delegates(self, patched: Any) -> None:
        _, mock_xc = patched
        mock_xc.MapIfPlus.return_value = [2, 4]
        from sxact.xcore import map_if_plus
        f = lambda x: x * 2
        map_if_plus(f, [1, 2])
        mock_xc.MapIfPlus.assert_called_once()

    def test_thread_array_delegates(self, patched: Any) -> None:
        _, mock_xc = patched
        from sxact.xcore import thread_array
        thread_array("head", [1], [2])
        mock_xc.ThreadArray.assert_called_once_with("head", [1], [2])

    def test_set_number_of_arguments_delegates(self, patched: Any) -> None:
        _, mock_xc = patched
        from sxact.xcore import set_number_of_arguments
        f = MagicMock()
        set_number_of_arguments(f, 3)
        mock_xc.SetNumberOfArguments.assert_called_once_with(f, 3)

    def test_true_or_false_delegates_and_returns_bool(self, patched: Any) -> None:
        _, mock_xc = patched
        mock_xc.TrueOrFalse.return_value = True
        from sxact.xcore import true_or_false
        result = true_or_false(True)
        mock_xc.TrueOrFalse.assert_called_once_with(True)
        assert result is True

    def test_validate_symbol_passes_julia_symbol(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.return_value = "<JuliaSymbol:Foo>"
        from sxact.xcore import validate_symbol
        validate_symbol("Foo")
        mock_jl.Symbol.assert_called_once_with("Foo")
        mock_xc.ValidateSymbol.assert_called_once_with("<JuliaSymbol:Foo>")

    def test_register_symbol_passes_str_and_package(self, patched: Any) -> None:
        _, mock_xc = patched
        from sxact.xcore import register_symbol
        register_symbol("MyTensor", "xTensor")
        mock_xc.register_symbol.assert_called_once_with("MyTensor", "xTensor")

    def test_x_up_set_converts_both_symbol_args(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
        from sxact.xcore import x_up_set
        x_up_set("prop", "tag", 99)
        mock_xc.xUpSet_b.assert_called_once_with(
            "<JuliaSymbol:prop>", "<JuliaSymbol:tag>", 99
        )

    def test_x_up_append_to_returns_list(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
        mock_xc.xUpAppendTo_b.return_value = [1, 2, 3]
        from sxact.xcore import x_up_append_to
        result = x_up_append_to("prop", "tag", 3)
        assert isinstance(result, list)
        assert result == [1, 2, 3]

    def test_x_up_delete_cases_to_delegates(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
        from sxact.xcore import x_up_delete_cases_to
        pred = lambda x: x > 5
        x_up_delete_cases_to("prop", "tag", pred)
        mock_xc.xUpDeleteCasesTo_b.assert_called_once_with(
            "<JuliaSymbol:prop>", "<JuliaSymbol:tag>", pred
        )

    def test_x_tag_set_converts_tag_to_symbol(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
        from sxact.xcore import x_tag_set
        x_tag_set("MyTag", "key", "val")
        mock_xc.xTagSet_b.assert_called_once_with(
            "<JuliaSymbol:MyTag>", "key", "val"
        )

    def test_x_tension_converts_defcommand_to_symbol(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
        from sxact.xcore import x_tension
        func = MagicMock()
        x_tension("mypkg", "DefTensor", "Beginning", func)
        mock_xc.xTension_b.assert_called_once_with(
            "mypkg", "<JuliaSymbol:DefTensor>", "Beginning", func
        )

    def test_make_x_tensions_converts_defcommand(self, patched: Any) -> None:
        mock_jl, mock_xc = patched
        mock_jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
        from sxact.xcore import make_x_tensions
        make_x_tensions("DefTensor", "End", "arg1")
        mock_xc.MakexTensions.assert_called_once_with(
            "<JuliaSymbol:DefTensor>", "End", "arg1"
        )

    def test_x_perm_names_returns_list(self, patched: Any) -> None:
        _, mock_xc = patched
        mock_xc.xPermNames = ["A", "B"]
        from sxact.xcore import x_perm_names
        assert x_perm_names() == ["A", "B"]

    def test_x_core_names_returns_list(self, patched: Any) -> None:
        _, mock_xc = patched
        mock_xc.xCoreNames = ["ValidateSymbol"]
        from sxact.xcore import x_core_names
        assert x_core_names() == ["ValidateSymbol"]

    def test_sub_head_delegates(self, patched: Any) -> None:
        _, mock_xc = patched
        sentinel = object()
        mock_xc.SubHead.return_value = sentinel
        from sxact.xcore import sub_head
        result = sub_head("expr")
        mock_xc.SubHead.assert_called_once_with("expr")
        assert result is sentinel

    def test_report_set_passes_kwargs(self, patched: Any) -> None:
        _, mock_xc = patched
        ref = MagicMock()
        from sxact.xcore import report_set
        report_set(ref, 42, verbose=False)
        mock_xc.ReportSet.assert_called_once_with(ref, 42, verbose=False)


# ---------------------------------------------------------------------------
# 4. Mutable string refs (dagger, link, warnings, directories)
# ---------------------------------------------------------------------------


class TestMutableRefs:
    """get/set functions for global Julia Ref[] values use seval."""

    def test_dagger_character_reads_via_seval(self, patched: Any) -> None:
        mock_jl, _ = patched
        mock_jl.seval.return_value = "†"
        from sxact.xcore import dagger_character
        result = dagger_character()
        assert result == "†"
        mock_jl.seval.assert_called_with("Main.XCore.DaggerCharacter[]")

    def test_set_dagger_character_writes_via_seval(self, patched: Any) -> None:
        mock_jl, _ = patched
        from sxact.xcore import set_dagger_character
        set_dagger_character("‡")
        call_code = mock_jl.seval.call_args[0][0]
        assert "DaggerCharacter" in call_code
        assert "‡" in call_code

    def test_link_character_reads_via_seval(self, patched: Any) -> None:
        mock_jl, _ = patched
        mock_jl.seval.return_value = "_"
        from sxact.xcore import link_character
        result = link_character()
        assert result == "_"
        mock_jl.seval.assert_called_with("Main.XCore.LinkCharacter[]")

    def test_set_link_character_writes_via_seval(self, patched: Any) -> None:
        mock_jl, _ = patched
        from sxact.xcore import set_link_character
        set_link_character("|")
        call_code = mock_jl.seval.call_args[0][0]
        assert "LinkCharacter" in call_code
        assert "|" in call_code

    def test_warning_from_reads_via_seval(self, patched: Any) -> None:
        mock_jl, _ = patched
        mock_jl.seval.return_value = "xAct"
        from sxact.xcore import warning_from
        result = warning_from()
        assert result == "xAct"

    def test_xact_directory_reads_via_seval(self, patched: Any) -> None:
        mock_jl, _ = patched
        from sxact.xcore import xact_directory
        result = xact_directory()
        # _default_seval returns "/xact" for xActDirectory[] patterns
        assert result == "/xact"

    def test_xact_doc_directory_reads_via_seval(self, patched: Any) -> None:
        mock_jl, _ = patched
        from sxact.xcore import xact_doc_directory
        result = xact_doc_directory()
        # _default_seval returns "/xact/doc" for xActDocDirectory[] patterns
        assert result == "/xact/doc"


# ---------------------------------------------------------------------------
# 5. Exception propagation
# ---------------------------------------------------------------------------


class TestExceptionPropagation:
    """Julia errors must surface as JuliaError in Python callers."""

    def test_julia_error_from_validate_symbol(self, patched: Any) -> None:
        from juliacall import JuliaError
        mock_jl, mock_xc = patched
        mock_jl.Symbol.return_value = "<JuliaSymbol:Foo>"
        mock_xc.ValidateSymbol.side_effect = JuliaError("Symbol already registered")
        from sxact.xcore import validate_symbol
        with pytest.raises(JuliaError):
            validate_symbol("Foo")

    def test_julia_error_from_just_one(self, patched: Any) -> None:
        from juliacall import JuliaError
        _, mock_xc = patched
        mock_xc.JustOne.side_effect = JuliaError("Expected singleton list")
        from sxact.xcore import just_one
        with pytest.raises(JuliaError):
            just_one([1, 2])

    def test_julia_error_from_register_symbol(self, patched: Any) -> None:
        from juliacall import JuliaError
        _, mock_xc = patched
        mock_xc.register_symbol.side_effect = JuliaError("Already owned by xTensor")
        from sxact.xcore import register_symbol
        with pytest.raises(JuliaError):
            register_symbol("ExistingSymbol", "xCoba")

    def test_julia_error_from_x_up_set(self, patched: Any) -> None:
        from juliacall import JuliaError
        mock_jl, mock_xc = patched
        mock_jl.Symbol.side_effect = lambda s: f"<JuliaSymbol:{s}>"
        mock_xc.xUpSet_b.side_effect = JuliaError("Upvalue conflict")
        from sxact.xcore import x_up_set
        with pytest.raises(JuliaError):
            x_up_set("prop", "tag", "val")

    def test_julia_error_message_is_readable(self, patched: Any) -> None:
        """JuliaError must carry a readable message string."""
        from juliacall import JuliaError
        _, mock_xc = patched
        msg = "Duplicate symbol: AlreadyThere"
        mock_xc.JustOne.side_effect = JuliaError(msg)
        from sxact.xcore import just_one
        with pytest.raises(JuliaError, match=msg):
            just_one([])


# ---------------------------------------------------------------------------
# 6. Performance – wrapper overhead vs direct Julia call (requires live Julia)
# ---------------------------------------------------------------------------

_PERF_REPS = 500


@pytest.mark.slow
class TestPerformance:
    """Wrapper overhead must be < 2× direct Julia call (sxAct-k0a criterion)."""

    def _measure(self, fn, reps: int) -> float:
        t0 = time.perf_counter()
        for _ in range(reps):
            fn()
        return time.perf_counter() - t0

    def test_symbol_join_overhead(self) -> None:
        import sxact.xcore as xc
        from sxact.xcore._runtime import get_xcore

        xc.symbol_join("Warm", "Up")  # JIT warm-up

        jl_xc = get_xcore()
        julia_elapsed = self._measure(lambda: jl_xc.SymbolJoin("A", "B"), _PERF_REPS)
        python_elapsed = self._measure(lambda: xc.symbol_join("A", "B"), _PERF_REPS)

        ratio = python_elapsed / julia_elapsed if julia_elapsed > 0 else float("inf")
        assert ratio < 2.0, (
            f"symbol_join is {ratio:.2f}× slower than direct Julia "
            f"(limit 2.0×); julia={julia_elapsed*1e3:.1f}ms "
            f"python={python_elapsed*1e3:.1f}ms over {_PERF_REPS} reps"
        )

    def test_has_dagger_character_q_overhead(self) -> None:
        import sxact.xcore as xc
        from sxact.xcore._runtime import get_xcore, get_julia

        xc.has_dagger_character_q("A†")  # JIT warm-up

        jl_xc = get_xcore()
        jl = get_julia()
        # Fair comparison: direct call must also do the str→Symbol conversion
        julia_elapsed = self._measure(
            lambda: jl_xc.HasDaggerCharacterQ(jl.Symbol("A†")), _PERF_REPS
        )
        python_elapsed = self._measure(
            lambda: xc.has_dagger_character_q("A†"), _PERF_REPS
        )

        ratio = python_elapsed / julia_elapsed if julia_elapsed > 0 else float("inf")
        assert ratio < 2.0, (
            f"has_dagger_character_q is {ratio:.2f}× slower than direct Julia "
            f"(limit 2.0×); julia={julia_elapsed*1e3:.1f}ms "
            f"python={python_elapsed*1e3:.1f}ms over {_PERF_REPS} reps"
        )

    def test_delete_duplicates_is_pure_python(self) -> None:
        """Pure-Python delete_duplicates has no Julia overhead to measure."""
        import sxact.xcore as xc
        lst = list(range(20))
        t0 = time.perf_counter()
        for _ in range(10_000):
            xc.delete_duplicates(lst)
        elapsed = time.perf_counter() - t0
        # Must complete 10k calls in under 1 second (pure Python; no Julia)
        assert elapsed < 1.0, f"delete_duplicates too slow: {elapsed:.3f}s for 10k calls"
