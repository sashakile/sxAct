## ADDED Requirements

### Requirement: Unified Expression AST
The expression parser SHALL represent both flat tensor products and CovD application using a single AST type system (`TensorFactor` and `CovDFactor` as `FactorNode` union).

#### Scenario: Flat tensor product parsed correctly
- **WHEN** `_parse_expression("S[-a,-b] V[-c]")` is called
- **THEN** it returns a `TermAST` with two `TensorFactor` nodes: `S` with indices `["-a","-b"]` and `V` with index `["-c"]`

#### Scenario: CovD application parsed correctly
- **WHEN** `_parse_expression("CD[-a][V[-b]]")` is called
- **THEN** it returns a `TermAST` with one `CovDFactor` node: covd_name `:CD`, deriv_index `"-a"`, operand containing a `TensorFactor` for `V["-b"]`

#### Scenario: Nested CovD chain parsed correctly
- **WHEN** `_parse_expression("CD[-a][CD[-b][T[-c]]]")` is called
- **THEN** it returns a `TermAST` with one `CovDFactor` whose operand contains another `CovDFactor`, whose operand contains `TensorFactor` for `T["-c"]`

#### Scenario: Mixed CovD and product parsed correctly
- **WHEN** `_parse_expression("CD[-a][V[-b]] S[-c,-d]")` is called
- **THEN** it returns a `TermAST` with two factors: one `CovDFactor` for the derivative and one `TensorFactor` for `S`

#### Scenario: Inner coefficient factored out
- **WHEN** `_parse_expression("CD[-a][3 V[-b]]")` is called
- **THEN** it returns a `TermAST` with coefficient `3` and one `CovDFactor` whose operand contains `TensorFactor` for `V["-b"]` (coefficient lives at the outer level)

#### Scenario: Non-CovD double bracket is a parse error
- **WHEN** `_parse_expression("NotACovD[-a][V[-b]]")` is called and `NotACovD` is not a registered CovD
- **THEN** a parse error is raised

#### Scenario: CovD of sum is rejected
- **WHEN** `_parse_expression("CD[-a][V[-b] + W[-b]]")` is called
- **THEN** an error is raised suggesting the user expand by linearity

### Requirement: CovD Round-Trip Through ToCanonical
`ToCanonical` SHALL preserve CovD bracket structure and recursively canonicalize the inner operand without dropping the derivative application.

#### Scenario: CovD expression survives ToCanonical
- **WHEN** `ToCanonical("CD[-a][S[-c,-b]]")` is called with `S` symmetric
- **THEN** the result is `"CD[-a][S[-b,-c]]"` (inner operand canonicalized, CovD preserved)

#### Scenario: ToCanonical is idempotent on CovD expressions
- **WHEN** `ToCanonical(ToCanonical("CD[-a][V[-b]]"))` is called
- **THEN** the result equals `ToCanonical("CD[-a][V[-b]]")`

#### Scenario: Mixed CovD+product canonicalized correctly
- **WHEN** `ToCanonical("CD[-a][V[-b]] S[-d,-c]")` is called with `S` symmetric
- **THEN** the result is `"CD[-a][V[-b]] S[-c,-d]"` (plain factors canonicalized, CovD preserved)

### Requirement: CovD Detection Guard
When the parser encounters CovD bracket syntax and the unified AST is not yet active, it SHALL raise an explicit error rather than silently dropping the operand.

#### Scenario: Error on CovD in ToCanonical
- **WHEN** `ToCanonical("CD[-a][V[-b]]")` is called and CovDFactor support is not enabled
- **THEN** an error is raised mentioning "CovD bracket syntax" and suggesting `SortCovDs`

#### Scenario: SortCovDs still works during transition
- **WHEN** `SortCovDs("CD[-b][CD[-a][V[-c]]]", :CD)` is called during any phase
- **THEN** it returns the correctly sorted result (unaffected by parser changes)

### Requirement: Single Parser Backend
After unification, `SortCovDs` and `CommuteCovDs` SHALL use `_parse_expression` (the unified parser) instead of the separate `_extract_covd_chain` / `_split_expression_terms` string-based parser. The `_preprocess_covd_reductions` string-regex rewrites SHALL be migrated to AST-level identity application.

#### Scenario: SortCovDs uses unified parser
- **WHEN** `SortCovDs` is called after Phase C
- **THEN** it parses the expression via `_parse_expression` into `TermAST` with `CovDFactor` nodes, not via `_extract_covd_chain`

#### Scenario: String-based CovD parsers removed
- **WHEN** Phase C is complete
- **THEN** `_extract_covd_chain`, `_split_expression_terms`, and the regex-based `_reduce_metric_compatibility` / `_reduce_second_bianchi` no longer exist in `Canonical.jl`
