#!/bin/bash
# Helper script to run Wolfram Engine with xAct

# Add xAct to path and run wolframscript
docker compose run --rm wolfram wolframscript -code "AppendTo[\$Path, \"/opt\"]" -run "$@"
