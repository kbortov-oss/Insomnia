#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
"$PROJECT_ROOT/scripts/build.sh"
NAME="Insomnia-v$VERSION-macOS-arm64-preview.zip"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR/Insomnia.app" "$OUTPUT_DIR/$NAME"
(cd "$OUTPUT_DIR" && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "Preview archive: $OUTPUT_DIR/$NAME"
