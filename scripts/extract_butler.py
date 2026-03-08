#!/usr/bin/env python3
"""Extract xPerm tests from ButlerExamples.nb (Mathematica 5.2 plain-text format).

Reads resources/xAct/Documentation/English/ButlerExamples.nb, regex-extracts
Input/Output pairs, groups by section, and emits TOML files under
tests/xperm/butler_examples/ matching the schema of existing tests/xperm/*.toml.

Usage:
    uv run python scripts/extract_butler.py [--dry-run]
"""

import re
import sys
from pathlib import Path

NOTEBOOK = Path("resources/xAct/Documentation/English/ButlerExamples.nb")
OUTPUT_DIR = Path("tests/xperm/butler_examples")

# Patterns whose Input content should be skipped entirely
SKIP_INPUT_PATTERNS = [
    r"<<\s*xAct",
    r"\$PrePrint",
    r"\$xPermRules",
    r"NameRules\[",
    r"PrintSchreier\[",
    r"(?:^|[^a-zA-Z])%(?:[^a-zA-Z%]|$)",  # bare % reference (previous output)
    r"xPermVerbose",
    r"//\s*ColumnForm",
    r"//\s*TableForm",
]

# Output that contains only these display forms should be skipped
SKIP_OUTPUT_STARTS = ("InterpretationBox", "TagBox")

# ─────────────────────────────────────────────────────────────────────────────
# WL expression extraction
# ─────────────────────────────────────────────────────────────────────────────

# Match \(content\) in the file — the file has literal backslash + paren
# r'\\\(' in Python raw string = chars \, \, \ , ( = 4 chars
# as regex: \\ (match literal \) + \( (match literal () = matches \(
WL_TOKEN_RE = re.compile(r"\\\((.+?)\\\)", re.DOTALL)


def extract_wl_content(boxdata_inner: str) -> str | None:
    """
    Extract WL expression(s) from the inner content of BoxData[...].

    Two forms:
      Single:  \\(expr\\)
      Multi:   {\\(\\(stmt;\\)\\), "\\n", \\(\\(stmt;\\)\\)}
    """
    s = boxdata_inner.strip()

    if s.startswith("{"):
        # Multi-statement cell: each statement is a \\(...\\) token
        parts = extract_all_wl_tokens(s)
        if not parts:
            return None
        # Each part may be double-wrapped \\(stmt;\\) → strip inner wrap
        stmts = [strip_double_wrap(p) for p in parts]
        return "; ".join(s for s in stmts if s)
    else:
        # Single expression: strip outer \\(...\\)
        parts = extract_all_wl_tokens(s)
        if not parts:
            return None
        return strip_double_wrap(parts[0])


def extract_all_wl_tokens(text: str) -> list[str]:
    """
    Find all top-level \\(content\\) tokens in text.
    Returns list of content strings (without the \\( \\) delimiters).
    Uses depth counting to handle nested \\(...\\).
    """
    results = []
    i = 0
    n = len(text)
    while i < n - 1:
        if text[i] == "\\" and text[i + 1] == "(":
            # Find matching \) counting depth
            depth = 1
            j = i + 2
            while j < n - 1 and depth > 0:
                if text[j] == "\\" and text[j + 1] == "(":
                    depth += 1
                    j += 2
                elif text[j] == "\\" and text[j + 1] == ")":
                    depth -= 1
                    if depth == 0:
                        results.append(text[i + 2 : j])
                    j += 2
                else:
                    j += 1
            i = j
        else:
            i += 1
    return results


def strip_double_wrap(expr: str) -> str:
    """If expr is wrapped in \\(...\\), strip one level of wrapping."""
    expr = expr.strip()
    tokens = extract_all_wl_tokens(expr)
    # If the entire expr is a single \\(...\\) wrapper, return the inner content
    if len(tokens) == 1 and expr.startswith("\\(") and expr.endswith("\\)"):
        return tokens[0].strip()
    return expr


def normalize_expr(expr: str) -> str:
    """Normalize whitespace in a WL expression."""
    # Collapse runs of whitespace (including newlines) to single space
    expr = re.sub(r"[ \t]*\n[ \t]*", " ", expr)
    expr = re.sub(r"[ \t]+", " ", expr)
    return expr.strip()


# ─────────────────────────────────────────────────────────────────────────────
# Filtering
# ─────────────────────────────────────────────────────────────────────────────


def should_skip_input(expr: str) -> bool:
    return any(re.search(p, expr) for p in SKIP_INPUT_PATTERNS)


def is_complex_output(boxdata_inner: str) -> bool:
    """True if the output is a display form (InterpretationBox, TagBox, etc.)."""
    s = boxdata_inner.strip()
    return s.startswith(SKIP_OUTPUT_STARTS)


def is_assignment(expr: str) -> bool:
    """True if expr contains at least one assignment (var = ...)."""
    for stmt in re.split(r";\s*", expr):
        stmt = stmt.strip()
        if re.match(r"^[a-zA-Z$][a-zA-Z0-9$]*\s*=(?!=)", stmt):
            return True
    return False


# ─────────────────────────────────────────────────────────────────────────────
# Notebook parsing
# ─────────────────────────────────────────────────────────────────────────────

# Section header
SECTION_RE = re.compile(r'Cell\["(Example[^"]+?)", "Section"\]')


def find_cg_blocks(text: str) -> list[tuple[int, int]]:
    """
    Find all Cell[CellGroupData[{...}]] block boundaries.
    Returns list of (start, end) character positions.
    Uses bracket counting with string-literal awareness.
    """
    pattern = re.compile(r"Cell\[CellGroupData\[")
    blocks = []
    i = 0
    while True:
        m = pattern.search(text, i)
        if not m:
            break
        # The opening [ is the last [ in "CellGroupData["
        # We need to find the matching ] for "Cell["
        # The "Cell[" opens at m.start() + 4 (the [ after "Cell")
        cell_bracket_pos = m.start() + 4  # pos of '[' in "Cell["
        end = find_matching_bracket(text, cell_bracket_pos)
        if end == -1:
            i = m.end()
            continue
        blocks.append((m.start(), end + 1))
        i = end + 1
    return blocks


def find_matching_bracket(text: str, open_pos: int) -> int:
    """
    Find the matching ']' for the '[' at open_pos.
    Handles string literals and escaped characters.
    Returns the position of ']', or -1 if not found.
    """
    assert text[open_pos] == "[", f"Expected '[' at {open_pos}, got {text[open_pos]!r}"
    depth = 0
    i = open_pos
    in_string = False
    while i < len(text):
        c = text[i]
        if in_string:
            if c == "\\" and i + 1 < len(text) and text[i + 1] in ('"', "\\"):
                i += 2
                continue
            if c == '"':
                in_string = False
        else:
            if c == '"':
                in_string = True
            elif c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def extract_cells_from_block(block: str) -> list[tuple[str, str]]:
    """
    Parse a CellGroupData block into individual cells.
    Returns list of (cell_type, boxdata_content) pairs.
    cell_type is "Input", "Output", "Print", or "complex" (for non-WL output).

    Uses bracket counting to find each Cell[BoxData[...]] boundary without
    regex spanning issues.
    """
    cells = []
    i = 0
    # n = len(block)  # unused
    # Find each Cell[BoxData[
    while True:
        start = block.find("Cell[BoxData[", i)
        if start == -1:
            break
        # Find the [ at position start+4 ("Cell[")
        cell_open = start + 4  # position of '[' in 'Cell['
        cell_end = find_matching_bracket(block, cell_open)
        if cell_end == -1:
            i = start + 1
            continue

        cell_content = block[start : cell_end + 1]

        # Extract the cell type from INSIDE the Cell[...] block.
        # Structure: Cell[BoxData[...], "Type"] or Cell[BoxData[...], ..., "Type"]
        # The cell type is the last string argument before the closing ']'.
        type_match = re.search(r',\s*"(Input|Output|Print)"\s*\]\s*$', cell_content)
        if not type_match:
            i = cell_end + 1
            continue

        cell_type = type_match.group(1)

        # Extract BoxData content (between the inner [])
        # "Cell[BoxData[<CONTENT>]]" → find the [ after "BoxData"
        bd_pos = cell_content.find("Cell[BoxData[") + len("Cell[BoxData")
        bd_open = bd_pos  # position of '[' in 'BoxData['
        bd_end = find_matching_bracket(cell_content, bd_open)
        if bd_end == -1:
            i = cell_end + 1
            continue

        boxdata_content = cell_content[bd_open + 1 : bd_end]

        cells.append((cell_type, boxdata_content))
        i = cell_end + 1

    return cells


def extract_test_pair_from_block(block: str) -> tuple[str, str] | None:
    """
    Try to extract a (input_wl, output_wl) test pair from a CellGroupData block.
    Returns None if the block doesn't have a clean, testable pair.
    """
    cells = extract_cells_from_block(block)

    input_cells = [(ct, bd) for ct, bd in cells if ct == "Input"]
    output_cells = [(ct, bd) for ct, bd in cells if ct == "Output"]

    # Skip if any output is a complex display form
    for ct, bd in output_cells:
        if bd.strip().startswith(SKIP_OUTPUT_STARTS):
            return None

    # We want exactly 1 Input and 1 Output
    if len(input_cells) != 1 or len(output_cells) != 1:
        return None

    input_bd = input_cells[0][1]
    output_bd = output_cells[0][1]

    input_wl = extract_wl_content(input_bd)
    output_wl = extract_wl_content(output_bd)

    if input_wl is None or output_wl is None:
        return None

    input_wl = normalize_expr(input_wl)
    output_wl = normalize_expr(output_wl)

    if not input_wl or not output_wl:
        return None
    if should_skip_input(input_wl):
        return None

    return (input_wl, output_wl)


def find_all_input_cells(text: str, skip_ranges: list[tuple[int, int]]) -> list[str]:
    """
    Find all Cell[BoxData[...], "Input"] cells in text that are NOT inside
    any of the skip_ranges. Returns list of WL expressions.
    Uses bracket counting for correct extraction.
    """
    results = []
    i = 0
    n = len(text)
    while True:
        start = text.find("Cell[BoxData[", i)
        if start == -1:
            break

        # Skip if inside a CellGroupData range
        if any(s <= start < e for s, e in skip_ranges):
            i = start + 1
            continue

        cell_open = start + 4  # '[' in 'Cell['
        if cell_open >= n or text[cell_open] != "[":
            i = start + 1
            continue
        cell_end = find_matching_bracket(text, cell_open)
        if cell_end == -1:
            i = start + 1
            continue

        # Check cell type by searching inside the cell content
        cell_content = text[start : cell_end + 1]
        type_match = re.search(r',\s*"(Input|Output|Print)"\s*\]\s*$', cell_content)
        if not type_match or type_match.group(1) != "Input":
            i = cell_end + 1
            continue
        bd_pos = len("Cell[BoxData")
        bd_end_inner = find_matching_bracket(cell_content, bd_pos)
        if bd_end_inner == -1:
            i = cell_end + 1
            continue

        boxdata_content = cell_content[bd_pos + 1 : bd_end_inner]
        wl = extract_wl_content(boxdata_content)
        if wl is None:
            i = cell_end + 1
            continue
        wl = normalize_expr(wl)
        if wl and not should_skip_input(wl) and is_assignment(wl):
            results.append(wl)

        i = cell_end + 1

    return results


def parse_section(section_text: str) -> tuple[list[str], list[tuple[str, str]]]:
    """
    Parse a section's text into (setup_stmts, test_pairs).

    setup_stmts: list of WL assignment strings (var = expr;)
    test_pairs:  list of (input_wl, output_wl)
    """
    # Find all CellGroupData blocks in this section
    cg_blocks = find_cg_blocks(section_text)

    # Collect test pairs from CellGroupData blocks; track only test-pair ranges
    test_pairs = []
    test_pair_ranges = []  # only CG blocks that are actual test pairs
    # all_cg_ranges unused
    for start, end in cg_blocks:
        block = section_text[start:end]
        pair = extract_test_pair_from_block(block)
        if pair is not None:
            test_pairs.append(pair)
            test_pair_ranges.append((start, end))

    # Find standalone Input cells that are NOT inside any test-pair CG block.
    # We still exclude cells that are inside OTHER (non-test) CG blocks that
    # are themselves inside a test-pair CG block — but since test pairs are
    # small (just Input+Output), there are no such nested blocks.
    # We DO include cells that are inside the outer section CG wrapper.
    setup = find_all_input_cells(section_text, test_pair_ranges)

    return setup, test_pairs


def parse_notebook(text: str) -> list[dict]:
    """
    Parse the notebook into sections with setup and test pairs.
    Returns list of {name, setup, tests}.
    """
    section_matches = list(SECTION_RE.finditer(text))
    if not section_matches:
        return []

    sections = []
    for i, m in enumerate(section_matches):
        name = m.group(1)
        start = m.start()
        end = (
            section_matches[i + 1].start()
            if i + 1 < len(section_matches)
            else len(text)
        )
        section_text = text[start:end]
        setup, tests = parse_section(section_text)
        sections.append({"name": name, "setup": setup, "tests": tests})

    return sections


# ─────────────────────────────────────────────────────────────────────────────
# TOML generation
# ─────────────────────────────────────────────────────────────────────────────


def section_to_slug(name: str) -> str:
    slug = name.lower()
    slug = re.sub(r"[^a-z0-9]+", "_", slug)
    return slug.strip("_")


def test_id_from_input(input_wl: str, idx: int) -> str:
    m = re.match(r"^([A-Z][a-zA-Z]+)\[", input_wl)
    func = m.group(1).lower() if m else "eval"
    return f"{func}_{idx:02d}"


def toml_string(s: str) -> str:
    """Encode s as a TOML double-quoted string."""
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    return f'"{s}"'


def generate_toml(
    section_name: str, setup: list[str], tests: list[tuple[str, str]]
) -> str:
    slug = section_to_slug(section_name)
    file_id = f"xperm/butler_examples/{slug}"

    lines = [
        f"# xperm/butler_examples/{slug}.toml",
        f"# Auto-extracted from ButlerExamples.nb — {section_name}",
        "# Generated by scripts/extract_butler.py",
        "",
        "[meta]",
        f'id              = "{file_id}"',
        f'description     = "xPerm butler examples: {section_name}"',
        'tags            = ["xperm", "butler", "layer:1"]',
        "layer           = 1",
        "oracle_is_axiom = true",
        "",
    ]

    # Emit each setup assignment as an Evaluate block
    seen_vars = set()
    for setup_expr in setup:
        stmts = [s.strip() for s in re.split(r";\s*", setup_expr) if s.strip()]
        for stmt in stmts:
            vm = re.match(r"^([a-zA-Z$][a-zA-Z0-9$]*)\s*=", stmt)
            if not vm:
                continue
            var = vm.group(1)
            if var in seen_vars:
                continue  # deduplicate
            seen_vars.add(var)
            lines += [
                "[[setup]]",
                'action   = "Evaluate"',
                f'store_as = "{var}"',
                "[setup.args]",
                f"expression = {toml_string(stmt + ';')}",
                "",
            ]

    # Emit each test pair
    seen_ids = set()
    for idx, (input_wl, output_wl) in enumerate(tests, 1):
        test_id = test_id_from_input(input_wl, idx)
        # deduplicate IDs
        base_id = test_id
        counter = 2
        while test_id in seen_ids:
            test_id = f"{base_id}_{counter}"
            counter += 1
        seen_ids.add(test_id)

        description = f"{input_wl[:70]}"

        lines += [
            "# ---------------------------------------------------------------------------",
            "",
            "[[tests]]",
            f'id          = "{test_id}"',
            f"description = {toml_string(description)}",
            "",
            "[[tests.operations]]",
            'action   = "Evaluate"',
            'store_as = "result"',
            "[tests.operations.args]",
            f"expression = {toml_string(input_wl)}",
            "",
            "[[tests.operations]]",
            'action = "Assert"',
            "[tests.operations.args]",
            f"condition = {toml_string(f'$result === {output_wl}')}",
            f"message   = {toml_string(f'Expected: {output_wl}')}",
            "",
            "[tests.expected]",
            "is_zero         = false",
            "comparison_tier = 1",
            "",
        ]

    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────


def main():
    dry_run = "--dry-run" in sys.argv
    verbose = "--verbose" in sys.argv

    if not NOTEBOOK.exists():
        print(f"ERROR: {NOTEBOOK} not found", file=sys.stderr)
        sys.exit(1)

    text = NOTEBOOK.read_text(encoding="latin-1")
    sections = parse_notebook(text)

    total_tests = 0
    files_written = []

    for sec in sections:
        name = sec["name"]
        setup = sec["setup"]
        tests = sec["tests"]

        if not tests:
            if verbose:
                print(f"  skip  {name!r}: no extractable tests")
            continue

        slug = section_to_slug(name)
        toml_content = generate_toml(name, setup, tests)
        outfile = OUTPUT_DIR / f"{slug}.toml"

        if dry_run:
            print(f"\n{'=' * 60}")
            print(f"  {outfile}")
            print(f"  setup={len(setup)}, tests={len(tests)}")
            if verbose:
                print(toml_content[:1200])
        else:
            OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
            outfile.write_text(toml_content)
            print(f"  wrote {outfile}  ({len(setup)} setup, {len(tests)} tests)")
            files_written.append(outfile)

        total_tests += len(tests)

    files_count = len([s for s in sections if s["tests"]])
    print(f"\nTotal: {files_count} files, {total_tests} tests")


if __name__ == "__main__":
    main()
