"""Tests for xact._bridge — safe Julia argument builders."""

import pytest

from xact._bridge import (
    jl_call,
    jl_escape,
    jl_int,
    jl_path,
    jl_str,
    jl_sym,
    jl_sym_list,
    validate_ident,
)


class TestValidateIdent:
    def test_valid_identifiers(self) -> None:
        assert validate_ident("M") == "M"
        assert validate_ident("MyTensor") == "MyTensor"
        assert validate_ident("_private") == "_private"
        assert validate_ident("T123") == "T123"

    def test_injection_rejected(self) -> None:
        with pytest.raises(ValueError, match="Invalid identifier"):
            validate_ident("M; evil()")

    def test_special_chars_rejected(self) -> None:
        with pytest.raises(ValueError):
            validate_ident("a b")
        with pytest.raises(ValueError):
            validate_ident("a.b")
        with pytest.raises(ValueError):
            validate_ident("")

    def test_digit_start_rejected(self) -> None:
        with pytest.raises(ValueError):
            validate_ident("1abc")

    def test_context_in_error(self) -> None:
        with pytest.raises(ValueError, match="manifold name"):
            validate_ident("bad name", "manifold name")


class TestJlEscape:
    def test_backslash(self) -> None:
        assert jl_escape("a\\b") == "a\\\\b"

    def test_double_quote(self) -> None:
        assert jl_escape('a"b') == 'a\\"b'

    def test_dollar_sign(self) -> None:
        assert jl_escape("a$b") == "a\\$b"

    def test_clean_string(self) -> None:
        assert jl_escape("T[-a,-b]") == "T[-a,-b]"


class TestJlSym:
    def test_valid(self) -> None:
        assert jl_sym("M") == ":M"
        assert jl_sym("CovD", "covd") == ":CovD"

    def test_injection_rejected(self) -> None:
        with pytest.raises(ValueError):
            jl_sym("M; evil()")

    def test_empty_rejected(self) -> None:
        with pytest.raises(ValueError):
            jl_sym("")


class TestJlInt:
    def test_valid(self) -> None:
        assert jl_int(4) == "4"
        assert jl_int(0) == "0"
        assert jl_int(-1) == "-1"

    def test_string_rejected(self) -> None:
        with pytest.raises(TypeError, match="Expected int"):
            jl_int("not_a_number")  # type: ignore[arg-type]

    def test_float_rejected(self) -> None:
        with pytest.raises(TypeError):
            jl_int(3.14)  # type: ignore[arg-type]

    def test_bool_rejected(self) -> None:
        with pytest.raises(TypeError):
            jl_int(True)  # type: ignore[arg-type]


class TestJlStr:
    def test_basic(self) -> None:
        assert jl_str("T[-a,-b]") == '"T[-a,-b]"'

    def test_escaping(self) -> None:
        assert jl_str('a"b') == '"a\\"b"'

    def test_dollar_escaped(self) -> None:
        assert jl_str("$x") == '"\\$x"'


class TestJlSymList:
    def test_basic(self) -> None:
        assert jl_sym_list(["a", "b", "c"]) == "[:a, :b, :c]"

    def test_empty(self) -> None:
        assert jl_sym_list([]) == "[]"

    def test_invalid_element_rejected(self) -> None:
        with pytest.raises(ValueError):
            jl_sym_list(["a", "b; evil()"])


class TestJlPath:
    def test_basic(self) -> None:
        assert jl_path("/tmp/foo") == '"/tmp/foo"'

    def test_spaces(self) -> None:
        assert jl_path("/tmp/my dir/file") == '"/tmp/my dir/file"'

    def test_backslash(self) -> None:
        assert jl_path("C:\\Users\\foo") == '"C:\\\\Users\\\\foo"'


class TestJlCall:
    """Test jl_call with a mock Julia object."""

    def test_call_builds_expression(self) -> None:
        """Verify the seval expression is built correctly."""
        calls: list[str] = []

        class MockJl:
            def seval(self, expr: str) -> str:
                calls.append(expr)
                return "ok"

        jl_call(MockJl(), "xAct.def_manifold!", ":M", "4", "[:a, :b]")
        assert calls == ["xAct.def_manifold!(:M, 4, [:a, :b])"]

    def test_call_wraps_errors(self) -> None:
        class FailJl:
            def seval(self, expr: str) -> None:
                raise Exception("Julia boom")

        with pytest.raises(RuntimeError, match="Julia call failed"):
            jl_call(FailJl(), "xAct.ToCanonical", '"T[-a,-b]"')

    def test_call_composes_with_builders(self) -> None:
        """End-to-end: builders + jl_call produce correct seval string."""
        calls: list[str] = []

        class MockJl:
            def seval(self, expr: str) -> str:
                calls.append(expr)
                return "ok"

        jl_call(
            MockJl(),
            "xAct.def_manifold!",
            jl_sym("M", "manifold"),
            jl_int(4),
            jl_sym_list(["a", "b", "c", "d"], "indices"),
        )
        assert calls == ["xAct.def_manifold!(:M, 4, [:a, :b, :c, :d])"]
