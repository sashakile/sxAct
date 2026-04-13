#!/usr/bin/env python3
"""Convert .qmd files to .ipynb, stripping YAML frontmatter from the first cell.

quarto convert dumps the YAML frontmatter verbatim into the first markdown
cell. This script post-processes the result to remove it, since the
kernelspec is already set in the notebook metadata by quarto.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

FRONTMATTER_RE = re.compile(r"^---\n.*?^---\n*", re.MULTILINE | re.DOTALL)


def convert(qmd_path: str) -> None:
    path = Path(qmd_path)
    ipynb_path = path.with_suffix(".ipynb")

    # Run quarto convert (via uvx so quarto need not be installed globally)
    result = subprocess.run(
        ["uvx", "--from", "quarto-cli", "quarto", "convert", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)

    # Post-process: strip YAML frontmatter from first markdown cell
    nb = json.loads(ipynb_path.read_text())
    cells = nb.get("cells", [])
    if cells and cells[0].get("cell_type") == "markdown":
        source = "".join(cells[0]["source"])
        cleaned = FRONTMATTER_RE.sub("", source, count=1)
        if cleaned != source:
            cells[0]["source"] = cleaned.splitlines(True)
            # Remove empty first cell if stripping left it blank
            if not "".join(cells[0]["source"]).strip():
                cells.pop(0)

    text = json.dumps(nb, indent=1, ensure_ascii=False) + "\n"
    ipynb_path.write_text(text)

    # Format Python cells so ruff-format won't modify the output on commit.
    subprocess.run(
        ["uv", "run", "ruff", "format", str(ipynb_path)],
        capture_output=True,
    )

    print(f"Converted to {ipynb_path}")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        convert(arg)
