"""HTTP client for the Wolfram Oracle server."""

from typing import Any, Literal

import requests

from sxact.normalize import normalize
from sxact.oracle.result import Result


class OracleClient:
    """Client for communicating with the Wolfram Oracle HTTP server."""

    def __init__(self, base_url: str = "http://localhost:8765"):
        self.base_url = base_url.rstrip("/")

    def health(self) -> bool:
        """Check if the oracle server is healthy."""
        try:
            resp = requests.get(f"{self.base_url}/health", timeout=5)
            return resp.status_code == 200 and resp.json().get("status") == "ok"
        except requests.RequestException:
            return False

    def evaluate(self, expr: str, timeout: int = 30) -> Result:
        """Evaluate a Wolfram expression."""
        try:
            resp = requests.post(
                f"{self.base_url}/evaluate",
                json={"expr": expr, "timeout": timeout},
                timeout=timeout + 5,
            )
            data = resp.json()
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
        except requests.RequestException as e:
            return Result(status="error", type="", repr="", normalized="", error=str(e))

    def evaluate_with_xact(
        self, expr: str, timeout: int = 60, context_id: str | None = None
    ) -> Result:
        """Evaluate a Wolfram expression with xAct pre-loaded.

        Args:
            expr: The Wolfram expression to evaluate.
            timeout: Timeout in seconds.
            context_id: Optional context ID for test isolation. When provided,
                the server wraps the expression in a Block with a unique context
                to prevent symbol pollution between tests.
        """
        json_body: dict[str, Any] = {"expr": expr, "timeout": timeout}
        if context_id:
            json_body["context_id"] = context_id
        try:
            resp = requests.post(
                f"{self.base_url}/evaluate-with-init",
                json=json_body,
                timeout=timeout + 5,
            )
            data = resp.json()
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
        except requests.RequestException as e:
            return Result(status="error", type="", repr="", normalized="", error=str(e))

    def cleanup(self) -> bool:
        """Clear Global context and reset xAct registries on the oracle.

        Returns True on success, False if the oracle is unavailable or errors.
        """
        try:
            resp = requests.post(f"{self.base_url}/cleanup", timeout=35)
            return resp.status_code == 200 and resp.json().get("status") == "ok"
        except requests.RequestException:
            return False

    def restart(self) -> bool:
        """Hard-restart the Wolfram kernel via the oracle.

        Returns True on success.  This is an expensive operation and should
        only be used as a fallback when cleanup() leaves dirty state.
        """
        try:
            resp = requests.post(f"{self.base_url}/restart", timeout=120)
            return resp.status_code == 200 and resp.json().get("status") == "ok"
        except requests.RequestException:
            return False

    def check_clean_state(self) -> tuple[bool, list[str]]:
        """Query oracle registry counts for leak detection.

        Returns (is_clean: bool, leaked_symbols: list[str]).
        ``is_clean`` is True when Manifolds and Tensors registries are both
        empty.  Falls back to (False, []) if the oracle is unreachable.
        """
        try:
            resp = requests.get(f"{self.base_url}/check-state", timeout=15)
            data = resp.json()
            return data.get("clean", False), data.get("leaked", [])
        except requests.RequestException:
            return False, []
