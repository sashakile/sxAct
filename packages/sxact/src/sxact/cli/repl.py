"""xact-test repl — interactive Wolfram-style REPL.

Users type Wolfram xAct expressions, which are parsed, translated to Julia,
and optionally evaluated live via the Julia adapter.

Usage::

    xact-test repl              # Live mode (requires Julia)
    xact-test repl --no-eval    # Translate-only mode (no Julia)
"""

from __future__ import annotations

import argparse
import sys
from typing import Any

from xact.translate.action_recognizer import ActionDict, recognize
from xact.translate.renderers import render, to_julia
from xact.translate.wl_parser import WLParseError, parse_session

# ---------------------------------------------------------------------------
# REPL commands
# ---------------------------------------------------------------------------

_HELP_TEXT = """\
sxAct REPL — type Wolfram xAct expressions

Commands:
  :help              Show this help
  :quit / :q         Exit REPL
  :reset             Clear all definitions (calls reset_state!())
  :history           Show expression history
  :to julia          Dump session as Julia code
  :to toml           Dump session as TOML test file
  :to python         Dump session as Python adapter calls
  :to json           Dump session as JSON

Syntax:
  DefManifold[M, 4, {a, b, c, d}]
  DefMetric[-1, g[-a,-b], CD]
  ToCanonical[T[-a,-b] - T[-b,-a]]
  expr // Simplify          (postfix pipe)
  result = ToCanonical[...]  (assignment)
  result == 0               (assertion)
  (* comment *)             (skipped)
"""


class REPLSession:
    """Manages REPL state: history, action accumulation, optional Julia eval."""

    def __init__(self, *, no_eval: bool = False) -> None:
        self.no_eval = no_eval
        self.history: list[str] = []
        self.actions: list[ActionDict] = []
        self.counter = 0
        self._adapter: Any = None
        self._ctx: Any = None

    def initialize(self) -> None:
        """Initialize Julia runtime (unless --no-eval)."""
        if self.no_eval:
            return
        try:
            from sxact.adapter.julia_stub import JuliaAdapter

            self._adapter = JuliaAdapter()
            self._ctx = self._adapter.initialize()
        except Exception as exc:
            print(f"Warning: Julia initialization failed: {exc}", file=sys.stderr)
            print("Falling back to translate-only mode.", file=sys.stderr)
            self.no_eval = True

    def teardown(self) -> None:
        if self._adapter and self._ctx:
            try:
                self._adapter.teardown(self._ctx)
            except Exception:
                pass

    def execute_line(self, line: str) -> list[str]:
        """Parse and execute a line, returning output lines."""
        output: list[str] = []
        try:
            trees = parse_session(line)
        except WLParseError as exc:
            output.append(f"  ParseError: {exc}")
            return output

        for tree in trees:
            self.counter += 1
            action_dict = recognize(tree)
            self.actions.append(action_dict)
            self.history.append(line)

            if self.no_eval:
                # Show translated Julia
                julia_line = to_julia([action_dict])
                output.append(f"  → {julia_line}")
            else:
                result = self._eval_action(action_dict)
                if result is not None:
                    output.append(f"Out[{self.counter}]= {result}")

        return output

    def _eval_action(self, ad: ActionDict) -> str | None:
        """Execute an action dict against the Julia adapter."""
        if self._adapter is None:
            return None

        action: str = str(ad["action"])
        args = ad.get("args", {})

        try:
            result = self._adapter.execute(self._ctx, action, args)
            if result.status == "ok":
                if result.repr and action not in (
                    "DefManifold",
                    "DefMetric",
                    "DefTensor",
                    "DefBasis",
                    "DefChart",
                    "DefPerturbation",
                ):
                    return str(result.repr)
                # For definitions, show a summary
                if action == "DefManifold":
                    return f"  Manifold {args.get('name')} (dim={args.get('dimension')})"
                if action == "DefMetric":
                    return f"  Metric {args.get('metric')} with covd {args.get('covd')}"
                if action == "DefTensor":
                    sym = args.get("symmetry", "")
                    sym_str = f" ({sym})" if sym else ""
                    return f"  Tensor {args.get('name')}{sym_str}"
                return None
            else:
                return f"  Error: {result.error}"
        except Exception as exc:
            return f"  Error: {exc}"

    def reset(self) -> str:
        """Reset Julia state and clear session."""
        self.actions.clear()
        self.history.clear()
        self.counter = 0
        if self._adapter and self._ctx:
            try:
                self._adapter.teardown(self._ctx)
                self._ctx = self._adapter.initialize()
                return "  State reset."
            except Exception as exc:
                return f"  Reset failed: {exc}"
        return "  Session cleared."

    def export_session(self, fmt: str) -> str:
        """Export accumulated session in the given format."""
        if not self.actions:
            return "  (no actions in session)"
        return render(self.actions, fmt)


# ---------------------------------------------------------------------------
# REPL loop
# ---------------------------------------------------------------------------


def _run_repl(session: REPLSession) -> int:
    """Main REPL loop."""
    mode = "translate-only" if session.no_eval else "Julia backend"
    print(f"sxAct REPL ({mode}) — type Wolfram xAct expressions")
    print("Type :help for commands, :quit to exit")
    print()

    while True:
        try:
            prompt = f"In[{session.counter + 1}]: "
            line = input(prompt)
        except (EOFError, KeyboardInterrupt):
            print()
            break

        line = line.strip()
        if not line:
            continue

        # REPL commands
        if line.startswith(":"):
            cmd = line.lower()
            if cmd in (":quit", ":q"):
                break
            if cmd == ":help":
                print(_HELP_TEXT)
                continue
            if cmd == ":reset":
                print(session.reset())
                continue
            if cmd == ":history":
                if not session.history:
                    print("  (no history)")
                else:
                    for i, h in enumerate(session.history, 1):
                        print(f"  In[{i}]: {h}")
                continue
            if cmd.startswith(":to "):
                fmt = cmd[4:].strip()
                if fmt not in ("julia", "toml", "python", "json"):
                    print(f"  Unknown format: {fmt!r}. Use julia, toml, python, or json.")
                    continue
                print(session.export_session(fmt))
                continue
            print(f"  Unknown command: {line!r}. Type :help for commands.")
            continue

        # Parse and execute
        output = session.execute_line(line)
        for out_line in output:
            print(out_line)

    session.teardown()
    return 0


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def _cmd_repl(args: argparse.Namespace) -> int:
    session = REPLSession(no_eval=args.no_eval)

    if not args.no_eval:
        print("Loading Julia runtime...", end=" ", flush=True)
    session.initialize()
    if not args.no_eval and not session.no_eval:
        print("done")

    return _run_repl(session)
