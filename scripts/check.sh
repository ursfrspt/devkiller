#!/usr/bin/env bash
set -euo pipefail

swift test
swift build
swift run devkillerctl list
./scripts/build-app.sh >/dev/null
