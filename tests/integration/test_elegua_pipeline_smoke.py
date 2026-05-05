"""End-to-end smoke test for the migrated Elegua + sxAct live pipeline."""

from __future__ import annotations

import pytest

from sxact.adapter.wolfram import WolframAdapter
from sxact.cli.run import _run_file_live
from sxact.elegua_bridge.adapters import EleguaWolframAdapter
from sxact.runner.loader import load_test_file


@pytest.mark.oracle
@pytest.mark.slow
def test_toml_to_elegua_wolfram_four_layer_validation_token_smoke(
    tmp_path, oracle_url: str, oracle
) -> None:
    """Load TOML, run through IsolatedRunner+WolframAdapter, and reach L4 compare.

    The fixture-provided ``oracle`` performs the availability check and skips when
    the live Wolfram oracle is absent. The actual run intentionally constructs a
    fresh ``WolframAdapter`` so the production adapter wrapping path is exercised.
    """
    test_path = tmp_path / "elegua_smoke.toml"
    test_path.write_text(
        """
[meta]
id = "elegua/smoke"
description = "Elegua + sxAct live smoke"
tags = ["elegua", "smoke"]
layer = 3
oracle_is_axiom = true

[[tests]]
id = "trig_identity_numeric_layer"
description = "Numeric layer validates a scalar identity"

[[tests.operations]]
action = "Evaluate"
[tests.operations.args]
expression = "Sin[x]^2 + Cos[x]^2"

[tests.expected]
expr = "1"
comparison_tier = 3
""".strip(),
        encoding="utf-8",
    )

    test_file = load_test_file(test_path)
    adapter = EleguaWolframAdapter(WolframAdapter(base_url=oracle_url, timeout=120))

    results = _run_file_live(test_file, adapter, tag_filter=None)

    assert len(results) == 1
    assert results[0].status == "pass"
    assert results[0].message == "matched at L4 numeric"
