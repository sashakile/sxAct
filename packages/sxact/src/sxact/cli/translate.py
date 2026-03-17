"""xact-test translate subcommand.

Reads Wolfram xAct expressions from stdin, file, or argument, translates
them to action dicts, and outputs in the selected format.

Usage::

    echo 'DefManifold[M, 4, {a,b,c,d}]' | xact-test translate --to julia
    xact-test translate --to toml < session.wl > tests/my_test.toml
    xact-test translate --to json -e 'ToCanonical[T[-a,-b]]'
"""

from __future__ import annotations

import argparse
import sys


def _cmd_translate(args: argparse.Namespace) -> int:
    from xact.translate.action_recognizer import wl_to_actions
    from xact.translate.renderers import render

    # Read input: -e flag, file argument, or stdin
    if args.expr:
        source = args.expr
    elif args.file:
        with open(args.file) as f:
            source = f.read()
    elif not sys.stdin.isatty():
        source = sys.stdin.read()
    else:
        print("Error: provide input via -e, --file, or stdin", file=sys.stderr)
        return 1

    if not source.strip():
        return 0

    try:
        actions = wl_to_actions(source)
    except Exception as exc:
        print(f"Parse error: {exc}", file=sys.stderr)
        return 1

    if not actions:
        return 0

    output = render(actions, args.to)
    print(output)
    return 0
