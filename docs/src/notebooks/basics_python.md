!!! tip "Run this notebook"
    Download the [Jupyter notebook](https://github.com/sashakile/sxAct/blob/main/notebooks/python/basics.ipynb) or open it in Google Colab.

# sxAct — Getting Started (Python)

> **Note:** Auto-generated from `notebooks/python/basics.qmd` via Quarto.
> Edit the source `.qmd` file, not the `.ipynb`.

## Overview

This notebook walks through the same workflow as the Julia version,
using the `xact` Python package. Under the hood, all computation
is performed by the Julia engine — but the API is fully Pythonic.

**Requirements:** Python 3.10+, Julia 1.12+.

## 1. Setup

```python
# Uncomment if running on Google Colab:
# !pip install xact-py

import xact

xact.reset()
```

## 2. Define a Manifold

A 4-dimensional spacetime manifold with abstract indices.

```python
M = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])
```

## 3. Define a Metric

Lorentzian signature, covariant derivative CD.
Automatically creates Riemann, Ricci, Weyl, Einstein, Christoffel.

```python
g = xact.Metric(M, "g", signature=-1, covd="CD")
```

## 4. Canonicalization

Symmetric metric: $g_{ba} - g_{ab} = 0$.

```python
xact.canonicalize("g[-b,-a] - g[-a,-b]")
```

Define a symmetric tensor and canonicalize:

```python
T = xact.Tensor("T", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")
xact.canonicalize("T[-b,-a] - T[-a,-b]")
```

## 5. Contraction

Lower an index with the metric:

```python
V = xact.Tensor("V", ["a"], M)
xact.contract("V[a] * g[-a,-b]")
```

## 6. Riemann Identities

First Bianchi identity:

```python
xact.canonicalize(
    "RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]"
)
```

Pair symmetry — $R_{abcd} = R_{cdab}$:

```python
xact.canonicalize("RiemannCD[-a,-b,-c,-d] - RiemannCD[-c,-d,-a,-b]")
```

## 7. Perturbation Theory

```python
h = xact.Tensor("h", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")
xact.Perturbation(h, g, order=1)
xact.perturb("g[-a,-b]", order=1)
```

## 8. Typed Expression API

String arguments work well but mistakes (wrong index count, wrong manifold) only
surface inside the engine. The `xact.expr` module adds typed index objects and
operator overloading to catch these errors at construction time.

> **Stage 1 note:** engine functions still return `str`. Full typed round-trip is
> planned for Stage 2.

### Index objects

```python
# indices() returns one Idx per registered label, in definition order.
a, b, c, d, e, f = xact.indices(M)

# -a produces a DnIdx (covariant / down)
print(-a)   # "-a"
```

### Tensor handles

```python
# tensor() validates the name and caches slot count.
Riem = xact.tensor("RiemannCD")
gT   = xact.tensor("g")
T_h  = xact.tensor("T")
```

### Building expressions

```python
# Riemann first Bianchi identity — typed vs string:

# String API (original)
xact.canonicalize(
    "RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]"
)

# Typed API — equivalent, validated at construction
expr = Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c]
xact.canonicalize(expr)    # "0"

# Arithmetic: scalar multiplication, negation, subtraction
pair_sym = Riem[-a,-b,-c,-d] - Riem[-c,-d,-a,-b]
xact.canonicalize(pair_sym)   # "0"

two_ricci = 2 * xact.tensor("RicciCD")[-a,-b]
print(two_ricci)   # "2 * RicciCD[-a,-b]"
```

### Validation errors

```python
# Wrong slot count — raised at construction, not inside the engine
try:
    Riem[-a,-b]     # IndexError: RiemannCD has 4 slots, got 2
except IndexError as e:
    print(e)
```

### Tensor and Metric objects support `[]` directly

```python
# g[-a,-b] is shorthand for xact.tensor("g")[-a,-b]
print(g[-a,-b])    # "g[-a,-b]"
xact.contract(g[-a,-b] * xact.tensor("V")[a])   # "V[-b]"
```

## Next Steps

- Full Julia API for more advanced workflows
- Coordinate components, covariant derivative commutation
- Documentation: [sashakile.github.io/sxAct](https://sashakile.github.io/sxAct/)
