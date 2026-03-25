"""Output renderers — convert action dicts to JSON, Julia, TOML, or Python.

Each renderer takes a list of action dicts (from :func:`wl_to_actions`) and
returns a formatted string in the target format.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any

ActionDict = dict[str, Any]

_DEFINITION_ACTIONS = frozenset(
    {
        "DefManifold",
        "DefMetric",
        "DefTensor",
        "DefBasis",
        "DefChart",
        "DefPerturbation",
    }
)


# ---------------------------------------------------------------------------
# JSON renderer
# ---------------------------------------------------------------------------


def to_json(actions: list[ActionDict]) -> str:
    """Render action dicts as pretty-printed JSON."""
    if len(actions) == 1:
        return json.dumps(actions[0], indent=2)
    return json.dumps(actions, indent=2)


# ---------------------------------------------------------------------------
# Julia renderer
# ---------------------------------------------------------------------------


def to_julia(actions: list[ActionDict]) -> str:
    """Render action dicts as Julia XTensor calls."""
    lines: list[str] = []
    for ad in actions:
        line = _action_to_julia(ad)
        store_as = ad.get("store_as")
        if store_as:
            line = f"{store_as} = {line}"
        lines.append(line)
    return "\n".join(lines)


def _action_to_julia(ad: ActionDict) -> str:
    action = ad["action"]
    args = ad.get("args", {})

    if action == "DefManifold":
        name = args.get("name", "")
        dim = args.get("dimension", 0)
        indices = args.get("indices", [])
        idx_jl = "[" + ", ".join(f":{i}" for i in indices) + "]"
        return f"xAct.def_manifold!(:{name}, {dim}, {idx_jl})"

    if action == "DefMetric":
        signdet = args.get("signdet", 0)
        metric = args.get("metric", "")
        covd = args.get("covd", "")
        return f'xAct.def_metric!({signdet}, "{metric}", :{covd})'

    if action == "DefTensor":
        name = args.get("name", "")
        indices = args.get("indices", [])
        manifold = args.get("manifold", "")
        sym = args.get("symmetry", "")
        idx_jl = "[" + ", ".join(f'"{i}"' for i in indices) + "]"
        parts = [f":{name}", idx_jl, f":{manifold}"]
        if sym:
            parts.append(f'symmetry_str="{sym}"')
        return f"xAct.def_tensor!({', '.join(parts)})"

    if action == "DefBasis":
        name = args.get("name", "")
        vbundle = args.get("vbundle", "")
        cnumbers = args.get("cnumbers", [])
        cn_jl = "[" + ", ".join(str(c) for c in cnumbers) + "]"
        return f"xAct.def_basis!(:{name}, :{vbundle}, {cn_jl})"

    if action == "DefChart":
        name = args.get("name", "")
        manifold = args.get("manifold", "")
        cnumbers = args.get("cnumbers", [])
        scalars = args.get("scalars", [])
        cn_jl = "[" + ", ".join(str(c) for c in cnumbers) + "]"
        sc_jl = "[" + ", ".join(f":{s}" for s in scalars) + "]"
        return f"xAct.def_chart!(:{name}, :{manifold}, {cn_jl}, {sc_jl})"

    if action == "DefPerturbation":
        name = args.get("name", "")
        metric = args.get("metric", "")
        param = args.get("parameter", "")
        return f"xAct.def_perturbation!(:{name}, :{metric}, :{param})"

    if action == "ToCanonical":
        return f'xAct.ToCanonical("{_jl_esc(args.get("expression", ""))}")'

    if action == "Simplify":
        expr = _jl_esc(args.get("expression", ""))
        return f'xAct.Simplify("{expr}")'

    if action == "Contract":
        return f'xAct.Contract("{_jl_esc(args.get("expression", ""))}")'

    if action == "CommuteCovDs":
        expr = _jl_esc(args.get("expression", ""))
        covd = args.get("covd", "")
        indices = args.get("indices", "")
        return f'xAct.CommuteCovDs("{expr}", :{covd}, {indices})'

    if action == "SortCovDs":
        expr = _jl_esc(args.get("expression", ""))
        covd = args.get("covd", "")
        return f'xAct.SortCovDs("{expr}", :{covd})'

    if action == "Perturb":
        expr = _jl_esc(args.get("expression", ""))
        order = args.get("order", 1)
        return f'xAct.perturb("{expr}", {order})'

    if action == "PerturbCurvature":
        key = args.get("key")
        if key:
            covd = args.get("covd", "")
            return f"xAct.perturb_curvature(:{key}, :{covd})"
        expr = _jl_esc(args.get("expression", ""))
        order = args.get("order", 1)
        return f'xAct.perturb_curvature("{expr}", {order})'

    if action == "PerturbationOrder":
        return f'xAct.PerturbationOrder("{_jl_esc(args.get("expression", ""))}")'

    if action == "PerturbationAtOrder":
        expr = args.get("expression", "")
        order = args.get("order", 1)
        return f"xAct.PerturbationAtOrder(:{expr}, {order})"

    if action == "CheckMetricConsistency":
        metric = args.get("metric", "")
        return f"xAct.check_metric_consistency(:{metric})"

    if action == "IntegrateByParts":
        expr = _jl_esc(args.get("expression", ""))
        covd = args.get("covd", "")
        return f'xAct.IBP("{expr}", :{covd})'

    if action == "TotalDerivativeQ":
        expr = _jl_esc(args.get("expression", ""))
        covd = args.get("covd", "")
        return f'xAct.TotalDerivativeQ("{expr}", :{covd})'

    if action == "VarD":
        var = _jl_esc(args.get("variable", ""))
        expr = _jl_esc(args.get("expression", ""))
        return f'xAct.VarD("{var}", "{expr}")'

    if action == "SetBasisChange":
        b1 = args.get("basis1", "")
        b2 = args.get("basis2", "")
        mat = args.get("matrix", "")
        return f"xAct.SetBasisChange(:{b1}, :{b2}, {mat})"

    if action == "ChangeBasis":
        expr = _jl_esc(args.get("expression", ""))
        basis = args.get("target_basis", "")
        return f'xAct.ChangeBasis("{expr}", :{basis})'

    if action == "GetJacobian":
        b1 = args.get("basis1", "")
        b2 = args.get("basis2", "")
        return f"xAct.GetJacobian(:{b1}, :{b2})"

    if action == "BasisChangeQ":
        b1 = args.get("basis1", "")
        b2 = args.get("basis2", "")
        return f"xAct.BasisChangeQ(:{b1}, :{b2})"

    if action == "SetComponents":
        tensor = args.get("tensor", "")
        components = args.get("components", "")
        return f'xAct.SetComponents("{tensor}", {components})'

    if action == "GetComponents":
        tensor = args.get("tensor", "")
        basis = args.get("basis", "")
        return f'xAct.GetComponents("{tensor}", :{basis})'

    if action == "ComponentValue":
        tensor = args.get("tensor", "")
        indices = args.get("indices", [])
        return f'xAct.ComponentValue("{tensor}", {indices})'

    if action == "CTensorQ":
        return f'xAct.CTensorQ("{args.get("tensor", "")}")'

    if action == "ToBasis":
        basis = args.get("basis", "")
        expr = _jl_esc(args.get("expression", ""))
        return f'xAct.ToBasis(:{basis}, "{expr}")'

    if action == "FromBasis":
        basis = args.get("basis", "")
        expr = _jl_esc(args.get("expression", ""))
        return f'xAct.FromBasis(:{basis}, "{expr}")'

    if action == "TraceBasisDummy":
        return f'xAct.TraceBasisDummy("{_jl_esc(args.get("expression", ""))}")'

    if action == "Christoffel":
        covd = args.get("covd", "")
        return f"xAct.Christoffel(:{covd})"

    if action == "Assert":
        return f"@assert {args.get('condition', '')}"

    # Evaluate / fallback
    return f'xAct.eval("{_jl_esc(args.get("expression", ""))}")'


def _jl_esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


# ---------------------------------------------------------------------------
# TOML renderer
# ---------------------------------------------------------------------------


def to_toml(actions: list[ActionDict]) -> str:
    """Render action dicts as a TOML test file."""
    lines: list[str] = []

    # Meta section
    lines.append("[meta]")
    lines.append('id = "translated-session"')
    lines.append('description = "Translated from Wolfram xAct"')
    lines.append('tags = ["translated"]')
    lines.append("layer = 1")
    lines.append("oracle_is_axiom = true")
    lines.append("")

    # Split into setup (definitions) and operations
    setup_actions: list[ActionDict] = []
    op_actions: list[ActionDict] = []
    for ad in actions:
        if ad["action"] in _DEFINITION_ACTIONS:
            setup_actions.append(ad)
        else:
            op_actions.append(ad)

    # Setup section
    for ad in setup_actions:
        lines.extend(_toml_setup_block(ad))
        lines.append("")

    # Tests section — group operations into test blocks
    if op_actions:
        test_groups = _group_test_operations(op_actions)
        for i, group in enumerate(test_groups, 1):
            lines.append("[[tests]]")
            # Derive description from first non-Assert action
            desc_action = next((a for a in group if a["action"] != "Assert"), group[0])
            desc = _toml_test_description(desc_action)
            lines.append(f'id = "test_{i}"')
            lines.append(f'description = "{desc}"')
            lines.append("")
            for ad in group:
                lines.extend(_toml_operation_block(ad))
                lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _toml_setup_block(ad: ActionDict) -> list[str]:
    lines = ["[[setup]]"]
    lines.append(f'action = "{ad["action"]}"')

    store_as = ad.get("store_as")
    args = ad.get("args", {})

    # Derive store_as from name if not explicitly set
    if not store_as:
        store_as = args.get("name", "")
    if store_as:
        lines.append(f'store_as = "{store_as}"')

    lines.append("[setup.args]")
    for key, val in args.items():
        lines.append(_toml_kv(key, val))

    return lines


def _toml_operation_block(ad: ActionDict) -> list[str]:
    lines = ["[[tests.operations]]"]
    lines.append(f'action = "{ad["action"]}"')

    store_as = ad.get("store_as")
    if store_as:
        lines.append(f'store_as = "{store_as}"')

    args = ad.get("args", {})
    if args:
        lines.append("[tests.operations.args]")
        for key, val in args.items():
            lines.append(_toml_kv(key, val))

    return lines


def _toml_kv(key: str, val: Any) -> str:
    if isinstance(val, bool):
        return f"{key} = {'true' if val else 'false'}"
    if isinstance(val, int):
        return f"{key} = {val}"
    if isinstance(val, list):
        items = ", ".join(f'"{v}"' if isinstance(v, str) else str(v) for v in val)
        return f"{key} = [{items}]"
    # String
    return f'{key} = "{val}"'


def _group_test_operations(ops: list[ActionDict]) -> list[list[ActionDict]]:
    """Group operations into test blocks.

    - An Assert following a compute groups with it
    - Assignments start new groups
    - Consecutive unassigned computes each get their own group
    """
    groups: list[list[ActionDict]] = []
    current: list[ActionDict] = []

    for ad in ops:
        if ad["action"] == "Assert" and current:
            current.append(ad)
            groups.append(current)
            current = []
        else:
            if current:
                groups.append(current)
            current = [ad]

    if current:
        groups.append(current)

    return groups


def _toml_test_description(ad: ActionDict) -> str:
    action: str = str(ad["action"])
    args = ad.get("args", {})
    expr = args.get("expression", "")
    if expr:
        short = expr[:50] + ("..." if len(expr) > 50 else "")
        return f"{action}: {short}"
    return action


# ---------------------------------------------------------------------------
# Python renderer
# ---------------------------------------------------------------------------


def to_python(actions: list[ActionDict]) -> str:
    """Render action dicts as Python adapter.execute() calls."""
    lines: list[str] = []
    lines.append("from sxact.adapter.julia_stub import JuliaAdapter")
    lines.append("")
    lines.append("adapter = JuliaAdapter()")
    lines.append("ctx = adapter.initialize()")
    lines.append("")

    for ad in actions:
        action = ad["action"]
        args = ad.get("args", {})
        store_as = ad.get("store_as")
        args_repr = repr(args)

        if store_as:
            lines.append(f'{store_as} = adapter.execute(ctx, "{action}", {args_repr})')
        else:
            lines.append(f'adapter.execute(ctx, "{action}", {args_repr})')

    lines.append("")
    lines.append("adapter.teardown(ctx)")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

_RENDERERS: dict[str, Callable[[list[ActionDict]], str]] = {
    "json": to_json,
    "julia": to_julia,
    "toml": to_toml,
    "python": to_python,
}


def render(actions: list[ActionDict], fmt: str) -> str:
    """Render actions in the specified format ('json', 'julia', 'toml', 'python')."""
    renderer = _RENDERERS.get(fmt)
    if renderer is None:
        raise ValueError(f"Unknown format {fmt!r}. Choose from: {', '.join(_RENDERERS)}")
    return renderer(actions)
