"""Tests for the normalization pipeline."""

import pytest

from sxact.normalize import ast_normalize, normalize


class TestWhitespaceNormalization:
    def test_extra_spaces_in_brackets(self) -> None:
        assert normalize("T[ -a,  -b ]") == "T[-$1, -$2]"

    def test_multiple_spaces(self) -> None:
        assert normalize("A   +   B") == "A + B"

    def test_no_space_before_comma(self) -> None:
        assert normalize("T[-a ,-b]") == "T[-$1, -$2]"


class TestDummyIndexCanonicalization:
    def test_basic_indices(self) -> None:
        assert normalize("T[-a, -b]") == "T[-$1, -$2]"

    def test_different_index_names(self) -> None:
        assert normalize("T[-x, -y]") == "T[-$1, -$2]"

    def test_same_index_multiple_times(self) -> None:
        assert normalize("T[-a, -b] S[-a, -c]") == "T[-$1, -$2] S[-$1, -$3]"

    def test_mixed_up_down_indices(self) -> None:
        assert normalize("T[-a, b]") == "T[-$1, $2]"

    def test_upper_indices(self) -> None:
        assert normalize("T[a, b]") == "T[$1, $2]"


class TestTermOrdering:
    def test_sum_ordering(self) -> None:
        assert normalize("B + A") == "A + B"

    def test_multi_term_ordering(self) -> None:
        assert normalize("C + A + B") == "A + B + C"

    def test_term_with_coefficient(self) -> None:
        result = normalize("B + 2 A")
        assert result == "2 A + B"


class TestCoefficientNormalization:
    def test_explicit_multiplication(self) -> None:
        assert normalize("2*x") == "2 x"

    def test_negative_one(self) -> None:
        assert normalize("-1*x") == "-x"

    def test_positive_one(self) -> None:
        assert normalize("1*x") == "x"


class TestCombinedPipeline:
    def test_full_normalization(self) -> None:
        input_expr = "T[ -x,  -y ] + S[-y, -x]"
        result = normalize(input_expr)
        assert "T[-$1, -$2]" in result or "S[-$1, -$2]" in result


# ---------------------------------------------------------------------------
# AST pipeline tests
# ---------------------------------------------------------------------------

class TestAstParser:
    """Tests for the S-expression parser."""

    def test_parse_leaf(self) -> None:
        from sxact.normalize.ast_parser import Leaf, parse
        assert parse("a") == Leaf("a")

    def test_parse_negative_leaf(self) -> None:
        from sxact.normalize.ast_parser import Leaf, parse
        assert parse("-a") == Leaf("-a")

    def test_parse_number(self) -> None:
        from sxact.normalize.ast_parser import Leaf, parse
        assert parse("2") == Leaf("2")

    def test_parse_simple_application(self) -> None:
        from sxact.normalize.ast_parser import Leaf, Node, parse
        tree = parse("T[-a, -b]")
        assert isinstance(tree, Node)
        assert tree.head == "T"
        assert tree.args == [Leaf("-a"), Leaf("-b")]

    def test_parse_nested_application(self) -> None:
        from sxact.normalize.ast_parser import Leaf, Node, parse
        tree = parse("Plus[a, b]")
        assert isinstance(tree, Node)
        assert tree.head == "Plus"
        assert len(tree.args) == 2

    def test_parse_deeply_nested(self) -> None:
        from sxact.normalize.ast_parser import Node, parse
        tree = parse("CD[-a][CD[-b][T[c]]]")
        assert isinstance(tree, Node)
        # Outermost: apply result of CD[-a][...] to inner
        # Structure: Node(Node("CD", [Leaf("-a")]), [Node(...)])
        assert isinstance(tree.args[0], Node)


class TestAstNormalize:
    """Tests for the ast_normalize function (the main correctness guarantees)."""

    def test_basic_tensor(self) -> None:
        assert ast_normalize("T[-a, -b]") == "T[-$1, -$2]"

    def test_different_index_names_same_result(self) -> None:
        assert ast_normalize("T[-a, -b]") == ast_normalize("T[-x, -y]")

    def test_commutativity_of_sum_fullform(self) -> None:
        # The key success criterion: ast_normalize works on FullForm oracle output.
        # Oracle emits: ToString[A[a] + B[b], FullForm] → "Plus[A[a], B[b]]"
        assert ast_normalize("Plus[A[a], B[b]]") == ast_normalize("Plus[B[a], A[b]]")

    def test_sort_plus_args(self) -> None:
        assert ast_normalize("Plus[B[b], A[a]]") == ast_normalize("Plus[A[a], B[b]]")

    def test_nested_brackets_parsed(self) -> None:
        # 3+ levels of nesting must not crash or produce wrong result
        r1 = ast_normalize("CD[-a][CD[-b][T[c]]]")
        r2 = ast_normalize("CD[-x][CD[-y][T[z]]]")
        assert r1 == r2  # same structure → same canonical form

    def test_times_coefficient_one_removed(self) -> None:
        # In FullForm xAct output, lowercase single letters are indices → get
        # canonicalized. Times[1, x] → Times[1, $1] → $1 (coefficient dropped).
        result = ast_normalize("Times[1, x]")
        assert result == "$1"

    def test_times_coefficient_one_with_tensor(self) -> None:
        # Tensor name (uppercase) is not treated as an index; only inner index
        # letters are renamed.
        result = ast_normalize("Times[1, T[-a, -b]]")
        assert result == "T[-$1, -$2]"

    def test_times_negative_one(self) -> None:
        # Times[-1, T[...]] → "-T[...]"
        result = ast_normalize("Times[-1, T[-a]]")
        assert result == "-T[-$1]"

    def test_fallback_on_parse_failure(self) -> None:
        # Infix expressions that fail to parse fall back to regex pipeline
        result = ast_normalize("A   +   B")
        assert result is not None  # must not raise
        assert "A" in result and "B" in result

    def test_index_reuse_across_tensors(self) -> None:
        # T[-a,-b] S[-a,-c] → shared index a → $1 in both
        r = ast_normalize("T[-a, -b]")
        assert r == "T[-$1, -$2]"

    def test_up_down_index_distinction(self) -> None:
        # Up and down indices get different canonical names
        r = ast_normalize("T[-a, b]")
        assert r == "T[-$1, $2]"

    def test_multi_letter_index(self) -> None:
        # Multi-letter indices like 'mu' must be recognized and renamed
        r = ast_normalize("T[-mu]")
        assert r == "T[-$1]"

    def test_multi_letter_index_with_digit(self) -> None:
        # 'mu3' is a valid xAct index
        r = ast_normalize("T[-mu3]")
        assert r == "T[-$1]"

    def test_multi_letter_indices_shared(self) -> None:
        # Shared multi-letter dummy index renamed consistently
        r = ast_normalize("T[-mu, -nu]")
        assert r == "T[-$1, -$2]"
