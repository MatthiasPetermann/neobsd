#!/bin/sh
set -eu

# Example hook for: scripts/publish-artifacts.sh --mode script
#
# This hook receives all pipeline values via environment variables:
#   PIPELINE_SOURCE_DIR    (required)
#   PIPELINE_ARTIFACT_DIR  (deprecated alias)
#   PIPELINE_TARGET        (required)
#   PIPELINE_RELEASE_ID    (required)
#   PIPELINE_RELEASE_TAG   (optional)
#   PIPELINE_MACHINE       (optional)
#   PIPELINE_MACHINE_ARCHITECTURE (optional)
#   PIPELINE_PLATFORM_KEY  (required)
#   PIPELINE_BASE_NAME     (optional)
#   PIPELINE_BASE_COMMIT   (optional)

require_var() {
  name="$1"
  eval "value=\${$name:-}"
  [ -n "$value" ] || {
    printf 'error: missing required env var: %s\n' "$name" >&2
    exit 1
  }
}

require_var PIPELINE_SOURCE_DIR
require_var PIPELINE_TARGET
require_var PIPELINE_RELEASE_ID
require_var PIPELINE_PLATFORM_KEY

PUBLISH_ROOT="${PUBLISH_ROOT:-/srv/neobsd/releases}"
DEST="$PUBLISH_ROOT/$PIPELINE_TARGET/$PIPELINE_RELEASE_ID/$PIPELINE_PLATFORM_KEY"

mkdir -p "$DEST"
cp -R "$PIPELINE_SOURCE_DIR"/. "$DEST"/

printf 'publish-hook: target=%s release_id=%s platform=%s release_tag=%s\n' \
  "$PIPELINE_TARGET" \
  "$PIPELINE_RELEASE_ID" \
  "$PIPELINE_PLATFORM_KEY" \
  "${PIPELINE_RELEASE_TAG:-<none>}" >&2
printf 'publish-hook: destination=%s\n' "$DEST" >&2
