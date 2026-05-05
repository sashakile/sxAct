"""sxAct result-adapting client for the Elegua Wolfram oracle HTTP API."""

from __future__ import annotations

import json
import urllib.error
from typing import Any, Literal

from elegua.oracle import OracleClient as EleguaOracleClient

from sxact.normalize import normalize
from sxact.oracle.result import Result


class OracleClient:
    """Client for communicating with the Wolfram Oracle server.

    The HTTP transport is provided by :class:`elegua.oracle.OracleClient`; sxAct
    keeps this thin adapter to preserve its historical ``Result`` envelope and
    the ``evaluate`` endpoint used by older tests/tools.
    """

    def __init__(self, base_url: str = "http://localhost:8765") -> None:
        self._client = EleguaOracleClient(base_url=base_url)

    @property
    def base_url(self) -> str:
        """Base URL for the underlying oracle service."""
        return self._client.base_url

    def health(self) -> bool:
        """Check if the oracle server is healthy."""
        return self._client.health()

    def evaluate(self, expr: str, timeout: int = 30) -> Result:
        """Evaluate a Wolfram expression and return an sxAct ``Result``."""
        try:
            data = self._client._post(
                "/evaluate", {"expr": expr, "timeout": timeout}, timeout + 5
            )
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
            return Result(status="error", type="", repr="", normalized="", error=str(exc))
        return _result_from_oracle_payload(data)

    def evaluate_with_xact(
        self, expr: str, timeout: int = 60, context_id: str | None = None
    ) -> Result:
        """Evaluate a Wolfram expression with xAct pre-loaded."""
        data = self._client.evaluate_with_xact(expr, timeout=timeout, context_id=context_id)
        return _result_from_oracle_payload(data)

    def cleanup(self) -> bool:
        """Clear Global context and reset xAct registries on the oracle."""
        return self._client.cleanup()

    def restart(self) -> bool:
        """Hard-restart the Wolfram kernel via the oracle."""
        try:
            data = self._client._post("/restart", {}, timeout=120)
            return data.get("status") == "ok"
        except (urllib.error.URLError, OSError, ValueError):
            return False

    def check_clean_state(self) -> tuple[bool, list[str]]:
        """Query oracle registry counts for leak detection."""
        return self._client.check_clean_state()


def _result_from_oracle_payload(data: dict[str, Any]) -> Result:
    """Convert an Elegua oracle JSON payload into sxAct's ``Result`` envelope."""
    status_raw = data.get("status", "error")
    status: Literal["ok", "error", "timeout"] = (
        "ok" if status_raw == "ok" else "timeout" if status_raw == "timeout" else "error"
    )
    raw = data.get("result", "") or ""
    return Result(
        status=status,
        type=data.get("type", "Expr"),
        repr=raw,
        normalized=normalize(raw) if raw else "",
        properties=data.get("properties", {}),
        diagnostics={"execution_time_ms": data.get("timing_ms")},
        error=data.get("error"),
    )
