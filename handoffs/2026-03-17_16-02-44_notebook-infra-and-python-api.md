---
date: 2026-03-17T16:02:44-03:00
git_commit: 50a0746
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-gic4, sxAct-ynbm, sxAct-d0gf, sxAct-63ps, sxAct-ht3u, sxAct-6w62
status: handoff
---

# Handoff: Notebook Infrastructure, Python Public API, and Onboarding Pipeline

## Context

This session set up the zero-friction onboarding infrastructure for sxAct. The goal is to let new users run a Riemann tensor calculation in under 60 seconds via Google Colab, JupyterLab, or Binder — in both Julia and Python.

We built a three-tier system: (1) Quarto-based notebooks with auto-generated `.ipynb` for Colab, (2) Pluto.jl interactive notebooks for GitHub Pages, (3) a Docker image (per release) for Binder and standalone use. We also created a transparent Python public API (`import xact`) that hides all juliacall internals, and added `typos` + `vale` pre-commit hooks for spell-checking and prose linting.

## Current Status

### Completed
- [x] `typos` and `vale` pre-commit hooks with domain vocabulary (commit `14634eb`)
- [x] Quarto + nbstripout notebook infrastructure — `.qmd` source of truth, `.ipynb` committed without output (sxAct-gic4, CLOSED)
- [x] `scripts/qmd2ipynb.py` — strips YAML frontmatter from quarto convert output (`4363f46`)
- [x] Julia basics notebook: `notebooks/julia/basics.qmd` — all cells verified against Julia engine
- [x] Python basics notebook: `notebooks/python/basics.qmd` — uses new `import xact` API
- [x] Pluto basics notebook: `notebooks/pluto/basics.jl` — reactive demo
- [x] `just lab` command for local JupyterLab (`99d3e43`)
- [x] Python public API: `packages/xact-py/src/xact/api.py` — Manifold, Metric, Tensor, Perturbation, canonicalize, contract, simplify, perturb, etc. (sxAct-ynbm, CLOSED)
- [x] 18 unit tests for Python API: `tests/unit/test_xact_api.py` — all passing
- [x] README, getting-started.md, api-python.md updated with new Python API examples
- [x] Pre-commit hooks: quarto-sync, nbstripout, typos, vale (13 hooks total, all passing)

### Not Yet Done
- [ ] Test notebooks in Google Colab (Julia + Python runtimes) (sxAct-d0gf)
- [ ] Add "Open in Colab" badges to README (sxAct-d0gf)
- [ ] Test Pluto notebook locally + PlutoStaticHTML export (sxAct-63ps)
- [ ] Verify GitHub Pages deployment includes rendered Pluto notebooks (sxAct-63ps)
- [ ] Dockerfile + CI workflow for GHCR image on release (sxAct-ht3u)
- [ ] Binder badge and `.binder/Dockerfile` (sxAct-ht3u)
- [ ] Research: type-safe Julia expression API (sxAct-6w62)

## Critical Files

> These are the MOST IMPORTANT files to understand for continuation

1. `packages/xact-py/src/xact/api.py` — The new Python public API (~250 lines). All user-facing classes and functions.
2. `packages/xact-py/src/xact/__init__.py` — Re-exports from api.py. This is what `import xact` provides.
3. `notebooks/julia/basics.qmd` — Julia notebook source (Quarto format). Verified against engine.
4. `notebooks/python/basics.qmd` — Python notebook source. Uses `import xact` API.
5. `notebooks/pluto/basics.jl` — Pluto reactive notebook. Not yet tested with PlutoStaticHTML.
6. `scripts/qmd2ipynb.py` — Post-processor for `quarto convert` (strips YAML frontmatter).
7. `.pre-commit-config.yaml:40-56` — Quarto sync + nbstripout hooks.
8. `docs/make.jl:19-38` — PlutoStaticHTML integration (not yet tested in CI).
9. `docs/Project.toml` — Added Pluto + PlutoStaticHTML deps (not yet resolved in CI).

## Recent Changes

> Files created/modified in this session (8 commits, `14634eb..50a0746`)

**New files:**
- `packages/xact-py/src/xact/api.py` — Python public API
- `tests/unit/test_xact_api.py` — 18 unit tests
- `notebooks/julia/basics.qmd` + `basics.ipynb` — Julia Quarto notebook
- `notebooks/python/basics.qmd` + `basics.ipynb` — Python Quarto notebook
- `notebooks/pluto/basics.jl` — Pluto interactive notebook
- `scripts/qmd2ipynb.py` — Quarto→ipynb post-processor
- `.vale.ini` — Vale prose linter config
- `.vale/styles/config/vocabularies/sxAct/accept.txt` — Domain vocabulary
- `_typos.toml` — Typos spell-checker config

**Modified files:**
- `.pre-commit-config.yaml` — Added typos, vale, quarto-sync, nbstripout hooks; excluded notebooks/ from julia-format
- `.gitignore` — Added `.vale/styles/*/` (keep config/)
- `pyproject.toml` — Added nbstripout, jupyterlab to dev deps; moved dev deps to `[dependency-groups]`
- `docs/make.jl` — Added PlutoStaticHTML export + "Notebooks" nav section
- `docs/Project.toml` — Added Pluto, PlutoStaticHTML deps
- `.github/workflows/docs.yml` — Trigger on `notebooks/pluto/**` changes
- `justfile` — Added `lab` command
- `README.md` — Added Python quick start + "Try It" section
- `docs/src/getting-started.md` — Added Python quick start
- `docs/src/api-python.md` — Rewrote section 2 with new API

**Relocated:**
- `notebooks/test_python_wolfram.py` → `research/test_python_wolfram.py`
- `notebooks/test_xact.wls` → `research/test_xact.wls`

## Key Learnings

1. **`quarto convert` dumps YAML frontmatter as a markdown cell** — it doesn't strip it. We wrote `scripts/qmd2ipynb.py` to post-process. The pre-commit hook runs this instead of raw `quarto convert`.

2. **juliacall `PyList` doesn't auto-convert to Julia `Vector`** — you need `jl.seval("collect")(list)`. The public API wraps this in `_to_jl_vec()` so users never see it.

3. **Julia `!` functions are `_b` suffix in juliacall** — `def_manifold!` → `xAct.def_manifold_b`. The public API wraps this completely.

4. **`def_perturbation!` requires tensor pre-registration** — you must call `def_tensor!` for the perturbation tensor first, then `def_perturbation!` to link it to the background. The `Perturbation` class documents this.

5. **Binder is unreliable for Julia** — 2GB RAM limit causes timeout during precompilation. Strategy: pre-build Docker image on CI (per release), push to GHCR, point Binder at pre-built image.

6. **Google Colab has native Julia support since March 2025** — select Julia from runtime menu. But kernel is 1.10 LTS, not 1.12.

7. **`end-of-file-fixer` and `quarto convert` cycle** — quarto generates `.ipynb` without trailing newline, the fixer adds it, next run quarto regenerates without it. Fixed by having `qmd2ipynb.py` ensure trailing newline.

8. **Pluto notebooks on Colab don't work** — the kernel proxy approach is unreliable (blank pages). Pluto is for local use and static export only.

## Open Questions

- [ ] Will PlutoStaticHTML work in the docs CI? (Pluto + PlutoStaticHTML added to docs/Project.toml but not tested)
- [ ] Should the Python `Metric` class auto-call `reset()` or require explicit reset?
- [ ] How should the Python API handle errors? Currently juliacall.JuliaError leaks through — should wrap in Python exceptions.
- [ ] `sxAct-ht3u` description still says "Jupytext sources" — should update to "Quarto sources"

## Next Steps

> Prioritized actions for next session

1. **Test Colab notebooks** (sxAct-d0gf) [Priority: HIGH]
   - Open `notebooks/julia/basics.ipynb` in Google Colab with Julia runtime
   - Open `notebooks/python/basics.ipynb` in Google Colab with Python runtime
   - Add "Open in Colab" badges to README
   - Note: Colab Julia is 1.10 LTS, our Project.toml says `julia = "1.12"` — may need separate Colab compat

2. **Test Pluto + PlutoStaticHTML** (sxAct-63ps) [Priority: HIGH]
   - Run `notebooks/pluto/basics.jl` locally with `Pluto.run()`
   - Test `PlutoStaticHTML.notebook_to_html()` on the notebook
   - Verify the docs CI builds with the new Pluto deps

3. **Docker image + Binder** (sxAct-ht3u) [Priority: MEDIUM]
   - Write `Dockerfile` based on `julia:1.12`
   - Add `.github/workflows/release-container.yml`
   - Add `.binder/Dockerfile` pointing at GHCR image
   - Test with `docker build` + `docker run`

4. **Research: type-safe Julia expressions** (sxAct-6w62) [Priority: LOW]
   - Survey TensorOperations.jl, ITensors.jl, Symbolics.jl for expression API patterns
   - Write design doc with proposed type hierarchy

## Ticket Summary

| Ticket | Status | Description |
|--------|--------|-------------|
| sxAct-gic4 | CLOSED | Quarto + nbstripout infra |
| sxAct-ynbm | CLOSED | Python public API |
| sxAct-d0gf | OPEN | Colab notebook testing + badges |
| sxAct-63ps | IN_PROGRESS | Pluto notebooks + GitHub Pages |
| sxAct-ht3u | OPEN (blocked) | Docker image + Binder |
| sxAct-6w62 | OPEN | Research: typed Julia expressions |
| sxAct-ead.1 | OPEN (blocked) | Parent: Zero-Friction Onboarding |

## References

- [Discourse: mybinder.org broken for Julia](https://discourse.julialang.org/t/mybinder-org-broken-for-julia-repos/108743)
- [Discourse: Julia in Colab](https://discourse.julialang.org/t/julia-in-colab/126600)
- [JuliaPluto/static-export-template](https://github.com/JuliaPluto/static-export-template)
- [Quarto convert docs](https://quarto.org/docs/tools/jupyter-lab.html)
- Plan: `plans/2026-03-11-multi-term-symmetry-engine.md` (Invar pipeline — all phases complete)
