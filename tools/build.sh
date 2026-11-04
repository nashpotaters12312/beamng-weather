#!/usr/bin/env bash
# Packs the mod into dist/beamng_weather.zip, ready for the BeamNG mods folder.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
rm -f dist/beamng_weather.zip
(cd mod && zip -r -X ../dist/beamng_weather.zip . -x '*.DS_Store')
echo "Built dist/beamng_weather.zip"
