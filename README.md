# xAct.jl — Migration & Implementation

This repository is dedicated to the Julia implementation of the [xAct](http://xact.es/) suite and its Python wrapper. It provides the core tensor algebra engines and validation tooling to ensure mathematical parity with the Wolfram Language "Gold Standard."

## Project Scope

- Primary Goal: Migrate xAct's functionality (xCore, xPerm, xTensor, etc.) to Julia for high-performance, open-source tensor calculus.
- Python Access: Provide an idiomatic Python wrapper (sxact-py) around the Julia core.
- Validation: Use a Dockerized Wolfram Engine (the "Oracle") to prove implementation correctness.

### The Migration Architecture

The project is designed to ensure rigorous mathematical correctness through a multi-tier verification pipeline:

1.  **xAct.jl** (Julia): The native computational engine, located in `src/julia`. This is the primary library for high-performance tensor calculus.
2.  **sxact-py** (Python): A thin wrapper around the Julia core that facilitates interoperability with the broader scientific Python ecosystem and the verification suite.
3.  **The Oracle** (Wolfram): A Dockerized Wolfram Engine running the original xAct code. It acts as the "Ground Truth" for proving implementation correctness.

Detailed documentation on the architecture can be found in the [Architecture Guide](https://sashakile.github.io/sxAct/architecture.html).

---

## The Verification Ecosystem

To maintain modularity, this project is part of a larger verification framework:

1.  **xAct.jl** (This Repo): The core Julia and Python implementations.
2.  **[Elegua](https://github.com/sashakile/elegua)** (External): The orchestration layer and multi-tier task runner used for parity verification.
3.  **[Chacana](https://github.com/sashakile/chacana)** (External): The unified Tensor DSL and formal specification that connects the different implementations.

## License

`xAct.jl` is released under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for the full text.
