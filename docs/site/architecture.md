# Architecture

sxAct provides the core Julia and Python implementations of xAct-compatible tensor algebra. It is designed to be the primary computational engine within a broader three-pillar ecosystem.

## Ecosystem Context

- sxAct (This Repo): The native computational engines (XCore.jl, XPerm.jl, XTensor.jl) and their high-level Python API.
- Elegua (External): The orchestration layer that manages multi-tier execution and parity verification.
- Chacana (External): The unified DSL and specification that standardizes communication between the engines.

## Computational Layers

The implementation is organized into four distinct layers:

### 1. Oracle (sxact.oracle)

The oracle is a Dockerized Wolfram Engine running xAct. The `sxact.oracle` module provides an HTTP client to send tensor expressions and receive xAct-normalized results.

### 2. Normalize (sxact.normalize)

Raw xAct output is not always in a canonical form. The `sxact.normalize` pipeline canonicalizes expressions (index renaming, term sorting) so they can be reliably compared.

### 3. Compare (sxact.compare)

The `sxact.compare` module asserts that two expressions are equivalent after normalization, and provides numeric sampling to verify identities that symbolic reduction might miss.

### 4. Implementation (src/julia)

The high-performance core implemented in Julia, representing the primary target of the migration.
