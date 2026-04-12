#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

MODE="none"
SOURCE_DIR=""
TARGET=""
RELEASE_ID=""
RELEASE_TAG=""
MACHINE=""
MACHINE_ARCHITECTURE=""
PLATFORM_KEY=""
BASE_NAME=""
BASE_COMMIT=""

PUBLISH_DIR=""
PUBLISH_SCRIPT=""
RSYNC_DEST=""
RSYNC_RSH=""

usage() {
  cat <<EOF
usage: $0 [options]

options:
  --mode <name>            none|local|copy|script|rsync (default: none)
  --source-dir <path>      source directory to publish
  --artifact-dir <path>    deprecated alias for --source-dir
  --target <name>          target name (required)
  --release-id <id>        release id (required)
  --release-tag <tag>      optional release tag
  --machine <name>         optional machine name (used to resolve platform key)
  --machine-architecture <name>
                           optional machine architecture (used with --machine)
  --platform-key <name>    optional explicit platform key (default: <machine>[-<machine-architecture>])
  --base-name <name>       optional base name for script mode env
  --base-commit <sha>      optional base commit for script mode env
  --publish-dir <path>     destination root for mode=copy
  --publish-script <path>  hook script for mode=script
  --rsync-dest <dest>      destination root for mode=rsync
  --rsync-rsh <command>    optional rsync -e command
  --help                   show this message
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      [ "$#" -ge 2 ] || die "missing value for --mode"
      MODE="$2"
      shift 2
      ;;
    --source-dir|--artifact-dir)
      [ "$#" -ge 2 ] || die "missing value for $1"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --target)
      [ "$#" -ge 2 ] || die "missing value for --target"
      TARGET="$2"
      shift 2
      ;;
    --release-id)
      [ "$#" -ge 2 ] || die "missing value for --release-id"
      RELEASE_ID="$2"
      shift 2
      ;;
    --release-tag)
      [ "$#" -ge 2 ] || die "missing value for --release-tag"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --machine)
      [ "$#" -ge 2 ] || die "missing value for --machine"
      MACHINE="$2"
      shift 2
      ;;
    --machine-architecture)
      [ "$#" -ge 2 ] || die "missing value for --machine-architecture"
      MACHINE_ARCHITECTURE="$2"
      shift 2
      ;;
    --platform-key)
      [ "$#" -ge 2 ] || die "missing value for --platform-key"
      PLATFORM_KEY="$2"
      shift 2
      ;;
    --base-name)
      [ "$#" -ge 2 ] || die "missing value for --base-name"
      BASE_NAME="$2"
      shift 2
      ;;
    --base-commit)
      [ "$#" -ge 2 ] || die "missing value for --base-commit"
      BASE_COMMIT="$2"
      shift 2
      ;;
    --publish-dir)
      [ "$#" -ge 2 ] || die "missing value for --publish-dir"
      PUBLISH_DIR="$2"
      shift 2
      ;;
    --publish-script)
      [ "$#" -ge 2 ] || die "missing value for --publish-script"
      PUBLISH_SCRIPT="$2"
      shift 2
      ;;
    --rsync-dest)
      [ "$#" -ge 2 ] || die "missing value for --rsync-dest"
      RSYNC_DEST="$2"
      shift 2
      ;;
    --rsync-rsh)
      [ "$#" -ge 2 ] || die "missing value for --rsync-rsh"
      RSYNC_RSH="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -n "$TARGET" ] || die "missing required option: --target"
[ -n "$RELEASE_ID" ] || die "missing required option: --release-id"

resolve_platform_key() {
  if [ -n "$PLATFORM_KEY" ]; then
    return
  fi

  if [ -n "$MACHINE" ]; then
    if [ -n "$MACHINE_ARCHITECTURE" ]; then
      PLATFORM_KEY="$MACHINE-$MACHINE_ARCHITECTURE"
    else
      PLATFORM_KEY="$MACHINE"
    fi
  fi

  [ -n "$PLATFORM_KEY" ] || die "missing platform context: set --platform-key or --machine"
}

require_source_dir() {
  [ -n "$SOURCE_DIR" ] || die "missing required option: --source-dir"
  [ -d "$SOURCE_DIR" ] || die "source directory not found: $SOURCE_DIR"
}

publish_copy() {
  require_source_dir
  [ -n "$PUBLISH_DIR" ] || die "mode=copy requires --publish-dir"

  dest="$PUBLISH_DIR/$TARGET/$RELEASE_ID/$PLATFORM_KEY"
  mkdir -p "$dest"
  cp -R "$SOURCE_DIR"/. "$dest"/
  info "published to: $dest"
}

publish_script() {
  require_source_dir
  [ -n "$PUBLISH_SCRIPT" ] || die "mode=script requires --publish-script"
  [ -f "$PUBLISH_SCRIPT" ] || die "publish script not found: $PUBLISH_SCRIPT"

  PIPELINE_TARGET="$TARGET" \
  PIPELINE_RELEASE_ID="$RELEASE_ID" \
  PIPELINE_RELEASE_TAG="$RELEASE_TAG" \
  PIPELINE_MACHINE="$MACHINE" \
  PIPELINE_MACHINE_ARCHITECTURE="$MACHINE_ARCHITECTURE" \
  PIPELINE_PLATFORM_KEY="$PLATFORM_KEY" \
  PIPELINE_SOURCE_DIR="$SOURCE_DIR" \
  PIPELINE_ARTIFACT_DIR="$SOURCE_DIR" \
  PIPELINE_BASE_NAME="$BASE_NAME" \
  PIPELINE_BASE_COMMIT="$BASE_COMMIT" \
  sh "$PUBLISH_SCRIPT"
}

publish_rsync() {
  require_source_dir
  [ -n "$RSYNC_DEST" ] || die "mode=rsync requires --rsync-dest"

  if ! command -v rsync >/dev/null 2>&1; then
    die "rsync is required for mode=rsync"
  fi

  dest="$RSYNC_DEST/$TARGET/$RELEASE_ID/$PLATFORM_KEY"

  if [ -n "$RSYNC_RSH" ]; then
    rsync -a --delete -e "$RSYNC_RSH" "$SOURCE_DIR"/ "$dest"/
  else
    rsync -a --delete "$SOURCE_DIR"/ "$dest"/
  fi

  info "published via rsync to: $dest"
}

case "$MODE" in
  none)
    info "stage: publish skipped"
    ;;
  local)
    require_source_dir
    info "stage: publish local-only ($SOURCE_DIR)"
    ;;
  copy)
    resolve_platform_key
    info "stage: publish copy"
    publish_copy
    ;;
  script)
    resolve_platform_key
    info "stage: publish script"
    publish_script
    ;;
  rsync)
    resolve_platform_key
    info "stage: publish rsync"
    publish_rsync
    ;;
  *)
    die "invalid publish mode: $MODE"
    ;;
esac
