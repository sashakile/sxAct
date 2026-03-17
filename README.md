# xAct.jl

[![Build Status](https://github.com/sashakile/sxAct/actions/workflows/test.yml/badge.svg)](https://github.com/sashakile/sxAct/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://sashakile.github.io/sxAct/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

A high-performance Julia implementation of the [xAct](http://xact.es/) tensor algebra suite for general relativity.

## Quick Start

```julia
using xAct
M = def_manifold!(:M, 4, [:a, :b, :c, :d])
T = def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
ToCanonical("T[-b,-a] - T[-a,-b]")  # returns "0"
```

### Python

```python
from xact.xcore import get_julia

jl = get_julia()
xAct = jl.xAct
jlvec = jl.seval("collect")

xAct.reset_state_b()
xAct.def_manifold_b("M", 4, jlvec(["a", "b", "c", "d"]))
xAct.def_tensor_b("T", jlvec(["-a", "-b"]), "M", symmetry_str="Symmetric[{-a,-b}]")
xAct.ToCanonical("T[-b,-a] - T[-a,-b]")  # returns "0"
```

## Try It

- [Julia notebook](notebooks/julia/basics.ipynb) — open in JupyterLab or Google Colab
- [Python notebook](notebooks/python/basics.ipynb) — open in JupyterLab or Google Colab
- Local: `just lab` to launch JupyterLab

## Components

- **xAct.jl** (Julia): The computational engine — canonicalization, contraction, covariant derivatives, perturbation theory, coordinate components (xCoba), and more.
- **sxact** (Python): Automated parity testing against the Wolfram Engine using TOML test cases and oracle snapshots.
- **[Chacana](https://github.com/sashakile/chacana)** (External): Unified Tensor DSL and formal specification.

## Documentation

Full documentation at [sashakile.github.io/sxAct](https://sashakile.github.io/sxAct/).

## AI Attribution

The majority of this codebase was developed with AI assistance using [Claude Code](https://claude.ai/claude-code), [Gemini](https://gemini.google.com/), and [Amp Code](https://ampcode.com/). All code is human-reviewed and tested against the Wolfram Engine oracle for mathematical correctness. We believe AI-assisted development, when paired with rigorous verification, produces higher-quality scientific software.

## License

`xAct.jl` is copyright (c) 2024-2026 sxAct Contributors and released under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for the full text.
