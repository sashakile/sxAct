# ✦ CHACANA

### *A Cross-Language Tensor Calculus DSL*

**Publication Strategy, Paper Structure, and Technical Roadmap**

Research & Strategy Document — March 2026

---

## Executive Summary

Chacana is a cross-language tensor calculus domain-specific language that uses TOML for declarations and a compact string micro-syntax for tensor expressions. Named after the Andean stepped cross—where *chakay* means *to bridge* or *to cross*—the DSL bridges the fragmented ecosystem of tensor computation tools across Python, Julia, Rust, JavaScript, and Go.

This document presents a comprehensive strategy for publishing the Chacana specification as an academic paper, analyzing publication venues, recommending paper structure, proposing a phased publication timeline, and identifying the formalisms and technical additions needed to maximize both academic and practical impact.

**Key recommendation:** Post an arXiv preprint under cs.PL (cross-listed to gr-qc and cs.SC) immediately, then submit a 5-page vision paper to Onward! 2026 or SLE 2027. In parallel, build a minimal proof-of-concept parser in Python to unlock higher-impact venues like Computer Physics Communications (IF 8.24).

---

# Part I: Publication Venue Analysis

## Venue Landscape by Implementation Requirements

The single most important factor shaping the publication strategy is Chacana's current spec-only status. Venues divide sharply into three tiers based on whether they require a working implementation.

### Tier 1 — Viable Now (No Implementation Required)

**SLE "New Ideas/Vision Papers" (5 pages + 1 page bibliography).** This track explicitly welcomes new, unconventional software language engineering research positions and well-defined research ideas at an early stage of investigation. Co-located with STAF; published in ACM Digital Library. Approximately 33% acceptance rate, double-blind review. SLE 2026 is in Rennes, France (July 2–3); the March 6 paper deadline has just passed, so SLE 2027 is the realistic target.

**Onward! Papers (at SPLASH, typically October).** Explicitly states it is more radical, more visionary, and more open than other conferences to ideas that are well-argued but not yet proven. Two-phase review with revision opportunity. Published in ACM Digital Library. Deadlines typically April–May for an October conference.

**Onward! Essays.** Accepts clear and compelling pieces of writing about topics important to the software community, even as short as a single page. Single-blind review.

**GPCE Short Papers (5–6 pages) or Generative Pearl (10–12 pages).** Scope explicitly includes domain-specific languages, language design, and language embedding. Short Papers accept unconventional ideas or new visions without requiring complete results. Co-located with ECOOP/SPLASH. Approximately 30–40% acceptance rate.

**ARRAY Workshop at PLDI.** Covers all aspects of array programming including tensor computation, Einstein notation, and DSL design. Extended abstracts (2 pages) explicitly accommodate work-in-progress.

**Computing in Science & Engineering (IEEE/AIP).** Publishes design and methodology articles for a scientific computing audience. Impact factor approximately 1.8–2.5. Magazine-style, 6–10 pages. Does not require benchmarks or implementations for design/vision pieces.

### Tier 2 — Viable with a Minimal Prototype Parser

**Computer Physics Communications, CP track.** The highest-impact option at IF 8.24 (2024). Software implementation is ideally available, not strictly mandatory, but reviewers will strongly expect it. The CP track publishes algebraic computation and mathematical methods papers. Cadabra, xAct/xPerm, and xTras all published here. Even a single-language proof-of-concept parser (200 lines of Python) would dramatically strengthen a CPC submission.

**ACM Transactions on Mathematical Software (TOMS).** Scope includes symbolic, algebraic, and geometric computing applications. Research papers require evidence of effectiveness and practicality but don't mandate submitted code. A strong formal/theoretical treatment of the DSL semantics could compensate for missing implementation. Review cycle: 6–12 months.

**PADL (Practical Aspects of Declarative Languages).** Co-located with POPL. Extended abstracts (3 pages) are informal and allow early-stage work.

### Tier 3 — Requires Full Working Implementation

| Venue | Key Requirement | Review Time | Notes |
|-------|----------------|-------------|-------|
| JOSS | Feature-complete OSS with tests, docs, CI, 6+ months commits | ~12 weeks | Zero APCs |
| SoftwareX | Software on GitHub | ~9 weeks | IF 2.4, APC ~$500–760 |
| JuliaCon / SciPy Proceedings | Implementation + conference talk | Varies | Community-focused |
| PLDI, POPL, OOPSLA | Substantial impl. + formal semantics or empirical eval. | 4–6 months | Top PL venues |

## arXiv Categories and Cross-Listing Strategy

The recommended arXiv configuration is **cs.PL as primary**, with **gr-qc** and **cs.SC** as cross-lists—two cross-lists, matching arXiv's guidance that it is rarely appropriate to add more than one or two.

- **cs.PL (Programming Languages)** should be primary because Chacana is fundamentally a language design contribution. The closest precedent—Bernardy and Jansson's "Domain-Specific Tensor Languages" (2023)—used cs.PL.
- **gr-qc (General Relativity and Quantum Cosmology)** as cross-list maximizes visibility to the intended user community. NRPyLaTeX and Pytearcat both used gr-qc as primary.
- **cs.SC (Symbolic Computation)** as second cross-list captures the tensor algebra and computer algebra audience. Alternative: cs.MS (Mathematical Software) if the paper emphasizes cross-language software engineering.

An alternative strategy exists if the paper is written primarily for physicists: gr-qc as primary with cs.PL cross-list. Choose based on the paper's actual emphasis.

---

# Part II: Lessons from Landmark Papers

## Structural Patterns in Successful DSL Papers

Analysis of seven landmark papers (Cadabra, xAct/xPerm, xTras, ITensor, Halide, SymPy, opt\_einsum) reveals consistent structural patterns.

**No paper includes a formal BNF grammar in the main text.** Every successful DSL paper in this space presents language design through examples and conceptual description rather than formal specification. The Cadabra paper describes its TeX-like input format inline. ITensor shows Julia code examples. This is a critical lesson: the TOML schema and micro-syntax should be shown through worked examples, not grammar productions.

**Design philosophy sections distinguish the strongest papers.** Cadabra's CPC paper opens with a conceptual argument about why list-based CAS systems are inadequate. ITensor explicitly states "two philosophical principles" early. Halide centers on the separation of algorithm from schedule. Chacana should lead with its core design thesis: that a TOML-based, language-agnostic declaration format can unify the fragmented ecosystem of tensor calculus tools.

**Worked examples from the target domain are universal and mandatory.** Every paper uses progressively complex domain-specific examples as the primary vehicle for demonstrating the language. The most effective papers use a single running example that grows in complexity across sections.

### Paper Length by Venue

| Paper | Pages | Style | Best Model For |
|-------|-------|-------|----------------|
| Cadabra (CPC) | 9 | Concise philosophy + feature demos | Short conference or CPC submission |
| ITensor (SciPost) | 30+ | Progressive interface walkthrough | Comprehensive journal paper |
| Halide (PLDI) | 12 | Formal model + compiler + benchmarks | Top PL venue (requires impl.) |
| SymPy (PeerJ) | 62 | Encyclopedic feature coverage | Mature large-scale software paper |
| opt\_einsum (JOSS) | 3 | Minimal: summary + timing comparison | JOSS format only |

## Framing a Specification Paper Without Implementation

The strongest framing is as a **language design and notation paper**—combining CS rigor with the physics tradition of notation proposals.

**Historical precedent:** Roger Penrose's abstract index notation (1968) is the most successful spec-only contribution in exactly this field. Published as a chapter in the Battelle Rencontres proceedings, it proposed a pure notation with no computational implementation. It became the standard notation in every major GR textbook. Chacana should explicitly position itself in this tradition: a machine-parseable Penrose notation for the 21st century.

**Cautionary note:** No tensor computation tool in the physics computing literature has published a spec before implementation. The mitigation strategy has three elements: frame Chacana as a notation and interchange format; demonstrate that TOML parsing is trivially achievable using standard libraries in all target languages; and build a minimal proof-of-concept parser in at least one language. Even 200 lines of Python would transform the paper from "proposal" to "validated design."

---

# Part III: Recommended Paper Structure

Based on the structural analysis of successful DSL papers, the following outline follows the Cadabra/ITensor model—leading with design philosophy, demonstrating through examples, and deferring formal details to appendices.

### Section 1: Introduction (1–1.5 pages)

Open with the problem: tensor calculus for differential geometry and GR is expressed in a compact mathematical notation that existing computational tools fragment across incompatible, language-locked ecosystems. State the contribution: a language-agnostic specification for declaring tensor expressions that any language can parse. List 3–4 explicit contributions: the TOML-based declaration format, the micro-syntax for tensor expressions, the cross-language parseability property, and the bridging of symbolic and numerical backends.

### Section 2: The Gap Between Notation and Computation (1–1.5 pages)

Develop the Cadabra-style argument about why existing tools fail. Show a concrete example—the same tensor expression as it appears in standard mathematical notation, xAct/Mathematica syntax, Cadabra syntax, SymPy tensor syntax, and Chacana's TOML+micro-syntax. This visual comparison is the paper's most persuasive element.

### Section 3: Design Principles (0.5–1 page)

Explicitly state 3–4 design principles: human-readability matching mathematical convention; language-agnostic parseability via TOML; separation of declaration from expression; extensibility to both symbolic and numerical backends.

### Section 4: The Chacana Specification (3–4 pages)

The core technical section. Present the TOML declaration format through progressively complex examples. Start with a simple metric tensor. Progress to Christoffel symbols with symmetry. Then covariant derivatives. Then the full Einstein field equations. Include a compact summary table of the micro-syntax operators. Place formal BNF grammar in an appendix.

### Section 5: Cross-Language Parseability (1–1.5 pages)

Demonstrate that the same TOML file parses identically in Python, Julia, Rust, JavaScript, and Go using standard TOML libraries. Show 5–10 line code snippets for at least three languages. This section is crucial for the spec-only paper because it provides concrete, verifiable evidence without requiring a custom implementation.

### Section 6: Comparison with Existing Tools (1–1.5 pages)

Structured comparison table showing Chacana vs. xAct, Cadabra, SymPy tensor module, ITensor, einsum, and NRPyLaTeX across dimensions: language support, tensor types supported, symmetry handling, covariant derivatives, readability, extensibility, and backend support.

### Section 7: Discussion and Future Work (0.5–1 page)

Acknowledge the spec-only status directly. Outline the implementation roadmap. Discuss the vision for Chacana as an interchange format between existing tools—not a replacement for xAct or Cadabra, but a common notation layer that could connect them.

### Section 8: Conclusion (0.5 page)

Concise restatement: a machine-parseable notation for tensor calculus that any programming language can read, positioned in the tradition of Penrose's abstract index notation but designed for the computational era.

### Appendices

- Appendix A: Formal micro-syntax grammar (BNF or PEG)
- Appendix B: Complete TOML specification reference
- Appendix C: Extended examples (Schwarzschild metric, linearized gravity, Bianchi identities)

---

# Part IV: Publication Timeline

## Phase 1 — Now (Spec-Only)

- Post to arXiv under cs.PL with gr-qc and cs.SC cross-lists
- Submit a 5-page version to **Onward! 2026** (deadline likely April–May 2026) or prepare for **SLE 2027** New Ideas/Vision track
- Present informally at the Einstein Toolkit Workshop or similar numerical relativity community event for early feedback

## Phase 2 — With Minimal Prototype (3–6 Months)

- Build a proof-of-concept parser in Python (~200–500 lines)
- Submit a full 10–12 page paper to **GPCE** (Generative Pearl track) or an expanded version to **Computing in Science & Engineering**
- Consider the **ARRAY Workshop** at PLDI for a focused tensor notation audience

## Phase 3 — With Working Implementation (6–12 Months)

- Submit to **Computer Physics Communications** (CP track, IF 8.24) for maximum physics community impact
- Simultaneously submit to **JOSS** (zero APCs, fast review, strong community recognition)
- For the most prestigious CS venue, consider a full **SLE Research Paper** (12 pages) with implementation results

---

# Part V: Formalisms and Additions for Maximum Impact

The following seven additions are ordered from most to least impactful for strengthening both the paper and the DSL itself.

## 1. Static Type System for Index Well-Formedness

*Impact:* **Transformative.** This is the single highest-impact addition. No existing tensor calculus tool for GR—not xAct, Cadabra, or SymPy—provides static, pre-execution validation of index consistency.

Chacana's TOML declarations already contain enough information to check this before any computation runs. Since every index is declared with its type, manifold, and variance, a parser can verify at parse time that every expression is well-formed: contracted pairs have one upper and one lower index of the same type, free indices appear exactly once per term, all terms in a sum have identical free index structure, derivative indices are compatible with the declared connection, and symmetry declarations are consistent.

**What to formalize:** Define typing judgments for Chacana expressions. An expression E is well-typed in context Γ (the TOML declarations) if it satisfies the above constraints. Present this semi-formally using inference rules. This transforms the paper from "a new notation" to "a notation with a novel type system"—a much stronger contribution for PL venues.

## 2. Formal Denotational Semantics for the Micro-Syntax

*Impact:* **High.** Adding even a lightweight formal semantics dramatically strengthens the paper for CS venues.

Define the denotation function ⟦·⟧ that maps each syntactic construct to its mathematical meaning: ⟦T{^a \_b}⟧ denotes an element of V ⊗ V\* where V is the tangent space of the declared manifold; ⟦T{^a \_b} \* S{^b \_c}⟧ denotes the contraction with the trace over the b slot; ⟦T{^a \_b ;c}⟧ denotes the covariant derivative using the declared connection. A half-page of inference rules with explanation is sufficient.

## 3. Rule Verification Framework

*Impact:* **High.** The current spec's `[rule]` section is powerful but doesn't address how to verify that user-defined rules are correct.

Specify that rules have preconditions (e.g., `riemann_to_weyl` only applies in 4D), that rules preserve index structure (the type system should verify both sides have the same free indices), and that rules form a confluent rewrite system when `auto_apply = true`. Chacana's declared index types and symmetries provide richer structure than existing verification systems have to work with.

## 4. Optimal Contraction Order as a First-Class Concept

*Impact:* **Medium-High.** The current spec has `einsum_opt = "optimal"` buried as a backend detail. Finding the optimal contraction path is an NP-hard problem, and optimizing it can yield 1,000x+ performance improvements.

Add a `[strategy]` or `[contraction]` section in the TOML that lets users specify contraction hints, intermediate tensor declarations, and cost annotations. This bridges the symbolic world (where contraction order is irrelevant) and the numerical world (where it determines whether computation takes seconds or hours). No existing tensor calculus notation captures this distinction.

## 5. Spinor and Form Calculus Support

*Impact:* **Medium.** The current spec hints at spinor support but it is underdeveloped.

Fully specify how Chacana handles 2-spinor calculus (Penrose's spinor formalism), differential forms (exterior algebra), and mixed tensor-spinor objects. Specify how spinor indices interact with tensor indices via the soldering form, how the exterior derivative d and Hodge dual \* are expressed in the micro-syntax, and how form degree is tracked in the type system. Even a 1-page section showing these constructs would signal to the GR community that this DSL is serious about their needs.

## 6. JSON Interchange Schema and AST Specification

*Impact:* **Medium (but easiest to implement).** The TOML format is for humans. For tool interoperability, Chacana also needs a machine interchange format.

Add a section specifying a canonical JSON representation of parsed Chacana expressions as an abstract syntax tree. Formalize this with a JSON Schema (RFC draft-bhutton-json-schema) for both the TOML declarations and the parsed expression AST. This lets existing tools (xAct, Cadabra, SymPy) export Chacana-compatible JSON without adopting TOML, making the cross-language bridge claim concrete and testable.

## 7. Perturbation Theory and Variational Calculus Support

*Impact:* **Medium.** The spec already includes `order = 1` for perturbation tensors. Formalizing how Chacana handles perturbation expansion would make it uniquely valuable.

Add a `[perturbation]` section that declares the background metric, the perturbation parameter ε, and the expansion order. Show how the micro-syntax expresses operations like δg{\_a \_b} = ε \* h{\_a \_b} + ε² \* k{\_a \_b} and how rules automatically expand products to the correct order. This directly addresses a pain point every gravitational wave researcher faces.

## Priority Recommendation

| # | Addition | Impact | Effort | Venues Unlocked |
|---|----------|--------|--------|-----------------|
| 1 | Static index type system | **Transformative** | Medium | SLE, GPCE, OOPSLA |
| 2 | Formal denotational semantics | **High** | Low–Medium | SLE, GPCE, ACM TOMS |
| 3 | Rule verification framework | **High** | Medium | POPL, PLDI (future) |
| 4 | Contraction order optimization | **Medium-High** | Low | CPC, SciPy, ARRAY |
| 5 | Spinor and form calculus | **Medium** | Medium | gr-qc audience, CPC |
| 6 | JSON interchange schema | **Medium** | Low | All (makes claims testable) |
| 7 | Perturbation theory support | **Medium** | Medium | gr-qc audience, CPC |

**If you can only add two things before submitting, choose 1 (the type system) and 2 (formal semantics).** Together, they transform Chacana from "a nice notation" into "a notation with provable correctness guarantees"—the difference between a workshop paper and a full research paper. If time permits a third, add 6 (JSON schema) because it's the easiest to implement and makes the cross-language claim immediately verifiable.

---

# Part VI: Package Name Availability

The name "Chacana" is available across all major package registries:

| Registry | Status | Import Syntax | Nearest Conflict |
|----------|--------|---------------|------------------|
| PyPI | Available | `from chacana import load` | chaco (2D plotting) |
| crates.io | Available | `use chacana::Spec;` | None |
| npm | Available | `import { load } from "chacana"` | chacha (crypto) |
| JuliaHub | Available | `using Chacana` | None |
| GitHub | Available | `github.com/*/chacana` | ceph/chacra (different) |

CLI usage: `chacana canonicalize schwarzschild.toml`

---

✦ *End of Document*
