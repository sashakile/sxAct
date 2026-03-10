# sxAct — xAct Migration & Implementation
# Copyright (C) 2026 sxAct Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

"""
sxAct - xAct Migration Experiments

Main entry point for Python-based experiments with Wolfram/xAct interoperability.
"""


def main():
    print("sxAct - xAct Migration Experiments")
    print("=" * 50)
    print("\nAvailable commands:")
    print("  - Run Wolfram: docker compose run --rm wolfram wolframscript")
    print(
        "  - Test xAct: docker compose run --rm wolfram wolframscript -file /notebooks/test_xact.wls"
    )
    print("  - Python example: uv run python notebooks/test_python_wolfram.py")
    print("\nSee SETUP.md for full documentation.")


if __name__ == "__main__":
    main()
