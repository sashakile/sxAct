# Naming and product map

!!! info "LLM TL;DR"
    - `XAct.jl` is the repository
    - `XAct.jl` / `XAct` is the Julia package and module
    - `xact-py` is the Python package name
    - `xact` is the Python import
    - `sxact` is the verification framework

This page explains the names used across the project. Use it when you need to understand which name belongs to the repository, the Julia engine, the Python wrapper, or the verification tooling.

## Name map

| Name | Kind | Meaning |
| :--- | :--- | :--- |
| `XAct.jl` | Repository | The Git repository that contains the whole project |
| `XAct.jl` | Julia package | The Julia package users add to their environment |
| `XAct` | Julia module | The module imported with `using XAct` |
| `xact-py` | Python package | The distribution published to PyPI |
| `xact` | Python import | The Python module imported in user code |
| `sxact` | Verification framework | The Python tooling for TOML tests, oracle snapshots, and normalization |

## Use the right name in the right place

| If you are doing… | Use… |
| :--- | :--- |
| Cloning the repo | `XAct.jl` |
| Importing the Julia module | `using XAct` |
| Installing from PyPI | `pip install xact-py` |
| Importing in Python | `import xact` |
| Talking about the verification stack | `sxact` |

## Related pages

- [Home](index.md)
- [Installation](installation.md)
- [Getting Started](getting-started.md)
- [Python API](api-python.md)
