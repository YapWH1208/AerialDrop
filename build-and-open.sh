#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

. "$PROJECT_DIR/Scripts/select-xcode.sh" || exit $?

rm -rf -- .build dist
./Scripts/build-app.sh
open -n "$PROJECT_DIR/dist/AerialDrop.app"
