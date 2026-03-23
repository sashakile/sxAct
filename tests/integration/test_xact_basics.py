"""Integration tests for basic xAct operations.

These tests validate the full pipeline:
1. Oracle HTTP server receives xAct expressions
2. xAct evaluates them correctly
3. Results are properly normalized
4. Comparator handles xAct output formats

All tests require the Docker oracle server running with xAct loaded.

NOTE: Each test uses unique manifold/tensor names (M1, M2, etc.) to avoid
conflicts in the persistent Wolfram kernel. xAct protects symbols after
definition, so reusing names across tests causes errors.
"""

import pytest

from sxact.compare import compare
from sxact.compare.comparator import EqualityMode
from sxact.oracle import OracleClient
from sxact.oracle.result import Result


def xact_evaluate(
    oracle: OracleClient, expr: str, context_id: str | None = None
) -> Result:
    """Evaluate an xAct expression and return a Result envelope.

    Uses /evaluate-with-init to ensure xAct is loaded.

    Args:
        oracle: The OracleClient instance.
        expr: The xAct expression to evaluate.
        context_id: Optional context ID for test isolation. When provided,
            symbols are created in a unique context to prevent pollution.
    """
    return oracle.evaluate_with_xact(expr, timeout=120, context_id=context_id)


@pytest.mark.oracle
@pytest.mark.slow
class TestDefineManifold:
    """Test 1: Define manifold, verify output."""

    def test_define_manifold_returns_manifold_info(self, oracle: OracleClient) -> None:
        result = xact_evaluate(oracle, "DefManifold[M1, 4, {a1,b1,c1,d1}]; M1")
        assert result.status == "ok", f"Failed: {result.error}"
        assert "M1" in result.repr, f"Expected M1 in repr, got: {result.repr}"

    def test_manifold_dimension(self, oracle: OracleClient) -> None:
        result = xact_evaluate(
            oracle, "DefManifold[M2, 3, {i2,j2,k2}]; DimOfManifold[M2]"
        )
        assert result.status == "ok", f"Failed: {result.error}"
        assert "3" in result.repr


@pytest.mark.oracle
@pytest.mark.slow
class TestDefineMetric:
    """Test 2: Define metric, verify properties."""

    def test_define_metric_with_signature(self, oracle: OracleClient) -> None:
        expr = """
        DefManifold[M3, 4, {a3,b3,c3,d3}];
        DefMetric[-1, g3[-a3,-b3], CD3];
        SignDetOfMetric[g3]
        """
        result = xact_evaluate(oracle, expr)
        assert result.status == "ok", f"Failed: {result.error}"
        assert "-1" in result.repr, (
            f"Expected -1 for Lorentzian signature, got: {result.repr}"
        )


@pytest.mark.oracle
@pytest.mark.slow
class TestSymmetricTensor:
    """Test 3: Define symmetric tensor, test symmetry."""

    def test_symmetric_tensor_swap_indices(self, oracle: OracleClient) -> None:
        expr = """
        DefManifold[M4, 4, {a4,b4,c4,d4}];
        DefTensor[S4[-a4,-b4], M4, Symmetric[{-a4,-b4}]];
        S4[-b4,-a4] - S4[-a4,-b4] // ToCanonical
        """
        result = xact_evaluate(oracle, expr)
        assert result.status == "ok", f"Failed: {result.error}"
        assert result.repr.strip() == "0", (
            f"Expected 0 for symmetric tensor swap, got: {result.repr}"
        )


@pytest.mark.oracle
@pytest.mark.slow
class TestToCanonical:
    """Test 4: ToCanonical on simple expression."""

    def test_tocanonical_reorders_indices(self, oracle: OracleClient) -> None:
        expr = """
        DefManifold[M5, 4, {a5,b5,c5,d5}];
        DefTensor[T5[-a5,-b5], M5];
        ToCanonical[T5[-b5,-a5]]
        """
        result = xact_evaluate(oracle, expr)
        assert result.status == "ok", f"Failed: {result.error}"
        # ToCanonical reorders indices; result must contain T5 with two index slots
        assert result.repr.startswith("T5[") or result.repr.startswith("-T5["), (
            f"Expected T5[...] expression, got: {result.repr}"
        )


@pytest.mark.oracle
@pytest.mark.slow
class TestMetricContraction:
    """Test 5: Simplify with metric contraction."""

    def test_metric_contraction_raises_index(self, oracle: OracleClient) -> None:
        expr = """
        DefManifold[M6, 4, {a6,b6,c6,d6}];
        DefMetric[1, g6[-a6,-b6], CD6];
        DefTensor[V6[a6], M6];
        g6[a6,b6] V6[-b6] // ContractMetric
        """
        result = xact_evaluate(oracle, expr)
        assert result.status == "ok", f"Failed: {result.error}"
        # Metric contraction raises the index; result must be V6 with one index slot
        assert result.repr.startswith("V6["), (
            f"Expected V6[...] expression, got: {result.repr}"
        )


@pytest.mark.oracle
@pytest.mark.slow
class TestRiemannTensor:
    """Test 6: Riemann tensor definition."""

    def test_riemann_exists_after_metric_definition(self, oracle: OracleClient) -> None:
        expr = """
        DefManifold[M7, 4, {a7,b7,c7,d7}];
        DefMetric[-1, g7[-a7,-b7], CD7];
        RiemannCD7[-a7,-b7,-c7,-d7]
        """
        result = xact_evaluate(oracle, expr)
        assert result.status == "ok", f"Failed: {result.error}"
        assert "Riemann" in result.repr, (
            f"Expected Riemann tensor in repr, got: {result.repr}"
        )


@pytest.mark.oracle
@pytest.mark.slow
class TestSymbolicEquality:
    """Test 7: Two expressions that are symbolically equal."""

    def test_symmetric_tensor_sum_equals_double(
        self, oracle: OracleClient, context_id: str
    ) -> None:
        # Define manifold and symmetric tensor, then test equality:
        # S[-a,-b] + S[-b,-a] should equal 2*S[-a,-b] for symmetric S
        # We apply ToCanonical to both sides since xAct needs explicit canonicalization
        setup = """
        DefManifold[M8, 4, {a8,b8,c8,d8}];
        DefTensor[S8[-a8,-b8], M8, Symmetric[{-a8,-b8}]];
        """
        xact_evaluate(oracle, setup, context_id=context_id)

        # Apply ToCanonical to get canonical forms before comparison
        lhs = xact_evaluate(
            oracle, "(S8[-a8,-b8] + S8[-b8,-a8]) // ToCanonical", context_id=context_id
        )
        rhs = xact_evaluate(
            oracle, "(2*S8[-a8,-b8]) // ToCanonical", context_id=context_id
        )

        assert lhs.status == "ok", f"LHS failed: {lhs.error}"
        assert rhs.status == "ok", f"RHS failed: {rhs.error}"

        cmp = compare(lhs, rhs, oracle)
        assert cmp.equal, f"Expected equality, got: tier={cmp.tier}, diff={cmp.diff}"
        assert cmp.tier <= 2, f"Expected tier 1 or 2, got tier {cmp.tier}"


@pytest.mark.oracle
@pytest.mark.slow
class TestNumericSampling:
    """Test 8: Expression requiring numeric sampling."""

    def test_numeric_evaluation_of_scalar_expression(
        self, oracle: OracleClient
    ) -> None:
        lhs = Result(
            status="ok",
            type="Scalar",
            repr="Sin[x]^2 + Cos[x]^2",
            normalized="Cos[x]^2 + Sin[x]^2",
        )
        rhs = Result(
            status="ok",
            type="Scalar",
            repr="1",
            normalized="1",
        )

        cmp = compare(lhs, rhs, oracle, mode=EqualityMode.NUMERIC)
        assert cmp.equal, f"Expected trig identity to hold: {cmp.diff}"


@pytest.mark.oracle
@pytest.mark.slow
class TestAntisymmetricTensor:
    """Test 9: Antisymmetric tensor properties."""

    def test_antisymmetric_tensor_swap_negates(
        self, oracle: OracleClient, context_id: str
    ) -> None:
        expr = """
        DefManifold[M9, 4, {a9,b9,c9,d9}];
        DefTensor[F9[-a9,-b9], M9, Antisymmetric[{-a9,-b9}]];
        F9[-b9,-a9] + F9[-a9,-b9] // ToCanonical
        """
        result = xact_evaluate(oracle, expr, context_id=context_id)
        assert result.status == "ok", f"Failed: {result.error}"
        assert result.repr.strip() == "0", (
            f"Expected 0 for antisymmetric sum, got: {result.repr}"
        )


@pytest.mark.oracle
@pytest.mark.slow
class TestBianchiIdentity:
    """Test 10: Riemann tensor symmetry properties.

    Note: ToCanonical doesn't apply first Bianchi identity (multi-term symmetry).
    Instead we verify the mono-term symmetries that ToCanonical handles:
    - Antisymmetry in first index pair: R[a,b,c,d] = -R[b,a,c,d]
    - Antisymmetry in second index pair: R[a,b,c,d] = -R[a,b,d,c]
    - Pair exchange symmetry: R[a,b,c,d] = R[c,d,a,b]
    """

    def test_riemann_antisymmetry_first_pair(
        self, oracle: OracleClient, context_id: str
    ) -> None:
        """R[a,b,c,d] + R[b,a,c,d] = 0 (antisymmetry in first pair)."""
        expr = """
        DefManifold[M10, 4, {a10,b10,c10,d10,e10,f10}];
        DefMetric[-1, g10[-a10,-b10], CD10];
        RiemannCD10[-a10,-b10,-c10,-d10] + RiemannCD10[-b10,-a10,-c10,-d10] // ToCanonical
        """
        result = xact_evaluate(oracle, expr, context_id=context_id)
        assert result.status == "ok", f"Failed: {result.error}"
        assert result.repr.strip() == "0", (
            f"Riemann antisymmetry should give 0, got: {result.repr}"
        )

    def test_riemann_pair_exchange(self, oracle: OracleClient, context_id: str) -> None:
        """R[a,b,c,d] - R[c,d,a,b] = 0 (pair exchange symmetry)."""
        expr = """
        DefManifold[M10b, 4, {a10b,b10b,c10b,d10b}];
        DefMetric[-1, g10b[-a10b,-b10b], CD10b];
        RiemannCD10b[-a10b,-b10b,-c10b,-d10b] - RiemannCD10b[-c10b,-d10b,-a10b,-b10b] // ToCanonical
        """
        result = xact_evaluate(oracle, expr, context_id=context_id)
        assert result.status == "ok", f"Failed: {result.error}"
        assert result.repr.strip() == "0", (
            f"Riemann pair exchange should give 0, got: {result.repr}"
        )
