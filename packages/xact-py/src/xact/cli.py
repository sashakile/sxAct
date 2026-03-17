"""xact CLI entry point.

Usage::

    xact translate --to julia -e 'DefManifold[M, 4, {a,b,c,d}]'
    xact translate --to json < session.wl
    xact translate --to toml --file session.wl > tests/my_test.toml
"""

from __future__ import annotations

import argparse
import sys


def _cmd_translate(args: argparse.Namespace) -> int:
    from xact.translate.action_recognizer import wl_to_actions
    from xact.translate.renderers import render

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

    print(render(actions, args.to))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="xact",
        description="xact CLI",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    translate = subparsers.add_parser(
        "translate",
        help="Translate Wolfram xAct expressions to JSON, Julia, TOML, or Python",
    )
    translate.add_argument(
        "--to",
        choices=["json", "julia", "toml", "python"],
        default="json",
        help="Output format (default: json)",
    )
    translate.add_argument(
        "-e",
        "--expr",
        default=None,
        metavar="EXPR",
        help="Single Wolfram expression to translate",
    )
    translate.add_argument(
        "--file",
        default=None,
        metavar="PATH",
        help="Path to a .wl file to translate",
    )
    translate.set_defaults(func=_cmd_translate)

    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
