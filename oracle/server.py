"""Flask HTTP server for Wolfram Engine evaluation with persistent kernel."""

import time

from flask import Flask, jsonify, request

from kernel_manager import KernelManager

app = Flask(__name__)
km = KernelManager()


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/evaluate", methods=["POST"])
def evaluate():
    """Evaluate a Wolfram expression (without xAct)."""
    data = request.get_json()
    if not data or "expr" not in data:
        return jsonify({"status": "error", "error": "Missing 'expr' field"}), 400

    expr = data["expr"]
    timeout = int(data.get("timeout", 30))

    start = time.time()
    ok, result, error = km.evaluate(expr, timeout, with_xact=False)
    elapsed_ms = int((time.time() - start) * 1000)

    if ok:
        return jsonify({"status": "ok", "result": result, "timing_ms": elapsed_ms})
    else:
        status = "timeout" if error and "timed out" in error else "error"
        return jsonify({"status": status, "error": error, "timing_ms": elapsed_ms})


@app.route("/evaluate-with-init", methods=["POST"])
def evaluate_with_init():
    """Evaluate expression with xAct pre-loaded."""
    data = request.get_json()
    if not data or "expr" not in data:
        return jsonify({"status": "error", "error": "Missing 'expr' field"}), 400

    expr = data["expr"]
    timeout = int(data.get("timeout", 60))
    context_id = data.get("context_id")  # Optional context isolation

    start = time.time()
    ok, result, error = km.evaluate(expr, timeout, with_xact=True, context_id=context_id)
    elapsed_ms = int((time.time() - start) * 1000)

    if ok:
        return jsonify({"status": "ok", "result": result, "timing_ms": elapsed_ms})
    else:
        status = "timeout" if error and "timed out" in error else "error"
        return jsonify({"status": status, "error": error, "timing_ms": elapsed_ms})


@app.route("/cleanup", methods=["POST"])
def cleanup():
    """Clear Global context and reset xAct registries between test files."""
    ok, result, error = km.cleanup()
    if ok:
        return jsonify({"status": "ok", "result": result})
    else:
        return jsonify({"status": "error", "error": error}), 500


@app.route("/restart", methods=["POST"])
def restart():
    """Hard-restart the Wolfram kernel (last-resort isolation fallback)."""
    try:
        km.restart()
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "error": str(e)}), 500


@app.route("/check-state", methods=["GET"])
def check_state():
    """Return current xAct registry counts for leak detection."""
    is_clean, leaked = km.check_clean_state()
    return jsonify({
        "clean": is_clean,
        "leaked": leaked,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8765, threaded=True)
