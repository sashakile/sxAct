# xAct Migration Research: Validation Benchmarks & Scientific Literature

This document synthesizes deep research into the foundational papers, application domains, and open-source repositories associated with the **xAct** Mathematica suite. The goal is to define concrete validation targets for migrating xAct functionality to Julia (`XCore.jl` / `sxAct`), ensuring the open-source port is scientifically robust and performant.

## 0. Terminology & Architecture Reference

To ensure clarity during the migration and validation process, the following terms are defined:

*   **Mono-term Symmetries:** Symmetries that relate a single tensor term to itself with a sign change (e.g., $A_{ab} = -A_{ba}$). These are handled automatically by `ToCanonical`.
*   **Multi-term Symmetries:** Identities involving sums of different index arrangements (e.g., the First Bianchi Identity $R_{abcd} + R_{acdb} + R_{adbc} = 0$). These often require specialized simplification rules and are **not** handled by Butler-Portugal alone.
*   **Tier 1 (AST Normalization):** Canonicalization of the expression's Abstract Syntax Tree (sorting, index renaming).
*   **Tier 2 (Symbolic Oracle):** Verification of $A - B = 0$ using the live Wolfram Engine's `Simplify` or `FullSimplify`.
*   **Tier 3 (Numeric Sampling):** Verification of identities by assigning random, well-conditioned numeric values to tensor components and checking for $0$ within a tolerance.

---

## 1. Core Packages and Foundational Papers

### A. xPerm: Index Canonicalization

*   **Paper:** Martín-García (2008) — *xPerm: fast index canonicalization for tensor computer algebra*
*   **arXiv:** [0803.0862 [cs.SC]](https://arxiv.org/abs/0803.0862)
*   **Journal:** *Comput. Phys. Commun.* 179:597–603
*   **C source:** `http://www.xact.es/xPerm/mathlink/xperm.c` (~2000 lines, well-commented)
*   **Significance:** Implements the Butler-Portugal algorithm as both a Mathematica package and a C subroutine. Proves effectively-polynomial runtime on realistic inputs. The C source is the authoritative implementation reference.
*   **Algorithm:** Maps tensor canonicalization to finding a double-coset representative `D*g*S` in the permutation group. Uses Schreier-Sims to build stabilizer chains (strong generating sets), then `double_coset_rep()` for canonicalization.
*   **Key C functions to port:**
    ```
    schreier_sims()        - builds strong generating set (stabilizer chain)
    schreier_vector()      - orbit computation with traceback
    coset_rep()            - canonical coset representative
    double_coset_rep()     - double coset rep (core of tensor canonicalization)
    canonical_perm_ext()   - full canonicalization with multiple dummy index sets
    ```
*   **Data conventions:** permutations as 1-indexed integer arrays in image notation — matches Julia's 1-indexed arrays.
*   **Validation Target:**
    *   Replicate performance timings: "several dozen indices in hundredths of a second," "one hundred indices in a few seconds."
    *   More critically: replicate the **same canonical forms** (not just timing) on those expressions.
    *   Use SymPy's `tensor_can.py` as cross-check oracle during development (see §3).

### B. xPerm Algorithm: State-of-the-Art Improvement

*   **Paper:** Niehoff (2018) — *Faster Tensor Canonicalization*
*   **arXiv:** [1702.08114](https://arxiv.org/abs/1702.08114)
*   **Journal:** *Comput. Phys. Commun.* 228:287–294
*   **Significance:** The original Butler-Portugal algorithm has O(n!) blowup for fully symmetric or antisymmetric index slots (the most common case in GR). Niehoff provides a modified algorithm handling these in polynomial time. **This is required reading before implementing xPerm.**

### C. Multi-Term Symmetry (Bianchi Identity)

*   **Paper:** Li et al. (2017) — *Riemann Tensor Polynomial Canonicalization by Graph Algebra Extension*
*   **arXiv:** [1701.08487 [cs.SC]](https://arxiv.org/abs/1701.08487)
*   **Venue:** ISSAC 2017
*   **Significance:** Addresses multi-term symmetry (the Bianchi identity) which neither xPerm nor the standard Butler-Portugal handles. Uses graph algebra (indices as vertices, contraction pairs as edges).
*   **Note:** For initial xTensor port, mono-term symmetry (Butler-Portugal) is sufficient; multi-term (Bianchi) can be added later. Consider adopting Cadabra's Young-projector approach for this (see §5).

### D. xTensor: Abstract Tensor Algebra

*   **No dedicated arXiv paper.** See the [xAct website](http://xact.es/) and the NTUA notes (referenced in [1412.4765](https://arxiv.org/abs/1412.4765)).
*   **Key operations:** tensor type declarations, abstract index contraction, covariant derivatives, Lie derivatives, metric raising/lowering, symmetrization/antisymmetrization, commuting covariant derivatives (`SortCovDs`), implicit-to-explicit index expansion.
*   **Covariant derivative commutation:** core identity is `∇_a ∇_b T^{cd} - ∇_b ∇_a T^{cd} = R^c_{eab} T^{ed} - R^d_{eab} T^{ce}`. Requires pattern-matching to substitute the Riemann commutator whenever two covariant derivative slots are exchanged.
*   **Depends on:** xPerm being complete and correct.

### E. xPert: Metric Perturbation Theory

*   **Paper:** Brizuela, Martín-García & Mena Marugán (2009) — *xPert: computer algebra for metric perturbation theory*
*   **arXiv:** [0807.0824 [gr-qc]](https://arxiv.org/abs/0807.0824)
*   **Journal:** *Gen. Rel. Grav.* 41:2415–2431
*   **Significance:** Implements explicit combinatorial formulas for n-th order perturbations of curvature tensors and their gauge changes, layered on xAct's canonicalization.
*   **Hard part:** generating all terms in the n-th order metric perturbation automatically (combinatorial expansion engine).
*   **Validation Target:**
    *   Derive the 1st, 2nd, and 3rd order perturbations of the Einstein equations for a generic metric.
    *   Verify expanded terms match Oracle output via Tier 2/3 comparators.

### F. Invar: Curvature Invariants

*   **Paper:** Martín-García, Yllanes & Portugal (2008) — *The Invar Tensor Package: Differential invariants of Riemann*
*   **arXiv:** [0802.1274](https://arxiv.org/abs/0802.1274) (see also earlier [0704.1756](https://arxiv.org/abs/0704.1756))
*   **Journal:** *Comput. Phys. Commun.* 179:586–590
*   **Significance:** Solves the complete problem of relations among scalar invariants of the Riemann tensor through 12 metric derivatives. Uses a database of >600,000 relations.
*   **Validation benchmarks:** Known values of Riemann invariants on Schwarzschild/Kerr:
    *   Kretschner scalar: $R_{abcd} R^{abcd}$
    *   Cubic: $R_{abcd} R^{abce} R_e^{\ d}$
*   **Hard part:** Database generation requires multi-term canonicalization (Bianchi identity) — beyond Butler-Portugal.

### G. xTras: Field Theory Utilities

*   **Paper:** Nutma (2014) — *xTras: a field-theory inspired xAct package for Mathematica*
*   **arXiv:** [1308.3493 [cs.SC]](https://arxiv.org/abs/1308.3493)
*   **Journal:** *Comput. Phys. Commun.* 185:1719–1738
*   **Key capabilities:** generate all tensor contractions, dimensional-dependent identities, traceless projections, equations of motion for Riemann monomials, Young symmetrizers and projectors, solving linear tensorial equation systems.
*   **Validation Target:**
    *   Derive equations of motion for: $f(R)$ gravity, Einstein-Gauss-Bonnet, Horndeski theory.
    *   Use standard Lagrangians from the paper. Assert equivalence with `xTras` via Oracle.
    *   **Note on Boundary Terms:** For initial validation, assume vanishing boundary terms during IBP (total derivatives discarded), consistent with standard `xTras` behavior.

### H. xPand: Cosmological Perturbations

*   **Paper:** Pitrou, Roy & Umeh (2013) — *xPand: An algorithm for perturbing homogeneous cosmologies*
*   **arXiv:** [1302.6174](https://arxiv.org/abs/1302.6174)
*   **Journal:** JCAP
*   **Significance:** Extends xPert for cosmology; 1+3 scalar/vector/tensor decompositions of perturbations around any homogeneous background to arbitrary order.
*   **Timing benchmarks from the paper:** Riemann to 2nd order in <2 min; Weyl to 2nd order in <13 min. A Julia port must match these.
*   **Validation Target:** Reproduce standard linear perturbation equations for FLRW background.

### I. Spinors: Spinor Calculus

*   **Paper:** García-Parrado Gómez-Lobo & Martín-García (2012) — *Spinors: A Mathematica package for doing spinor calculus in GR*
*   **arXiv:** [1110.2662 [gr-qc]](https://arxiv.org/abs/1110.2662)
*   **Journal:** *Comput. Phys. Commun.* 183:2214–2225
*   **Scope:** Penrose 2-component spinor calculus, 4D Lorentzian only. Newman-Penrose and GHP equations derived from scratch.
*   **Depends on:** xTensor being feature-complete.

### J. FieldsX: Fermions, Gauge Fields, BRST

*   **Paper:** Fröb (2020) — *FieldsX: extension to include fermions, gauge fields and BRST cohomology*
*   **arXiv:** [2008.12422](https://arxiv.org/abs/2008.12422)
*   **GitHub:** [mfroeb/FieldsX](https://github.com/mfroeb/FieldsX)
*   **Scope:** Grassmann-odd algebra, graded commutators, BV-BRST differentials, curved-space gamma matrices, Fierz identities. Demonstrated on N=1 SYM.
*   **Lowest priority** for initial migration.

---

## 2. Validation Benchmarks from Papers Using xAct

These are published computations with explicit results that validate a Julia port:

| Paper | arXiv | What was computed | Packages | Notes |
|-------|-------|-------------------|----------|-------|
| Brizuela, Martín-García, Tiglio (2009) | [0903.1134](https://arxiv.org/abs/0903.1134) | Complete 2nd-order Zerilli/Regge-Wheeler eqs, metric reconstruction, radiated energy for Schwarzschild | xTensor, xPert | Has companion Mathematica notebook — highest-priority benchmark |
| Brizuela, Martín-García, Mena Marugán (2007) | [gr-qc/0607025](https://arxiv.org/abs/gr-qc/0607025) | 2nd+ order perturbations of spherical spacetimes | xTensor, xPert | |
| Agullo et al. (2020) | [2006.03397](https://arxiv.org/abs/2006.03397) | Full gauge-invariant linear perturbations of Bianchi I in Hamiltonian form | xTensor, xPert | |
| Pitrou, Roy, Umeh — xPand (2013) | [1302.6174](https://arxiv.org/abs/1302.6174) | FLRW perturbations to arbitrary order; timing benchmarks | xTensor, xPert | <2 min for Ricci 2nd order |
| García-Parrado, Martín-García (2012) | [1110.2662](https://arxiv.org/abs/1110.2662) | Full Newman-Penrose and GHP equations | xTensor, Spinors | |
| Blanchet et al. (2008) | [0802.1249](https://arxiv.org/abs/0802.1249) | 3rd post-Newtonian gravitational wave polarizations | xTensor | |

---

## 3. Real-World Repositories for Test Data

1.  **[xAct-contrib](https://github.com/xAct-contrib)** — Official community hub. Repositories like `xTras` and `Spinors` contain Mathematica test files (`.nb` or `.wl`). Convert these into `sxAct` TOML test schemas.
2.  **[wevbarker/HiGGS](https://github.com/wevbarker/HiGGS)** & **[wevbarker/PSALTer](https://github.com/wevbarker/PSALTer)** — Hamiltonian constraints and particle spectrums of tensor Lagrangians. Highly complex expressions; excellent stress tests for the Tier 1 AST normalizer and Tier 3 numeric sampler.
3.  **[shubham-93/xAct-Mathematica-template-notebooks](https://github.com/shubham-93/xAct-Mathematica-template-notebooks-for-physics)** — Standard initialization templates; use to set up automated test contexts in `sxAct`.

---

## 4. Migration and Validation Strategy

### Phase 1: xPerm (Butler-Portugal) — CRITICAL PATH

*   **Goal:** Native Julia implementation of `xperm.c`.
*   **Approach options:**
    1. **Bootstrap:** `ccall` wrapper to the existing `xperm.c` — immediate correctness.
    2. **Native:** Port C logic to pure `XPerm.jl` — required for performance and long-term maintainability.
*   **Reference implementations in order of readability:**
    1. SymPy [`tensor_can.py`](https://github.com/sympy/sympy/blob/master/sympy/combinatorics/tensor_can.py) — pure Python, same algorithm, most readable
    2. `xperm.c` — authoritative C source at `http://www.xact.es/xPerm/mathlink/xperm.c`
*   **SymPy paper:** [arXiv:1302.1219](https://arxiv.org/abs/1302.1219) documents the Python implementation.
*   **Validation:** Compare Julia canonical forms against Wolfram xPerm Oracle on a diverse suite of tensors before declaring correctness.
*   **Group theory support:** `AbstractAlgebra.jl` has `Perm{T}` and orbit computation. For full BSGS with arbitrary groups: `Oscar.jl` (via GAP) is the best Julia option, though it adds FFI overhead. For the xPerm inner loop, native Julia Schreier-Sims (~500 lines) is preferable.

### Phase 2: xTensor Core

*   **Goal:** Port abstract index notation, metric raising/lowering, covariant derivatives.
*   **Validation:** Use `sxAct` Oracle to compare canonicalized forms of randomly generated Riemann contractions. Key benchmark: the Schwarzschild 2nd-order perturbation notebook from [0903.1134](https://arxiv.org/abs/0903.1134).

### Phase 3: xTras — Functional Derivatives

*   **Goal:** Lagrangian variation and integration by parts.
*   **Validation:** Standard Lagrangians (Einstein-Hilbert, Maxwell, Gauss-Bonnet) from the Nutma (2014) paper.

### Phase 4: xPert — Perturbation Expansions

*   **Goal:** Automatic metric perturbation expansions.
*   **Validation:** Reproduce the perturbation tables from Brizuela et al. (2009). Use Tier 3 Numeric Sampler for high-order symbolic perturbations (circumvents Mathematica's slow symbolic simplifications for massive expressions).

---

## 5. Open-Source Alternatives to xAct

### Cadabra2 (C++/Python — closest feature equivalent)

*   **Papers:** [hep-th/0701238](https://arxiv.org/abs/hep-th/0701238) (2007), [JOSS 2018 3(32):1118](https://joss.theoj.org/papers/10.21105/joss.01118)
*   **GitHub:** [kpeeters/cadabra2](https://github.com/kpeeters/cadabra2)
*   **Application papers:** [2210.00005](https://arxiv.org/abs/2210.00005), [2210.00007](https://arxiv.org/abs/2210.00007)
*   **Key distinction:** Cadabra uses **Young-projector-based multi-term symmetry algorithms** (handles Bianchi identity natively). xPerm handles only mono-term permutation symmetries.
*   **Recommendation:** For multi-term canonicalization (Bianchi identity), adopt Cadabra's Young-projector approach rather than extending Butler-Portugal.

### SageManifolds (Python/SageMath)

*   **Papers:** [1412.4765](https://arxiv.org/abs/1412.4765), [1804.07346](https://arxiv.org/abs/1804.07346)
*   Does NOT use Butler-Portugal; works at coordinate-component level. Useful for specific-metric validation benchmarks.

### SymPy Tensor Module

*   [Tensor docs](https://docs.sympy.org/latest/modules/tensor/tensor.html), [canonicalization docs](https://docs.sympy.org/latest/modules/combinatorics/tensor_can.html)
*   Pure-Python Butler-Portugal. Slower than `xperm.c` but same algorithm. **Primary reference for Julia port.**

---

## 6. Comprehensive Survey

*   **MacCallum (2018)** — *Computer algebra in gravity research.* *Living Reviews in Relativity* 21:6.
*   [Springer](https://link.springer.com/article/10.1007/s41114-018-0015-6) / [PMC open access](https://pmc.ncbi.nlm.nih.gov/articles/PMC6105178/)
*   Compares all tensor CAS systems (xAct, Cadabra, SageManifolds, GRTensor, DifferentialGeometry, Atlas 2, Maxima ctensor/itensor). Key finding: "There is no best package." Essential reading for architecture decisions.

---

## 7. Migration Difficulty Map

| Module | Difficulty | Depends on | Key references | Estimated effort |
|--------|-----------|------------|----------------|------------------|
| xCore | Medium | — | xAct website | Partially done |
| xPerm | High | xCore | 0803.0862, 1702.08114, tensor_can.py | 4–8 weeks |
| xTensor | Very High | xPerm | xAct notebooks, 0903.1134 | 3–6 months |
| xCoba | Medium | xTensor | 1412.4765 (NTUA notes) | 4–8 weeks |
| xPert | Medium-High | xTensor | 0807.0824 | 6–10 weeks |
| Harmonics | Medium | xCore | No paper found | 2–4 weeks |
| xTras | Low-Medium | xTensor | 1308.3493 | 4–6 weeks |
| Spinors | High | xTensor | 1110.2662 | 2–3 months |
| Invar | Very High | xTensor | 0802.1274 | 3–4 months |
| FieldsX | Very High | xTensor | 2008.12422 | 3+ months |

**Recommended sequence:** xPerm → xTensor → xCoba/xPert in parallel → xTras → Invar/Spinors.
