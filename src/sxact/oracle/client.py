"""HTTP client for the Wolfram Oracle server."""

from dataclasses import dataclass
from typing import Optional

import requests


@dataclass
class EvalResult:
    """Result from evaluating a Wolfram expression."""

    status: str
    result: Optional[str] = None
    error: Optional[str] = None
    timing_ms: Optional[int] = None


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

    def evaluate(self, expr: str, timeout: int = 30) -> EvalResult:
        """Evaluate a Wolfram expression."""
        try:
            resp = requests.post(
                f"{self.base_url}/evaluate",
                json={"expr": expr, "timeout": timeout},
                timeout=timeout + 5,
            )
            data = resp.json()
            return EvalResult(
                status=data.get("status", "error"),
                result=data.get("result"),
                error=data.get("error"),
                timing_ms=data.get("timing_ms"),
            )
        except requests.RequestException as e:
            return EvalResult(status="error", error=str(e))

    def evaluate_with_xact(self, expr: str, timeout: int = 60) -> EvalResult:
        """Evaluate a Wolfram expression with xAct pre-loaded."""
        try:
            resp = requests.post(
                f"{self.base_url}/evaluate-with-init",
                json={"expr": expr, "timeout": timeout},
                timeout=timeout + 5,
            )
            data = resp.json()
            return EvalResult(
                status=data.get("status", "error"),
                result=data.get("result"),
                error=data.get("error"),
                timing_ms=data.get("timing_ms"),
            )
        except requests.RequestException as e:
            return EvalResult(status="error", error=str(e))
