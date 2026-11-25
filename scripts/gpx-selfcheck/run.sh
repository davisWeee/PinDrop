#!/bin/bash
# Compiles the pure-Foundation GPX/route logic with a self-check driver and runs it.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${TMPDIR:-/tmp}/pindrop-gpx-selfcheck"
swiftc -O -o "$OUT" \
  RoamControl/Services/GPX/GPXModels.swift \
  RoamControl/Services/GPX/GPXParser.swift \
  RoamControl/Services/GPX/GPXWriter.swift \
  RoamControl/Features/Route/RouteGeometry.swift \
  scripts/gpx-selfcheck/main.swift
"$OUT"
