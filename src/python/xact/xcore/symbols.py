"""Symbol naming, dagger/link characters, registry, and mutable refs."""

from __future__ import annotations

from typing import Any

from . import _runtime


# ---------------------------------------------------------------------------
# Internal helpers (used by this module and upvalues.py)
# ---------------------------------------------------------------------------


def _sym(s: str | Any) -> Any:
    """Convert a Python str to a Julia Symbol (pass-through for Julia values)."""
    if isinstance(s, str):
        return _runtime.get_julia().Symbol(s)
    return s


def _str(s: Any) -> str:
    """Convert a Julia Symbol (or any Julia value) to a Python str."""
    return str(s)


def _sym_list(symbols: list[str | Any]) -> Any:
    """Convert a Python list of str/Symbols to a Julia Vector{Symbol}."""
    jl = _runtime.get_julia()
    return (
        jl.seval("Symbol[]")
        if not symbols
        else jl.seval(
            "Symbol[" + ", ".join(f"Symbol({str(s)!r})" for s in symbols) + "]"
        )
    )


def _str_list(vec: Any) -> list[str]:
    """Convert a Julia Vector{Symbol} to a Python list of str."""
    return [str(s) for s in vec]


# ---------------------------------------------------------------------------
# 4. Symbol naming and dagger / link characters
# ---------------------------------------------------------------------------


def symbol_join(*symbols: Any) -> str:
    """Concatenate *symbols* into a single symbol name.

    Julia: ``SymbolJoin(symbols...)``
    """
    return _str(_runtime.get_xcore().SymbolJoin(*symbols))


def no_pattern(expr: Any) -> Any:
    """Identity shim (Julia has no Pattern wrappers).

    Julia: ``NoPattern(expr)``
    """
    return expr


# --- DaggerCharacter ---


def dagger_character() -> str:
    """Return the current dagger character string.

    Julia: ``DaggerCharacter[]``
    """
    return str(_runtime.get_julia().seval("Main.XCore.DaggerCharacter[]"))


def set_dagger_character(value: str) -> None:
    """Set the dagger character string.

    Julia: ``DaggerCharacter[] = value``
    """
    _runtime.get_julia().seval(f"Main.XCore.DaggerCharacter[] = {value!r}")


def has_dagger_character_q(s: str | Any) -> bool:
    """Return True if the symbol name contains the dagger character.

    Julia: ``HasDaggerCharacterQ(s)``
    """
    return bool(_runtime.get_xcore().HasDaggerCharacterQ(_sym(s)))


def make_dagger_symbol(s: str | Any) -> str:
    """Toggle the dagger character on a symbol (add if absent, remove if present).

    Julia: ``MakeDaggerSymbol(s)``
    """
    return _str(_runtime.get_xcore().MakeDaggerSymbol(_sym(s)))


# --- LinkCharacter ---


def link_character() -> str:
    """Return the current link character string.

    Julia: ``LinkCharacter[]``
    """
    return str(_runtime.get_julia().seval("Main.XCore.LinkCharacter[]"))


def set_link_character(value: str) -> None:
    """Set the link character string.

    Julia: ``LinkCharacter[] = value``
    """
    _runtime.get_julia().seval(f"Main.XCore.LinkCharacter[] = {value!r}")


def link_symbols(symbols: list[str | Any]) -> str:
    """Join *symbols* with the link character into a single symbol name.

    Julia: ``LinkSymbols(symbols)``
    """
    return _str(_runtime.get_xcore().LinkSymbols(_sym_list(symbols)))


def unlink_symbol(s: str | Any) -> list[str]:
    """Split a symbol at each link character; return parts as a list of str.

    Julia: ``UnlinkSymbol(s)``
    """
    return _str_list(_runtime.get_xcore().UnlinkSymbol(_sym(s)))


# ---------------------------------------------------------------------------
# 10. Symbol registry and validation
# ---------------------------------------------------------------------------


def validate_symbol(name: str | Any) -> None:
    """Raise if *name* collides with an already-registered or Base symbol.

    Julia: ``ValidateSymbol(name)``

    Raises:
        JuliaError: if the symbol name is already in use.
    """
    _runtime.get_xcore().ValidateSymbol(_sym(name))


def find_symbols(expr: Any) -> list[str]:
    """Recursively collect all Symbols in *expr*; return as list of str.

    Julia: ``FindSymbols(expr)``
    """
    return _str_list(_runtime.get_xcore().FindSymbols(expr))


def register_symbol(name: str | Any, package: str) -> None:
    """Register *name* as owned by *package*.

    Julia: ``register_symbol(name, package)``

    Raises:
        JuliaError: if *name* is already registered by a different package.
    """
    _runtime.get_xcore().register_symbol(str(name), package)


# --- Per-package name lists (read-only views) ---


def x_perm_names() -> list[str]:
    """Return a copy of the xPerm symbol name list."""
    return list(_runtime.get_xcore().xPermNames)


def x_tensor_names() -> list[str]:
    """Return a copy of the xTensor symbol name list."""
    return list(_runtime.get_xcore().xTensorNames)


def x_core_names() -> list[str]:
    """Return a copy of the xCore symbol name list."""
    return list(_runtime.get_xcore().xCoreNames)


def x_tableau_names() -> list[str]:
    """Return a copy of the xTableau symbol name list."""
    return list(_runtime.get_xcore().xTableauNames)


def x_coba_names() -> list[str]:
    """Return a copy of the xCoba symbol name list."""
    return list(_runtime.get_xcore().xCobaNames)


def invar_names() -> list[str]:
    """Return a copy of the Invar symbol name list."""
    return list(_runtime.get_xcore().InvarNames)


def harmonics_names() -> list[str]:
    """Return a copy of the Harmonics symbol name list."""
    return list(_runtime.get_xcore().HarmonicsNames)


def x_pert_names() -> list[str]:
    """Return a copy of the xPert symbol name list."""
    return list(_runtime.get_xcore().xPertNames)


def spinors_names() -> list[str]:
    """Return a copy of the Spinors symbol name list."""
    return list(_runtime.get_xcore().SpinorsNames)


def em_names() -> list[str]:
    """Return a copy of the EM symbol name list."""
    return list(_runtime.get_xcore().EMNames)


# --- Mutable string refs ---


def warning_from() -> str:
    """Return the current WarningFrom label."""
    return str(_runtime.get_julia().seval("Main.XCore.WarningFrom[]"))


def set_warning_from(value: str) -> None:
    """Set the WarningFrom label."""
    _runtime.get_julia().seval(f"Main.XCore.WarningFrom[] = {value!r}")


def xact_directory() -> str:
    """Return the xAct installation directory path."""
    return str(_runtime.get_julia().seval("Main.XCore.xActDirectory[]"))


def set_xact_directory(path: str) -> None:
    """Set the xAct installation directory path."""
    _runtime.get_julia().seval(f"Main.XCore.xActDirectory[] = {path!r}")


def xact_doc_directory() -> str:
    """Return the xAct documentation directory path."""
    return str(_runtime.get_julia().seval("Main.XCore.xActDocDirectory[]"))


def set_xact_doc_directory(path: str) -> None:
    """Set the xAct documentation directory path."""
    _runtime.get_julia().seval(f"Main.XCore.xActDocDirectory[] = {path!r}")
