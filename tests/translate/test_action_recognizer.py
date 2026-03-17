"""Tests for action recognizer — Appendix A test matrix action-level checks."""

from __future__ import annotations

import pytest

from xact.translate import wl_to_action, wl_to_actions


# ===================================================================
# A.1 Definition actions
# ===================================================================


class TestDefinitions:
    def test_t1_def_manifold(self) -> None:
        d = wl_to_action("DefManifold[M, 4, {a, b, c, d}]")
        assert d["action"] == "DefManifold"
        assert d["args"]["name"] == "M"
        assert d["args"]["dimension"] == 4
        assert d["args"]["indices"] == ["a", "b", "c", "d"]

    def test_t2_def_metric(self) -> None:
        d = wl_to_action("DefMetric[-1, g[-a,-b], CD]")
        assert d["action"] == "DefMetric"
        assert d["args"]["signdet"] == -1
        assert d["args"]["metric"] == "g[-a, -b]"
        assert d["args"]["covd"] == "CD"

    def test_t3_def_tensor_symmetric(self) -> None:
        d = wl_to_action("DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]")
        assert d["action"] == "DefTensor"
        assert d["args"]["name"] == "T"
        assert d["args"]["indices"] == ["-a", "-b"]
        assert d["args"]["manifold"] == "M"
        assert "Symmetric" in d["args"]["symmetry"]

    def test_t4_def_tensor_no_symmetry(self) -> None:
        d = wl_to_action("DefTensor[V[a], M]")
        assert d["action"] == "DefTensor"
        assert d["args"]["name"] == "V"
        assert d["args"]["indices"] == ["a"]
        assert d["args"]["manifold"] == "M"
        assert "symmetry" not in d["args"]

    def test_t5_multiline(self) -> None:
        d = wl_to_action(
            "DefTensor[R[-a,-b,-c,-d], M,\n  RiemannSymmetric[{-a,-b,-c,-d}]]"
        )
        assert d["action"] == "DefTensor"
        assert d["args"]["name"] == "R"
        assert len(d["args"]["indices"]) == 4

    def test_t6_def_basis(self) -> None:
        d = wl_to_action("DefBasis[tetrad, TangentM, {1,2,3,4}]")
        assert d["action"] == "DefBasis"
        assert d["args"]["name"] == "tetrad"
        assert d["args"]["vbundle"] == "TangentM"
        assert d["args"]["cnumbers"] == [1, 2, 3, 4]

    def test_t7_def_chart(self) -> None:
        d = wl_to_action("DefChart[cart, M, {1,2,3,4}, {x,y,z,t}]")
        assert d["action"] == "DefChart"
        assert d["args"]["name"] == "cart"
        assert d["args"]["manifold"] == "M"
        assert d["args"]["cnumbers"] == [1, 2, 3, 4]
        assert d["args"]["scalars"] == ["x", "y", "z", "t"]

    def test_t8_def_perturbation(self) -> None:
        d = wl_to_action("DefPerturbation[h, g, eps]")
        assert d["action"] == "DefPerturbation"
        assert d["args"]["name"] == "h"
        assert d["args"]["metric"] == "g"
        assert d["args"]["parameter"] == "eps"


# ===================================================================
# A.2 Expression actions
# ===================================================================


class TestExpressions:
    def test_t9_to_canonical(self) -> None:
        d = wl_to_action("ToCanonical[T[-a,-b] - T[-b,-a]]")
        assert d["action"] == "ToCanonical"
        assert "T[-a, -b]" in d["args"]["expression"]

    def test_t10_simplify(self) -> None:
        d = wl_to_action("Simplify[R[-a,-b,-c,-d] + R[-a,-c,-d,-b]]")
        assert d["action"] == "Simplify"
        assert "R[" in d["args"]["expression"]

    def test_t11_contract_metric(self) -> None:
        d = wl_to_action("ContractMetric[g[-a,b] V[-b]]")
        assert d["action"] == "Contract"

    def test_t12_perturb(self) -> None:
        d = wl_to_action("Perturb[g[-a,-b], 2]")
        assert d["action"] == "Perturb"
        assert d["args"]["order"] == 2

    def test_t13_commute_covds(self) -> None:
        d = wl_to_action("CommuteCovDs[T[-a,-b], CD, {-a,-b}]")
        assert d["action"] == "CommuteCovDs"
        assert d["args"]["covd"] == "CD"

    def test_t14_ibp(self) -> None:
        d = wl_to_action("IBP[CD[-a][V[a]], CD]")
        assert d["action"] == "IntegrateByParts"
        assert d["args"]["covd"] == "CD"

    def test_t15_total_derivative_q(self) -> None:
        d = wl_to_action("TotalDerivativeQ[CD[-a][V[a]], CD]")
        assert d["action"] == "TotalDerivativeQ"
        assert d["args"]["covd"] == "CD"

    def test_t16_christoffel_p(self) -> None:
        d = wl_to_action("ChristoffelP[CD]")
        assert d["action"] == "Christoffel"
        assert d["args"]["covd"] == "CD"


# ===================================================================
# A.3 Chained application
# ===================================================================


class TestChained:
    def test_t17_vard(self) -> None:
        d = wl_to_action("VarD[g[-a,-b]][R[]]")
        assert d["action"] == "VarD"
        assert "g[-a, -b]" in d["args"]["variable"]
        assert "R[]" in d["args"]["expression"]

    def test_t18_to_basis(self) -> None:
        d = wl_to_action("ToBasis[tetrad][T[-a,-b]]")
        assert d["action"] == "ToBasis"
        assert d["args"]["basis"] == "tetrad"

    def test_t19_from_basis(self) -> None:
        d = wl_to_action("FromBasis[tetrad][T[-a,-b]]")
        assert d["action"] == "FromBasis"
        assert d["args"]["basis"] == "tetrad"


# ===================================================================
# A.4 Syntactic sugar & edge cases
# ===================================================================


class TestSyntacticSugar:
    def test_t20_postfix_pipe(self) -> None:
        d = wl_to_action("T[-a,-b] - T[-b,-a] // ToCanonical")
        assert d["action"] == "ToCanonical"

    def test_t21_assignment(self) -> None:
        d = wl_to_action("result = ToCanonical[S[-a,-b]]")
        assert d["action"] == "ToCanonical"
        assert d["store_as"] == "result"

    def test_t22_comment(self) -> None:
        actions = wl_to_actions("(* This is a comment *)")
        assert actions == []

    def test_t23_semicolon(self) -> None:
        actions = wl_to_actions(
            "DefManifold[M, 4, {a,b,c,d}]; DefMetric[-1, g[-a,-b], CD]"
        )
        assert len(actions) == 2
        assert actions[0]["action"] == "DefManifold"
        assert actions[1]["action"] == "DefMetric"

    def test_t24_bare_expression(self) -> None:
        d = wl_to_action("2 T[-a,-b] + 3 S[-a,-b]")
        assert d["action"] == "Evaluate"

    def test_t25_simplify_assumptions(self) -> None:
        d = wl_to_action("Simplify[expr, Assumptions -> {x > 0}]")
        assert d["action"] == "Simplify"
        assert "assumptions" in d["args"]

    def test_t26_string_literals(self) -> None:
        d = wl_to_action('DefMetric[-1, g[-a,-b], CD, {";", "∇"}]')
        assert d["action"] == "DefMetric"

    def test_t27_jacobian(self) -> None:
        d = wl_to_action("Jacobian[basis1, basis2]")
        assert d["action"] == "GetJacobian"
        assert d["args"]["basis1"] == "basis1"
        assert d["args"]["basis2"] == "basis2"

    def test_t28_blank_lines(self) -> None:
        actions = wl_to_actions("\n\n   \n")
        assert actions == []


# ===================================================================
# Additional recognizer tests
# ===================================================================


class TestRecognizer:
    def test_comparison_equal(self) -> None:
        d = wl_to_action("result == 0")
        assert d["action"] == "Assert"
        assert "result == 0" in d["args"]["condition"]

    def test_comparison_sameq(self) -> None:
        d = wl_to_action("result === True")
        assert d["action"] == "Assert"
        assert "===" in d["args"]["condition"]

    def test_unrecognized_head_warns(self) -> None:
        with pytest.warns(UserWarning, match="Unrecognized"):
            d = wl_to_action("MyCustomFunc[x, y]")
        assert d["action"] == "Evaluate"

    def test_perturbation_as_perturb_curvature(self) -> None:
        d = wl_to_action("Perturbation[expr, 2]")
        assert d["action"] == "PerturbCurvature"
        assert d["args"]["order"] == 2

    def test_perturb_curvature_key(self) -> None:
        d = wl_to_action("Riemann1[CD]")
        assert d["action"] == "PerturbCurvature"
        assert d["args"]["key"] == "Riemann1"
        assert d["args"]["covd"] == "CD"

    def test_sort_covds(self) -> None:
        d = wl_to_action("SortCovDs[expr, CD]")
        assert d["action"] == "SortCovDs"
        assert d["args"]["covd"] == "CD"

    def test_set_basis_change(self) -> None:
        d = wl_to_action("SetBasisChange[b1, b2, mat]")
        assert d["action"] == "SetBasisChange"

    def test_change_basis(self) -> None:
        d = wl_to_action("ChangeBasis[expr, target]")
        assert d["action"] == "ChangeBasis"

    def test_ctensor_q(self) -> None:
        d = wl_to_action("CTensorQ[T]")
        assert d["action"] == "CTensorQ"

    def test_full_session(self) -> None:
        source = """\
DefManifold[M, 4, {a,b,c,d}]
DefMetric[-1, g[-a,-b], CD]
result = ToCanonical[T[-a,-b] - T[-b,-a]]
result == 0
"""
        actions = wl_to_actions(source)
        assert len(actions) == 4
        assert actions[0]["action"] == "DefManifold"
        assert actions[1]["action"] == "DefMetric"
        assert actions[2]["action"] == "ToCanonical"
        assert actions[2]["store_as"] == "result"
        assert actions[3]["action"] == "Assert"

    def test_public_api_import(self) -> None:
        from xact.translate import wl_to_action as fn1, wl_to_actions as fn2

        assert callable(fn1)
        assert callable(fn2)
