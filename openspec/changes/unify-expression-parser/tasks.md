## 1. Phase A — Error guard (eliminates silent data loss)
- [x] 1.1 Add detection in `_parse_monomial`: after parsing `Name[indices]`, if next char is `[`, raise `error("CovD bracket syntax CD[...][...] is not supported by ToCanonical. Use SortCovDs/CommuteCovDs for covariant derivative expressions.")` — done in 567ab18
- [x] 1.2 Add test: `ToCanonical("CD[-a][V[-b]]")` raises error (not silently drops) — done in 567ab18
- [x] 1.3 Add test: `Contract("CD[-a][V[-b]]")` raises error — done in 567ab18
- [x] 1.4 Verify existing CovD tests still pass (`SortCovDs`, `CommuteCovDs` use separate parser)
- [x] 1.5 Verify full XTensor + fuzz test suites pass

## 2. Phase B — Unified AST
- [x] 2.1 Define `TensorFactor` as a rename of `FactorAST`; rename all references
- [x] 2.2 Update `TermAST` to use `Vector{FactorNode}` where `FactorNode = Union{TensorFactor, CovDFactor}`
- [x] 2.3 Define `CovDFactor` type with `covd_name`, `deriv_index`, `operand::Vector{FactorNode}`
- [x] 2.4 Update `_parse_monomial` to recognize `Name[idx][operand]` as CovD when `CovDQ(Name)` is true; reject sums and non-CovD double brackets
- [x] 2.5 Update `_term_key_str` to serialize `CovDFactor` as `"CD[-a][V[-b]]"` format
- [x] 2.6 Update `_serialize` — works via `_term_key_str` (no separate change needed)
- [x] 2.7 Update `_canonicalize_term` to recursively canonicalize the inner operand of `CovDFactor`
- [x] 2.8 Add test: `ToCanonical("CD[-a][S[-c,-b]]")` → `"CD[-a][S[-b,-c]]"` (inner operand canonicalized)
- [x] 2.9 Add test: round-trip `ToCanonical(ToCanonical("CD[-a][V[-b]]"))` is idempotent
- [x] 2.10 Add test: mixed CovD+product `ToCanonical("CD[-a][V[-b]] S[-d,-c]")` → `"CD[-a][V[-b]] S[-c,-d]"`
- [x] 2.11 Add test: CovD of sum `ToCanonical("CD[-a][V[-b] + W[-b]]")` raises error suggesting linearity expansion
- [x] 2.12 Add fuzz tests: random CovD expressions survive ToCanonical round-trip
- [x] 2.13 Verify full XTensor + fuzz test suites pass (zero regressions)

## 3. Phase C — Retire string-based CovD parser
- [ ] 3.1 Rewrite `SortCovDs` to parse via `_parse_expression` (unified AST) instead of `_extract_covd_chain`
- [ ] 3.2 Rewrite `CommuteCovDs` to use unified AST
- [ ] 3.3 Migrate `_preprocess_covd_reductions` (`_reduce_metric_compatibility`, `_reduce_second_bianchi`) from string-regex to AST-level identity application
- [ ] 3.4 Remove `_extract_covd_chain`, `_split_expression_terms`, and string-based helpers
- [ ] 3.5 Verify all SortCovDs/CommuteCovDs tests pass with new parser backend
- [ ] 3.6 Verify full test suite passes
