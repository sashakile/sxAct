"""Wolfram Expression Translator — WL surface syntax → sxAct action dicts.

Public API::

    from xact.translate import wl_to_action, wl_to_actions

    wl_to_action("DefManifold[M, 4, {a, b, c, d}]")
    # → {"action": "DefManifold", "args": {"name": "M", "dimension": 4, ...}}

    wl_to_actions("DefManifold[M, 4, {a,b}]; DefMetric[-1, g[-a,-b], CD]")
    # → [{"action": "DefManifold", ...}, {"action": "DefMetric", ...}]
"""

from xact.translate.action_recognizer import wl_to_action, wl_to_actions

__all__ = ["wl_to_action", "wl_to_actions"]
