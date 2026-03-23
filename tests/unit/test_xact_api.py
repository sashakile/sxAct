"""Unit tests for the xact public Python API."""

import pytest

import xact


@pytest.fixture(autouse=True)
def _reset():
    """Reset xAct state before each test."""
    xact.reset()


@pytest.fixture()
def manifold():
    return xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])


@pytest.fixture()
def metric(manifold):
    return xact.Metric(manifold, "g", signature=-1, covd="CD")


class TestManifold:
    def test_create(self):
        M = xact.Manifold("M", 4, ["a", "b", "c", "d"])
        assert M.name == "M"
        assert M.dim == 4

    def test_repr(self):
        M = xact.Manifold("M", 4, ["a", "b"])
        assert repr(M) == "Manifold('M', 4)"

    def test_dimension(self):
        M = xact.Manifold("M", 4, ["a", "b", "c", "d"])
        assert xact.dimension(M) == 4
        assert xact.dimension("M") == 4


class TestMetric:
    def test_create(self, manifold):
        g = xact.Metric(manifold, "g", signature=-1, covd="CD")
        assert g.name == "g"
        assert g.covd == "CD"

    def test_repr(self, manifold):
        g = xact.Metric(manifold, "g", signature=-1, covd="CD")
        assert repr(g) == "Metric('g', covd='CD')"

    def test_metric_symmetry(self, manifold, metric):
        result = xact.canonicalize("g[-b,-a] - g[-a,-b]")
        assert result == "0"


class TestTensor:
    def test_symmetric(self, manifold, metric):
        T = xact.Tensor("T", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        assert T.name == "T"
        result = xact.canonicalize("T[-b,-a] - T[-a,-b]")
        assert result == "0"

    def test_no_symmetry(self, manifold, metric):
        A = xact.Tensor("A", ["-a", "-b"], manifold)
        assert A.name == "A"

    def test_repr(self, manifold, metric):
        T = xact.Tensor("T", ["-a", "-b"], manifold)
        assert repr(T) == "Tensor('T', ['-a', '-b'])"


class TestCanonicalize:
    def test_zero(self, manifold, metric):
        xact.Tensor("T", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        assert xact.canonicalize("T[-b,-a] - T[-a,-b]") == "0"

    def test_bianchi_identity(self, manifold, metric):
        result = xact.canonicalize(
            "RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]"
        )
        assert result == "0"

    def test_riemann_antisymmetry(self, manifold, metric):
        result = xact.canonicalize("RiemannCD[-a,-b,-c,-d] + RiemannCD[-b,-a,-c,-d]")
        assert result == "0"

    def test_riemann_pair_symmetry(self, manifold, metric):
        result = xact.canonicalize("RiemannCD[-a,-b,-c,-d] - RiemannCD[-c,-d,-a,-b]")
        assert result == "0"


class TestContract:
    def test_lower_index(self, manifold, metric):
        xact.Tensor("V", ["a"], manifold)
        result = xact.contract("V[a] * g[-a,-b]")
        assert result == "V[a]"


class TestSimplify:
    def test_simplify_returns_string(self, manifold, metric):
        result = xact.simplify("g[-a,-b]")
        assert result == "g[-a,-b]"


class TestPerturbation:
    def test_perturb_metric(self, manifold, metric):
        h = xact.Tensor("h", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        xact.Perturbation(h, metric, order=1)
        result = xact.perturb("g[-a,-b]", order=1)
        assert "h" in result

    def test_repr(self, manifold, metric):
        h = xact.Tensor("h", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        p = xact.Perturbation(h, metric, order=1)
        assert repr(p) == "Perturbation('h', 'g', order=1)"


class TestManifoldValidation:
    def test_empty_name(self):
        with pytest.raises(ValueError, match="valid identifier"):
            xact.Manifold("", 4, ["a", "b"])

    def test_invalid_name(self):
        with pytest.raises(ValueError, match="valid identifier"):
            xact.Manifold("123bad", 4, ["a", "b"])

    def test_zero_dimension(self):
        with pytest.raises(ValueError, match="dimension must be >= 1"):
            xact.Manifold("M", 0, ["a", "b"])

    def test_empty_indices(self):
        with pytest.raises(ValueError, match="at least one index"):
            xact.Manifold("M", 4, [])


class TestMetricValidation:
    def test_bad_manifold_type(self, manifold):
        with pytest.raises(TypeError, match="Manifold instance"):
            xact.Metric("not_a_manifold", "g", signature=-1, covd="CD")

    def test_bad_signature(self, manifold):
        with pytest.raises(ValueError, match="signature must be"):
            xact.Metric(manifold, "g", signature=0, covd="CD")

    def test_bad_name(self, manifold):
        with pytest.raises(ValueError, match="valid identifier"):
            xact.Metric(manifold, "", signature=-1, covd="CD")


class TestTensorValidation:
    def test_bad_name(self, manifold, metric):
        with pytest.raises(ValueError, match="valid identifier"):
            xact.Tensor("", ["-a", "-b"], manifold)

    def test_bad_manifold_type(self, manifold, metric):
        with pytest.raises(TypeError, match="Manifold instance"):
            xact.Tensor("T", ["-a", "-b"], "not_a_manifold")


class TestPerturbationValidation:
    def test_bad_tensor_type(self, manifold, metric):
        with pytest.raises(TypeError, match="Tensor instance"):
            xact.Perturbation("not_a_tensor", metric, order=1)

    def test_bad_background_type(self, manifold, metric):
        h = xact.Tensor("h", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        with pytest.raises(TypeError, match="Metric or Tensor"):
            xact.Perturbation(h, "not_a_metric", order=1)

    def test_bad_order(self, manifold, metric):
        h = xact.Tensor("h", ["-a", "-b"], manifold, symmetry="Symmetric[{-a,-b}]")
        with pytest.raises(ValueError, match="order must be >= 1"):
            xact.Perturbation(h, metric, order=0)


class TestReset:
    def test_reset_clears_state(self):
        xact.Manifold("M", 4, ["a", "b", "c", "d"])
        xact.reset()
        # Should be able to redefine the same manifold after reset
        m = xact.Manifold("M", 4, ["a", "b", "c", "d"])
        assert m.name == "M"
