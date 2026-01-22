"""Flask HTTP server for Wolfram Engine evaluation."""

from flask import Flask, request, jsonify
import subprocess
import time

app = Flask(__name__)

INIT_SCRIPT = "/oracle/init.wl"


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/evaluate", methods=["POST"])
def evaluate():
    data = request.get_json()
    if not data or "expr" not in data:
        return jsonify({"status": "error", "error": "Missing 'expr' field"}), 400

    expr = data["expr"]
    timeout = data.get("timeout", 30)

    start = time.time()
    try:
        result = subprocess.run(
            ["wolframscript", "-code", expr],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        elapsed_ms = int((time.time() - start) * 1000)

        if result.returncode == 0:
            return jsonify(
                {
                    "status": "ok",
                    "result": result.stdout.strip(),
                    "timing_ms": elapsed_ms,
                }
            )
        else:
            return jsonify(
                {
                    "status": "error",
                    "result": result.stdout.strip(),
                    "error": result.stderr.strip(),
                    "timing_ms": elapsed_ms,
                }
            )
    except subprocess.TimeoutExpired:
        elapsed_ms = int((time.time() - start) * 1000)
        return jsonify(
            {
                "status": "timeout",
                "error": f"Evaluation timed out after {timeout}s",
                "timing_ms": elapsed_ms,
            }
        )
    except Exception as e:
        elapsed_ms = int((time.time() - start) * 1000)
        return jsonify(
            {
                "status": "error",
                "error": str(e),
                "timing_ms": elapsed_ms,
            }
        )


@app.route("/evaluate-with-init", methods=["POST"])
def evaluate_with_init():
    """Evaluate expression with xAct pre-loaded."""
    data = request.get_json()
    if not data or "expr" not in data:
        return jsonify({"status": "error", "error": "Missing 'expr' field"}), 400

    expr = data["expr"]
    timeout = data.get("timeout", 60)

    full_expr = f'Get["{INIT_SCRIPT}"]; {expr}'

    start = time.time()
    try:
        result = subprocess.run(
            ["wolframscript", "-code", full_expr],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        elapsed_ms = int((time.time() - start) * 1000)

        if result.returncode == 0:
            return jsonify(
                {
                    "status": "ok",
                    "result": result.stdout.strip(),
                    "timing_ms": elapsed_ms,
                }
            )
        else:
            return jsonify(
                {
                    "status": "error",
                    "result": result.stdout.strip(),
                    "error": result.stderr.strip(),
                    "timing_ms": elapsed_ms,
                }
            )
    except subprocess.TimeoutExpired:
        elapsed_ms = int((time.time() - start) * 1000)
        return jsonify(
            {
                "status": "timeout",
                "error": f"Evaluation timed out after {timeout}s",
                "timing_ms": elapsed_ms,
            }
        )
    except Exception as e:
        elapsed_ms = int((time.time() - start) * 1000)
        return jsonify(
            {
                "status": "error",
                "error": str(e),
                "timing_ms": elapsed_ms,
            }
        )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8765)
