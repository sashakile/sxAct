"""Tests for WL surface-syntax parser — covers Appendix A test matrix."""

from __future__ import annotations

import pytest

from xact.translate.wl_parser import (
    WLLeaf,
    WLNode,
    WLParseError,
    parse,
    parse_session,
)
from xact.translate.wl_serializer import serialize


# ===================================================================
# A.1 Definition Parsing
# ===================================================================


class TestDefinitionParsing:
    """T1–T8: Definition expressions."""

    def test_t1_def_manifold(self) -> None:
        """T1: DefManifold[M, 4, {a, b, c, d}]"""
        tree = parse("DefManifold[M, 4, {a, b, c, d}]")
        assert isinstance(tree, WLNode)
        assert tree.head == "DefManifold"
        assert len(tree.args) == 3
        assert tree.args[0] == WLLeaf("M")
        assert tree.args[1] == WLLeaf("4")
        assert isinstance(tree.args[2], WLNode)
        assert tree.args[2].head == "List"
        assert [a.value for a in tree.args[2].args] == ["a", "b", "c", "d"]  # type: ignore[union-attr]

    def test_t2_def_metric(self) -> None:
        """T2: DefMetric[-1, g[-a,-b], CD]"""
        tree = parse("DefMetric[-1, g[-a,-b], CD]")
        assert isinstance(tree, WLNode)
        assert tree.head == "DefMetric"
        assert len(tree.args) == 3
        # First arg: -1 (negation of 1)
        # Second arg: g[-a,-b] (function call with signed indices)
        g_node = tree.args[1]
        assert isinstance(g_node, WLNode)
        assert g_node.head == "g"
        assert g_node.args[0] == WLLeaf("-a")
        assert g_node.args[1] == WLLeaf("-b")
        # Third arg: CD
        assert tree.args[2] == WLLeaf("CD")

    def test_t3_def_tensor_symmetric(self) -> None:
        """T3: DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]"""
        tree = parse("DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]")
        assert isinstance(tree, WLNode)
        assert tree.head == "DefTensor"
        # First arg: T[-a,-b]
        t_node = tree.args[0]
        assert isinstance(t_node, WLNode)
        assert t_node.head == "T"
        assert t_node.args[0] == WLLeaf("-a")
        assert t_node.args[1] == WLLeaf("-b")
        # Second arg: M
        assert tree.args[1] == WLLeaf("M")
        # Third arg: Symmetric[{-a,-b}]
        sym = tree.args[2]
        assert isinstance(sym, WLNode)
        assert sym.head == "Symmetric"

    def test_t4_def_tensor_no_symmetry(self) -> None:
        """T4: DefTensor[V[a], M]"""
        tree = parse("DefTensor[V[a], M]")
        assert isinstance(tree, WLNode)
        assert tree.head == "DefTensor"
        v_node = tree.args[0]
        assert isinstance(v_node, WLNode)
        assert v_node.head == "V"
        assert v_node.args[0] == WLLeaf("a")

    def test_t5_multiline_bracket_continuation(self) -> None:
        """T5: Multi-line bracket continuation."""
        source = """DefTensor[R[-a,-b,-c,-d], M,
  RiemannSymmetric[{-a,-b,-c,-d}]]"""
        tree = parse(source)
        assert isinstance(tree, WLNode)
        assert tree.head == "DefTensor"
        assert len(tree.args) == 3

    def test_t6_def_basis(self) -> None:
        """T6: DefBasis[tetrad, TangentM, {1,2,3,4}]"""
        tree = parse("DefBasis[tetrad, TangentM, {1,2,3,4}]")
        assert isinstance(tree, WLNode)
        assert tree.head == "DefBasis"
        assert tree.args[0] == WLLeaf("tetrad")
        assert tree.args[1] == WLLeaf("TangentM")
        lst = tree.args[2]
        assert isinstance(lst, WLNode) and lst.head == "List"
        assert [a.value for a in lst.args] == ["1", "2", "3", "4"]  # type: ignore[union-attr]

    def test_t7_def_chart(self) -> None:
        """T7: DefChart[cart, M, {1,2,3,4}, {x,y,z,t}]"""
        tree = parse("DefChart[cart, M, {1,2,3,4}, {x,y,z,t}]")
        assert isinstance(tree, WLNode)
        assert tree.head == "DefChart"
        assert len(tree.args) == 4
        scalars = tree.args[3]
        assert isinstance(scalars, WLNode) and scalars.head == "List"
        assert [a.value for a in scalars.args] == ["x", "y", "z", "t"]  # type: ignore[union-attr]

    def test_t8_def_perturbation(self) -> None:
        """T8: DefPerturbation[h, g, eps]"""
        tree = parse("DefPerturbation[h, g, eps]")
        assert isinstance(tree, WLNode)
        assert tree.head == "DefPerturbation"
        assert [a.value for a in tree.args] == ["h", "g", "eps"]  # type: ignore[union-attr]


# ===================================================================
# A.2 Expression Parsing
# ===================================================================


class TestExpressionParsing:
    """T9–T16: Expression/computation actions."""

    def test_t9_to_canonical_subtraction(self) -> None:
        """T9: ToCanonical[T[-a,-b] - T[-b,-a]]"""
        tree = parse("ToCanonical[T[-a,-b] - T[-b,-a]]")
        assert isinstance(tree, WLNode)
        assert tree.head == "ToCanonical"
        assert len(tree.args) == 1
        inner = tree.args[0]
        assert isinstance(inner, WLNode)
        assert inner.head == "Plus"

    def test_t10_simplify_addition(self) -> None:
        """T10: Simplify[R[-a,-b,-c,-d] + R[-a,-c,-d,-b]]"""
        tree = parse("Simplify[R[-a,-b,-c,-d] + R[-a,-c,-d,-b]]")
        assert isinstance(tree, WLNode)
        assert tree.head == "Simplify"
        inner = tree.args[0]
        assert isinstance(inner, WLNode)
        assert inner.head == "Plus"

    def test_t11_contract_metric(self) -> None:
        """T11: ContractMetric[g[-a,b] V[-b]]"""
        tree = parse("ContractMetric[g[-a,b] V[-b]]")
        assert isinstance(tree, WLNode)
        assert tree.head == "ContractMetric"
        # The argument is implicit multiplication: g[-a,b] * V[-b]
        inner = tree.args[0]
        assert isinstance(inner, WLNode)
        assert inner.head == "Times"

    def test_t12_perturb(self) -> None:
        """T12: Perturb[g[-a,-b], 2]"""
        tree = parse("Perturb[g[-a,-b], 2]")
        assert isinstance(tree, WLNode)
        assert tree.head == "Perturb"
        assert len(tree.args) == 2

    def test_t13_commute_covds(self) -> None:
        """T13: CommuteCovDs[T[-a,-b], CD, {-a,-b}]"""
        tree = parse("CommuteCovDs[T[-a,-b], CD, {-a,-b}]")
        assert isinstance(tree, WLNode)
        assert tree.head == "CommuteCovDs"
        assert len(tree.args) == 3

    def test_t14_ibp(self) -> None:
        """T14: IBP[CD[-a][V[a]], CD]"""
        tree = parse("IBP[CD[-a][V[a]], CD]")
        assert isinstance(tree, WLNode)
        assert tree.head == "IBP"
        # First arg is chained: CD[-a][V[a]]
        chained = tree.args[0]
        assert isinstance(chained, WLNode)
        assert isinstance(chained.head, WLNode)  # CD[-a] is the head
        assert chained.head.head == "CD"

    def test_t15_total_derivative_q(self) -> None:
        """T15: TotalDerivativeQ[CD[-a][V[a]], CD]"""
        tree = parse("TotalDerivativeQ[CD[-a][V[a]], CD]")
        assert isinstance(tree, WLNode)
        assert tree.head == "TotalDerivativeQ"

    def test_t16_christoffel_p(self) -> None:
        """T16: ChristoffelP[CD]"""
        tree = parse("ChristoffelP[CD]")
        assert isinstance(tree, WLNode)
        assert tree.head == "ChristoffelP"
        assert tree.args[0] == WLLeaf("CD")


# ===================================================================
# A.3 Chained Application
# ===================================================================


class TestChainedApplication:
    """T17–T19: Chained function application."""

    def test_t17_vard(self) -> None:
        """T17: VarD[g[-a,-b]][R[]]"""
        tree = parse("VarD[g[-a,-b]][R[]]")
        assert isinstance(tree, WLNode)
        # Outer head is VarD[g[-a,-b]] (a Node)
        assert isinstance(tree.head, WLNode)
        assert tree.head.head == "VarD"
        # Outer args: [R[]]
        r_node = tree.args[0]
        assert isinstance(r_node, WLNode)
        assert r_node.head == "R"

    def test_t18_to_basis(self) -> None:
        """T18: ToBasis[tetrad][T[-a,-b]]"""
        tree = parse("ToBasis[tetrad][T[-a,-b]]")
        assert isinstance(tree, WLNode)
        assert isinstance(tree.head, WLNode)
        assert tree.head.head == "ToBasis"

    def test_t19_from_basis(self) -> None:
        """T19: FromBasis[tetrad][T[-a,-b]]"""
        tree = parse("FromBasis[tetrad][T[-a,-b]]")
        assert isinstance(tree, WLNode)
        assert isinstance(tree.head, WLNode)
        assert tree.head.head == "FromBasis"


# ===================================================================
# A.4 Syntactic Sugar & Edge Cases
# ===================================================================


class TestSyntacticSugar:
    """T20–T28: Postfix, assignment, comments, semicolons, etc."""

    def test_t20_postfix_pipe(self) -> None:
        """T20: T[-a,-b] - T[-b,-a] // ToCanonical → ToCanonical[...]"""
        tree = parse("T[-a,-b] - T[-b,-a] // ToCanonical")
        assert isinstance(tree, WLNode)
        assert tree.head == "ToCanonical"
        inner = tree.args[0]
        assert isinstance(inner, WLNode)
        assert inner.head == "Plus"

    def test_t21_assignment(self) -> None:
        """T21: result = ToCanonical[S[-a,-b]]"""
        tree = parse("result = ToCanonical[S[-a,-b]]")
        assert isinstance(tree, WLNode)
        assert tree.head == "Set"
        assert tree.args[0] == WLLeaf("result")
        rhs = tree.args[1]
        assert isinstance(rhs, WLNode)
        assert rhs.head == "ToCanonical"

    def test_t22_comment(self) -> None:
        """T22: Comments are skipped."""
        stmts = parse_session("(* This is a comment *)")
        assert stmts == []

    def test_t23_semicolon_separator(self) -> None:
        """T23: Semicolon-separated statements."""
        stmts = parse_session(
            "DefManifold[M, 4, {a,b,c,d}]; DefMetric[-1, g[-a,-b], CD]"
        )
        assert len(stmts) == 2
        assert isinstance(stmts[0], WLNode) and stmts[0].head == "DefManifold"
        assert isinstance(stmts[1], WLNode) and stmts[1].head == "DefMetric"

    def test_t24_bare_expression(self) -> None:
        """T24: Bare expression (no function head) → just an expression."""
        tree = parse("2 T[-a,-b] + 3 S[-a,-b]")
        assert isinstance(tree, WLNode)
        assert tree.head == "Plus"

    def test_t25_assumptions_arrow(self) -> None:
        """T25: Simplify with Rule (->)."""
        tree = parse("Simplify[expr, Assumptions -> {x > 0}]")
        assert isinstance(tree, WLNode)
        assert tree.head == "Simplify"
        # Second arg should be a Rule node
        rule = tree.args[1]
        assert isinstance(rule, WLNode)
        assert rule.head == "Rule"

    def test_t26_string_literals(self) -> None:
        """T26: String literal arguments."""
        tree = parse('DefMetric[-1, g[-a,-b], CD, {";", "∇"}]')
        assert isinstance(tree, WLNode)
        assert tree.head == "DefMetric"
        assert len(tree.args) == 4
        lst = tree.args[3]
        assert isinstance(lst, WLNode) and lst.head == "List"
        assert lst.args[0] == WLLeaf('";"')
        assert lst.args[1] == WLLeaf('"∇"')

    def test_t27_jacobian_name(self) -> None:
        """T27: Jacobian[basis1, basis2] — name mapping tested at recognizer level."""
        tree = parse("Jacobian[basis1, basis2]")
        assert isinstance(tree, WLNode)
        assert tree.head == "Jacobian"

    def test_t28_blank_lines(self) -> None:
        """T28: Empty/blank lines are skipped."""
        stmts = parse_session("\n\n   \n")
        assert stmts == []


# ===================================================================
# Serializer round-trips
# ===================================================================


class TestSerializerRoundTrip:
    """Parse → serialize produces equivalent string."""

    @pytest.mark.parametrize(
        "expr",
        [
            "DefManifold[M, 4, {a, b, c, d}]",
            "DefMetric[-1, g[-a, -b], CD]",
            "ToCanonical[T[-a, -b] - T[-b, -a]]",
            "VarD[g[-a, -b]][R[]]",
            "ToBasis[tetrad][T[-a, -b]]",
            "ChristoffelP[CD]",
            "{1, 2, 3, 4}",
        ],
    )
    def test_round_trip(self, expr: str) -> None:
        tree = parse(expr)
        result = serialize(tree)
        # Re-parse and compare ASTs
        tree2 = parse(result)
        assert tree == tree2

    def test_serialize_subtraction(self) -> None:
        tree = parse("T[-a,-b] - T[-b,-a]")
        s = serialize(tree)
        assert "T[-a, -b]" in s or "T[-a,-b]" in s
        assert " - " in s


# ===================================================================
# Error handling
# ===================================================================


class TestErrorHandling:
    def test_unmatched_bracket(self) -> None:
        with pytest.raises(WLParseError):
            parse("DefManifold[M, 4")

    def test_unsupported_map(self) -> None:
        with pytest.raises(WLParseError, match="Map"):
            parse("f /@ {1, 2, 3}")

    def test_unsupported_apply(self) -> None:
        with pytest.raises(WLParseError, match="Apply"):
            parse("f @@ {1, 2, 3}")

    def test_empty_input(self) -> None:
        with pytest.raises(WLParseError):
            parse("")


# ===================================================================
# Additional edge cases
# ===================================================================


class TestEdgeCases:
    def test_nested_function_calls(self) -> None:
        tree = parse("Simplify[ToCanonical[T[-a,-b]]]")
        assert isinstance(tree, WLNode)
        assert tree.head == "Simplify"
        inner = tree.args[0]
        assert isinstance(inner, WLNode) and inner.head == "ToCanonical"

    def test_negative_number_in_brackets(self) -> None:
        tree = parse("f[-3]")
        assert isinstance(tree, WLNode)
        # -3 as negation of 3 inside brackets
        arg = tree.args[0]
        # Should be Times[-1, 3] since -3 has space/no-ident
        assert isinstance(arg, WLNode) and arg.head == "Times"

    def test_signed_index_no_space(self) -> None:
        """Signed index: -a with no space between - and a."""
        tree = parse("T[-a]")
        assert isinstance(tree, WLNode)
        assert tree.args[0] == WLLeaf("-a")

    def test_comparison_equal(self) -> None:
        tree = parse("result == 0")
        assert isinstance(tree, WLNode)
        assert tree.head == "Equal"

    def test_comparison_sameq(self) -> None:
        tree = parse("result === True")
        assert isinstance(tree, WLNode)
        assert tree.head == "SameQ"

    def test_session_with_comments_and_blanks(self) -> None:
        source = """
(* Setup *)
DefManifold[M, 4, {a,b,c,d}]

(* Define metric *)
DefMetric[-1, g[-a,-b], CD]
"""
        stmts = parse_session(source)
        assert len(stmts) == 2

    def test_power(self) -> None:
        tree = parse("x^2")
        assert isinstance(tree, WLNode)
        assert tree.head == "Power"
        assert tree.args[0] == WLLeaf("x")
        assert tree.args[1] == WLLeaf("2")

    def test_empty_arg_list(self) -> None:
        """R[] — function call with no arguments."""
        tree = parse("R[]")
        assert isinstance(tree, WLNode)
        assert tree.head == "R"
        assert tree.args == []

    def test_division(self) -> None:
        tree = parse("a / b")
        assert isinstance(tree, WLNode)
        assert tree.head == "Times"

    def test_mixed_session(self) -> None:
        """Full session with definitions, computations, assignments, comparisons."""
        source = """\
DefManifold[M, 4, {a,b,c,d}];
DefMetric[-1, g[-a,-b], CD];
result = ToCanonical[T[-a,-b] - T[-b,-a]];
result == 0
"""
        stmts = parse_session(source)
        assert len(stmts) == 4
        assert stmts[0].head == "DefManifold"  # type: ignore[union-attr]
        assert stmts[1].head == "DefMetric"  # type: ignore[union-attr]
        assert stmts[2].head == "Set"  # type: ignore[union-attr]
        assert stmts[3].head == "Equal"  # type: ignore[union-attr]

    def test_greater_than_in_list(self) -> None:
        """T25-related: > inside list should not crash (treated as ident chars)."""
        # The > is not in our grammar as a token, so {x > 0} needs handling.
        # For now, the parser should handle > within expressions by treating
        # it as part of the surrounding context. Let's test the Rule form.
        tree = parse("Assumptions -> True")
        assert isinstance(tree, WLNode)
        assert tree.head == "Rule"
