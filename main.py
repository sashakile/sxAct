"""
sxAct - xAct Migration Experiments

Main entry point for Python-based experiments with Wolfram/xAct interoperability.
"""

def main():
    print("sxAct - xAct Migration Experiments")
    print("=" * 50)
    print("\nAvailable commands:")
    print("  - Run Wolfram: docker compose run --rm wolfram wolframscript")
    print("  - Test xAct: docker compose run --rm wolfram wolframscript -file /notebooks/test_xact.wls")
    print("  - Python example: uv run python notebooks/test_python_wolfram.py")
    print("\nSee SETUP.md for full documentation.")


if __name__ == "__main__":
    main()
