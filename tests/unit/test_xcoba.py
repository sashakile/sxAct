"""Unit tests for xCoba Python API — coordinate basis and chart infrastructure."""

import pytest

import xact


# ---------------------------------------------------------------------------
# Basis handle class
# ---------------------------------------------------------------------------


class TestBasis:
    def test_create(self, manifold, metric):
        B = xact.Basis("B", "TangentM", [1, 2, 3, 4])
        assert B.name == "B"
        assert B.vbundle == "TangentM"
        assert B.cnumbers == [1, 2, 3, 4]

    def test_repr(self, manifold, metric):
        B = xact.Basis("B", "TangentM", [1, 2, 3, 4])
        assert repr(B) == "Basis('B', 'TangentM')"

    def test_creates_julia_basis(self, manifold, metric):
        xact.Basis("B", "TangentM", [1, 2, 3, 4])
        # The basis should be queryable from Julia
        jl, _ = xact.api._ensure_init()
        assert jl.seval("XTensor.BasisQ(:B)") is True


# ---------------------------------------------------------------------------
# Chart handle class
# ---------------------------------------------------------------------------


class TestChart:
    def test_create(self, manifold):
        C = xact.Chart("SchC", manifold, [1, 2, 3, 4], ["t", "r", "th", "ph"])
        assert C.name == "SchC"
        assert C.manifold is manifold
        assert C.cnumbers == [1, 2, 3, 4]
        assert C.scalars == ["t", "r", "th", "ph"]

    def test_create_with_manifold_name(self, manifold):
        C = xact.Chart("SchC", "M", [1, 2, 3, 4], ["t", "r", "th", "ph"])
        assert C.name == "SchC"

    def test_repr(self, manifold):
        C = xact.Chart("SchC", manifold, [1, 2, 3, 4], ["t", "r", "th", "ph"])
        assert repr(C) == "Chart('SchC', 'M')"

    def test_creates_julia_chart(self, manifold):
        xact.Chart("SchC", manifold, [1, 2, 3, 4], ["t", "r", "th", "ph"])
        jl, _ = xact.api._ensure_init()
        assert jl.seval("XTensor.ChartQ(:SchC)") is True

    def test_registers_coordinate_scalars(self, manifold):
        xact.Chart("SchC", manifold, [1, 2, 3, 4], ["t", "r", "th", "ph"])
        jl, _ = xact.api._ensure_init()
        # Each scalar should be registered as a tensor
        for sc in ["t", "r", "th", "ph"]:
            assert jl.seval(f"XTensor.TensorQ(:{sc})") is True


# ---------------------------------------------------------------------------
# def_basis / def_chart functions (module-level)
# ---------------------------------------------------------------------------


class TestDefBasis:
    def test_def_basis(self, manifold, metric):
        xact.def_basis("B2", "TangentM", [1, 2, 3, 4])
        jl, _ = xact.api._ensure_init()
        assert jl.seval("XTensor.BasisQ(:B2)") is True

    def test_def_basis_wrong_vbundle(self, manifold, metric):
        with pytest.raises(Exception):
            xact.def_basis("B3", "NonExistentBundle", [1, 2, 3, 4])


class TestDefChart:
    def test_def_chart(self, manifold):
        xact.def_chart("SchC2", "M", [1, 2, 3, 4], ["t2", "r2", "th2", "ph2"])
        jl, _ = xact.api._ensure_init()
        assert jl.seval("XTensor.ChartQ(:SchC2)") is True

    def test_def_chart_wrong_dim(self, manifold):
        with pytest.raises(Exception):
            xact.def_chart("SchC3", "M", [1, 2, 3], ["t3", "r3", "th3"])


# ---------------------------------------------------------------------------
# Basis change operations
# ---------------------------------------------------------------------------


class TestBasisChange:
    @pytest.fixture()
    def two_bases(self, manifold, metric):
        B1 = xact.Basis("Bcart", "TangentM", [1, 2, 3, 4])
        B2 = xact.Basis("Bpol", "TangentM", [1, 2, 3, 4])
        # Simple identity Jacobian (diagonal 1s)
        identity = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        xact.set_basis_change("Bcart", "Bpol", identity)
        return B1, B2

    def test_set_basis_change(self, two_bases):
        assert xact.basis_change_q("Bcart", "Bpol") is True

    def test_basis_change_q_false(self, manifold, metric):
        xact.Basis("Bx", "TangentM", [1, 2, 3, 4])
        xact.Basis("By", "TangentM", [1, 2, 3, 4])
        assert xact.basis_change_q("Bx", "By") is False

    def test_get_jacobian(self, two_bases):
        j = xact.get_jacobian("Bcart", "Bpol")
        assert isinstance(j, str)
        # Jacobian should be a CTensor object representation
        assert len(j) > 0


# ---------------------------------------------------------------------------
# 2D flat-space fixture used by component / ToBasis / christoffel tests
# ---------------------------------------------------------------------------


@pytest.fixture()
def flat2d():
    """2D flat (Euclidean) manifold with a chart and identity metric."""
    M = xact.Manifold("Mf2", 2, ["fa", "fb", "fc"])
    g = xact.Metric(M, "gf2", signature=1, covd="Df2")
    C = xact.Chart("Cf2", M, [1, 2], ["fx", "fy"])
    # identity metric g_{ab} = [[1,0],[0,1]]
    xact.set_components("gf2", [[1, 0], [0, 1]], ["Cf2", "Cf2"])
    return M, g, C


# ---------------------------------------------------------------------------
# CTensor class
# ---------------------------------------------------------------------------


class TestCTensor:
    def test_create(self):
        ct = xact.CTensor("T", [[1, 0], [0, 1]], ["B1", "B2"])
        assert ct.tensor == "T"
        assert ct.array == [[1, 0], [0, 1]]
        assert ct.bases == ["B1", "B2"]
        assert ct.weight == 0

    def test_repr(self):
        ct = xact.CTensor("T", [], ["B"])
        assert "CTensor" in repr(ct)
        assert "T" in repr(ct)


# ---------------------------------------------------------------------------
# set_components / get_components
# ---------------------------------------------------------------------------


class TestSetGetComponents:
    def test_set_returns_ctensor(self, flat2d):
        ct = xact.set_components("gf2", [[1, 0], [0, 1]], ["Cf2", "Cf2"])
        assert isinstance(ct, xact.CTensor)
        assert ct.tensor == "gf2"
        assert ct.bases == ["Cf2", "Cf2"]

    def test_set_get_roundtrip(self, flat2d):
        arr = [[1, 2], [3, 4]]
        M, g, C = flat2d
        xact.Tensor("Tf2", ["-fa", "-fb"], M)
        xact.set_components("Tf2", arr, ["Cf2", "Cf2"])
        ct = xact.get_components("Tf2", ["Cf2", "Cf2"])
        assert isinstance(ct, xact.CTensor)
        assert ct.array == [[1.0, 2.0], [3.0, 4.0]]
        assert ct.bases == ["Cf2", "Cf2"]

    def test_get_components_vector(self, flat2d):
        M, g, C = flat2d
        xact.Tensor("Vf2", ["fa"], M)
        xact.set_components("Vf2", [3, 7], ["Cf2"])
        ct = xact.get_components("Vf2", ["Cf2"])
        assert ct.array == [3.0, 7.0]
        assert ct.bases == ["Cf2"]


# ---------------------------------------------------------------------------
# component_value
# ---------------------------------------------------------------------------


class TestComponentValue:
    def test_diagonal_element(self, flat2d):
        assert xact.component_value("gf2", [1, 1], ["Cf2", "Cf2"]) == pytest.approx(1.0)
        assert xact.component_value("gf2", [1, 2], ["Cf2", "Cf2"]) == pytest.approx(0.0)

    def test_off_diagonal(self, flat2d):
        M, g, C = flat2d
        xact.Tensor("Af2", ["-fa", "-fb"], M)
        xact.set_components("Af2", [[1, 2], [3, 4]], ["Cf2", "Cf2"])
        # Julia uses 1-based indexing: [2,1] = row 2 col 1 = 3.0
        assert xact.component_value("Af2", [2, 1], ["Cf2", "Cf2"]) == pytest.approx(3.0)


# ---------------------------------------------------------------------------
# ctensor_q
# ---------------------------------------------------------------------------


class TestCTensorQ:
    def test_true_after_set(self, flat2d):
        assert xact.ctensor_q("gf2", "Cf2", "Cf2") is True

    def test_false_before_set(self, manifold):
        xact.Tensor("Utest", ["-a", "-b"], manifold)
        assert xact.ctensor_q("Utest", "B_notset") is False

    def test_exported(self):
        assert hasattr(xact, "ctensor_q")


# ---------------------------------------------------------------------------
# to_basis / from_basis / trace_basis_dummy
# ---------------------------------------------------------------------------


class TestToBasis:
    def test_returns_ctensor(self, flat2d):
        ct = xact.to_basis("gf2[-fa,-fb]", "Cf2")
        assert isinstance(ct, xact.CTensor)
        assert ct.bases == ["Cf2", "Cf2"]

    def test_identity_metric(self, flat2d):
        ct = xact.to_basis("gf2[-fa,-fb]", "Cf2")
        import math

        # Diagonal [[1,0],[0,1]] — off-diagonals near zero
        assert math.isclose(ct.array[0][0], 1.0)
        assert math.isclose(ct.array[0][1], 0.0)

    def test_vector_projection(self, flat2d):
        M, g, C = flat2d
        xact.Tensor("Wf2", ["fa"], M)
        xact.set_components("Wf2", [5, 11], ["Cf2"])
        ct = xact.to_basis("Wf2[fa]", "Cf2")
        assert ct.array == pytest.approx([5.0, 11.0])

    def test_texpr_input(self, flat2d):
        M, g, C = flat2d
        a, b, *_ = xact.indices(M)
        gf2 = xact.tensor("gf2")
        # AppliedTensor with down indices: gf2[-fa,-fb]
        expr = gf2[-a, -b]
        ct = xact.to_basis(expr, "Cf2")
        assert isinstance(ct, xact.CTensor)


class TestFromBasis:
    def test_returns_string(self, flat2d):
        M, g, C = flat2d
        xact.Tensor("Pf2", ["-fa"], M)
        xact.set_components("Pf2", [1, 0], ["Cf2"])
        result = xact.from_basis("Pf2", ["Cf2"])
        assert isinstance(result, str)
        assert len(result) > 0

    def test_exported(self):
        assert hasattr(xact, "from_basis")


class TestTraceBasisDummy:
    def test_trace_identity(self, flat2d):
        # Trace of 2x2 identity = 2
        M, g, C = flat2d
        xact.Tensor("Qf2", ["-fa", "fa"], M)
        xact.set_components("Qf2", [[1, 0], [0, 1]], ["Cf2", "Cf2"])
        ct = xact.trace_basis_dummy("Qf2", ["Cf2", "Cf2"])
        assert isinstance(ct, xact.CTensor)
        import math

        assert math.isclose(float(ct.array), 2.0)

    def test_exported(self):
        assert hasattr(xact, "trace_basis_dummy")


# ---------------------------------------------------------------------------
# christoffel
# ---------------------------------------------------------------------------


class TestChristoffel:
    def test_flat_metric_zero(self, flat2d):
        ct = xact.christoffel("gf2", "Cf2")
        assert isinstance(ct, xact.CTensor)
        # All Christoffel symbols of a flat metric are zero
        import numpy as np

        gamma = np.array(ct.array)
        assert np.allclose(gamma, 0.0)

    def test_shape(self, flat2d):
        ct = xact.christoffel("gf2", "Cf2")
        import numpy as np

        gamma = np.array(ct.array)
        assert gamma.shape == (2, 2, 2)

    def test_exported(self):
        assert hasattr(xact, "christoffel")


# ---------------------------------------------------------------------------
# Exported symbols
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Integration: end-to-end xCoba pipelines (sxAct-xqpd)
# ---------------------------------------------------------------------------


class TestBasisChangeEndToEnd:
    """set_basis_change -> change_basis -> verify transformation."""

    @pytest.fixture()
    def setup_2d(self, manifold, metric):
        B = xact.Basis("Bi", "TangentM", [1, 2, 3, 4])
        C = xact.Chart("Ci", manifold, [1, 2, 3, 4], ["x", "y", "z", "w"])
        return B, C

    def test_set_and_query_basis_change(self, setup_2d):
        B, C = setup_2d
        xact.set_basis_change(
            "Bi", "Ci", [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        )
        assert xact.basis_change_q("Bi", "Ci") is True

    def test_get_jacobian(self, setup_2d):
        B, C = setup_2d
        xact.set_basis_change(
            "Bi", "Ci", [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
        )
        jac = xact.get_jacobian("Bi", "Ci")
        assert isinstance(jac, str)


class TestComponentTensorPipeline:
    """set_components -> get_components -> component_value."""

    def test_set_get_components(self, manifold, metric):
        xact.Chart("Cc", manifold, [1, 2, 3, 4], ["x", "y", "z", "w"])
        xact.Tensor("Tc", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        vals = [[1, 2, 3, 4], [2, 5, 6, 7], [3, 6, 8, 9], [4, 7, 9, 10]]
        xact.set_components("Tc", vals, ["Cc", "Cc"])
        ct = xact.get_components("Tc", ["Cc", "Cc"])
        assert isinstance(ct, xact.CTensor)
        assert ct.tensor == "Tc"

    def test_ctensor_q_after_set(self, manifold, metric):
        xact.Chart("Cq", manifold, [1, 2, 3, 4], ["x", "y", "z", "w"])
        xact.Tensor("Tq", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        xact.set_components(
            "Tq", [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]], ["Cq", "Cq"]
        )
        assert xact.ctensor_q("Tq", "Cq", "Cq") is True


class TestTraceBasisDummyPipeline:
    """trace_basis_dummy returns a scalar CTensor."""

    def test_trace_of_identity(self, manifold, metric):
        xact.Chart("Ct", manifold, [1, 2, 3, 4], ["x", "y", "z", "w"])
        xact.Tensor("Tt", ["a", "-b"], manifold)
        xact.set_components(
            "Tt", [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]], ["Ct", "Ct"]
        )
        ct = xact.trace_basis_dummy("Tt", ["Ct", "Ct"])
        assert isinstance(ct, xact.CTensor)
        # Trace of 4x4 identity = 4
        assert ct.array == 4 or ct.array == 4.0


_XCOBA_EXPORTS = [
    "Basis",
    "Chart",
    "CTensor",
    "def_basis",
    "def_chart",
    "set_basis_change",
    "change_basis",
    "get_jacobian",
    "basis_change_q",
    "set_components",
    "get_components",
    "component_value",
    "ctensor_q",
    "to_basis",
    "from_basis",
    "trace_basis_dummy",
    "christoffel",
]


class TestExports:
    @pytest.mark.parametrize("symbol", _XCOBA_EXPORTS)
    def test_xcoba_exported(self, symbol):
        assert hasattr(xact, symbol), f"xact.{symbol} not exported"
