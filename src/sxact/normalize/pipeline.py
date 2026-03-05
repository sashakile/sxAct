"""Normalization pipeline for xAct expression comparison.

The pipeline applies these transformations in order:
1. Whitespace normalization
2. Dummy index canonicalization ($1, $2, ...)
3. Term ordering (lexicographic for sums)
4. Coefficient normalization
"""

import logging
import re
from typing import Callable

logger = logging.getLogger(__name__)


def normalize_whitespace(expr: str) -> str:
    """Normalize whitespace in an expression.

    - Remove spaces around brackets
    - Ensure single space after commas
    - Collapse multiple spaces to single space
    - Normalize spaces around operators
    """
    result = expr.strip()
    result = re.sub(r"\[\s+", "[", result)
    result = re.sub(r"\s+\]", "]", result)
    result = re.sub(r"\s*,\s*", ", ", result)
    result = re.sub(r"\s+", " ", result)
    return result


def canonicalize_indices(expr: str) -> str:
    """Canonicalize dummy indices to $1, $2, etc.

    Indices are renamed in order of first appearance.
    Preserves up/down distinction (- prefix for down).
    Only matches indices inside square brackets.
    """
    bracket_pattern = re.compile(r"\[([^\]]+)\]")
    index_pattern = re.compile(r"(-?)([a-zA-Z])(?=[,\]\s]|$)")
    index_map: dict[str, int] = {}
    counter = 1

    def replace_index(match: re.Match[str]) -> str:
        nonlocal counter
        sign = match.group(1)
        index_name = match.group(2)

        if index_name not in index_map:
            index_map[index_name] = counter
            counter += 1

        canonical_num = index_map[index_name]
        return f"{sign}${canonical_num}"

    def replace_bracket_contents(bracket_match: re.Match[str]) -> str:
        contents = bracket_match.group(1)
        new_contents = index_pattern.sub(replace_index, contents)
        return f"[{new_contents}]"

    return bracket_pattern.sub(replace_bracket_contents, expr)


def order_terms(expr: str) -> str:
    """Order terms in a sum lexicographically.

    Splits on ' + ', sorts terms, rejoins.
    """
    if " + " not in expr:
        return expr

    terms = expr.split(" + ")
    sorted_terms = sorted(terms, key=lambda t: t.lstrip("-").lstrip("0123456789 "))
    return " + ".join(sorted_terms)


def normalize_coefficients(expr: str) -> str:
    """Normalize coefficient representation.

    - 2*x -> 2 x
    - -1*x -> -x
    - 1*x -> x
    """
    result = re.sub(r"\*", " ", expr)
    result = re.sub(r"(?<!\d)-1\s+", "-", result)
    result = re.sub(r"(?<![0-9-])1\s+(?=[a-zA-Z])", "", result)
    result = re.sub(r"\s+", " ", result)
    return result.strip()


def normalize(expr: str) -> str:
    """Apply full normalization pipeline to an expression.

    Pipeline order:
    1. Whitespace normalization
    2. Coefficient normalization
    3. Dummy index canonicalization
    4. Term ordering
    """
    pipeline: list[Callable[[str], str]] = [
        normalize_whitespace,
        normalize_coefficients,
        canonicalize_indices,
        order_terms,
    ]

    result = expr
    for transform in pipeline:
        result = transform(result)

    return result


def ast_normalize(expr: str) -> str:
    """Normalize *expr* using the AST-based pipeline.

    Unlike :func:`normalize`, this function:

    - Handles arbitrarily nested brackets without false negatives
    - Sorts commutative operators (Plus, Times) *before* canonicalizing indices,
      so that structurally equivalent expressions with different dummy index
      names produce identical output (e.g. ``A[a]+B[b]`` and ``B[a]+A[b]``
      both normalize to ``A[$1] + B[$2]``)
    - Uses a strict serializer that matches the legacy output format for
      simple expressions

    This function is the preferred normalizer for Tier 1 comparison.
    The legacy :func:`normalize` is retained for backwards compatibility.

    Args:
        expr: A Wolfram expression string (infix *or* FullForm notation).

    Returns:
        Canonical normalized string.
    """
    from sxact.normalize.ast_parser import parse
    from sxact.normalize.passes import (
        canonicalize_indices as ast_canonicalize_indices,
        flatten_coefficients,
        sort_commutative,
    )
    from sxact.normalize.serializer import serialize

    try:
        tree = parse(expr)
        tree = sort_commutative(tree)
        tree = ast_canonicalize_indices(tree)
        tree = flatten_coefficients(tree)
        return serialize(tree)
    except Exception:
        # Fall back to regex pipeline on parse failure (e.g. infix operators).
        # Log so callers can diagnose when valid FullForm fails to parse.
        logger.warning("ast_normalize: falling back to regex pipeline for %r", expr)
        return normalize(expr)
