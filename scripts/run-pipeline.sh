#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/lib/common.sh"

CLI_PROFILE_FILE=""
CLI_TARGET=""
CLI_SRC_DIR=""
CLI_SRC_REPO=""
CLI_XSRC_REPO=""
CLI_FETCH_MODE=""
CLI_MACHINE=""
CLI_MACHINE_ARCHITECTURE=""
CLI_XSRC_DIR=""
CLI_JOBS=""
CLI_BUILD_STEPS=""
CLI_TOOLS_ROOT=""
CLI_TOOLS_DIR=""
CLI_OBJ_ROOT=""
CLI_OBJ_DIR=""
CLI_RELEASE_TAG=""
CLI_RELEASE_ID=""
CLI_PUBLISH_MODE=""
CLI_PUBLISH_DIR=""
CLI_PUBLISH_SCRIPT=""
CLI_RSYNC_DEST=""
CLI_RSYNC_RSH=""

CLI_DO_BUILD_SET=0
CLI_DO_BUILD=1
CLI_NO_X_SET=0
CLI_NO_X=1
CLI_REUSE_TOOLS_SET=0
CLI_REUSE_TOOLS=0
CLI_CHECK_PREFIX_ORDER_SET=0
CLI_CHECK_PREFIX_ORDER=1
CLI_CLEAN=0

usage() {
  cat <<EOF
usage: $0 [options]

options:
  --profile <path>              shell build profile file (any filename)
  --target <name>               target in targets/<name>
  --src-dir <path>              path to netbsd-src checkout
  --src-repo <url>              source repository (default: NetBSD/src)
  --xsrc-repo <url>             xsrc repository (default: NetBSD/xsrc)
  --fetch-mode <mode>           auto|none
  --machine <name>              NetBSD MACHINE
  --machine-architecture <name> NetBSD MACHINE_ARCH
  --xsrc-dir <path>             path to netbsd-xsrc checkout
  --jobs <n>                    build parallelism
  --build-steps <names>         space-separated list: tools|release|sourcesets|iso-image|install-image|all
  --tools-root <path>           root for reusable tooldirs
  --tools-dir <path>            explicit tooldir (overrides --tools-root)
  --reuse-tools <bool>          reuse existing tooldir if available (default: 0)
  --obj-root <path>             root for per-target/release/platform obj dirs
  --obj-dir <path>              explicit obj dir (overrides --obj-root)
  --release-tag <tag>           release tag for publishing/metadata
  --release-id <id>             id used in directory layout
  --clean                       remove existing obj path before run
  --publish-mode <mode>         none|local|copy|script|rsync
  --publish-dir <path>          destination base dir for publish-mode=copy
  --publish-script <path>       hook script for publish-mode=script
  --rsync-dest <dest>           rsync destination root for publish-mode=rsync
  --rsync-rsh <command>         optional rsync -e value
  --no-build                    skip build stage
  --build                       force build stage on
  --no-x                        disable xsrc during build
  --with-x                      enable xsrc during build
  --check-prefix-order <bool>   enforce non-decreasing series prefixes in validation
  --help                        show this message

notes:
  - If --profile is omitted and --target is set, the expected auto profile is:
      profiles/<target>-<machine>-<machine-architecture-name>
  - release tag format is YY.<sequence> (for example 26.0, 27.0)
  - preflight fails when obj path already exists, unless --clean is set
  - CLI options always override values from the profile.
EOF
}

resolve_release_tag() {
  if [ -n "$RELEASE_TAG" ]; then
    return
  fi

  if RELEASE_TAG="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)"; then
    return
  fi

  RELEASE_TAG=""
}

validate_release_tag() {
  tag="$1"
  err="invalid release tag: $tag (expected: YY.<sequence>, sequence starts at 0)"

  [ -n "$tag" ] || return 0

  case "$tag" in
    *.*)
      year="${tag%%.*}"
      seq="${tag#*.}"
      ;;
    *)
      die "$err"
      ;;
  esac

  case "$year" in
    [0-9][0-9])
      ;;
    *)
      die "$err"
      ;;
  esac

  case "$seq" in
    ''|*[!0-9]*|*.*)
      die "$err"
      ;;
  esac
}

default_machine_architecture_for_machine() {
  machine_name="$1"

  case "$machine_name" in
    amd64)
      printf 'x86_64\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

resolve_machine_architecture_default() {
  if [ -n "$MACHINE_ARCHITECTURE" ]; then
    return
  fi

  MACHINE_ARCHITECTURE="$(default_machine_architecture_for_machine "$MACHINE")"
}

validate_machine_values() {
  case "$MACHINE" in
    amd64)
      if [ "$MACHINE_ARCHITECTURE" = "amd64" ]; then
        die "invalid MACHINE_ARCHITECTURE for MACHINE=amd64: amd64 (use x86_64)"
      fi
      ;;
  esac
}

platform_key_for_machine() {
  machine_name="$1"
  machine_architecture_name="$2"

  if [ -n "$machine_architecture_name" ]; then
    printf '%s-%s\n' "$machine_name" "$machine_architecture_name"
  else
    printf '%s\n' "$machine_name"
  fi
}

resolve_release_id() {
  if [ -n "$RELEASE_ID" ]; then
    return
  fi

  if [ -n "$RELEASE_TAG" ]; then
    RELEASE_ID="$RELEASE_TAG"
    return
  fi

  now="$(date -u +%Y%m%dT%H%M%SZ)"
  sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  RELEASE_ID="dev-$now-$sha"
}

remove_path() {
  path="$1"

  case "$path" in
    ""|"/"|".")
      die "refusing to clean unsafe path: $path"
      ;;
  esac

  [ -e "$path" ] || [ -L "$path" ] || return 0
  rm -rf "$path"
}

preflight_dir() {
  kind="$1"
  dir="$2"
  clean="$3"
  clean_flag="$4"

  if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
    return 0
  fi

  if [ "$clean" = "1" ]; then
    info "preflight: removing existing $kind path: $dir"
    remove_path "$dir"
    return 0
  fi

  die "preflight failed: $kind path already exists: $dir (set $clean_flag or use a different --release-id)"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || die "missing value for --profile"
      CLI_PROFILE_FILE="$2"
      shift 2
      ;;
    --target)
      [ "$#" -ge 2 ] || die "missing value for --target"
      CLI_TARGET="$2"
      shift 2
      ;;
    --src-dir)
      [ "$#" -ge 2 ] || die "missing value for --src-dir"
      CLI_SRC_DIR="$2"
      shift 2
      ;;
    --src-repo)
      [ "$#" -ge 2 ] || die "missing value for --src-repo"
      CLI_SRC_REPO="$2"
      shift 2
      ;;
    --xsrc-repo)
      [ "$#" -ge 2 ] || die "missing value for --xsrc-repo"
      CLI_XSRC_REPO="$2"
      shift 2
      ;;
    --fetch-mode)
      [ "$#" -ge 2 ] || die "missing value for --fetch-mode"
      CLI_FETCH_MODE="$2"
      shift 2
      ;;
    --machine)
      [ "$#" -ge 2 ] || die "missing value for --machine"
      CLI_MACHINE="$2"
      shift 2
      ;;
    --machine-architecture)
      [ "$#" -ge 2 ] || die "missing value for --machine-architecture"
      CLI_MACHINE_ARCHITECTURE="$2"
      shift 2
      ;;
    --xsrc-dir)
      [ "$#" -ge 2 ] || die "missing value for --xsrc-dir"
      CLI_XSRC_DIR="$2"
      shift 2
      ;;
    --jobs)
      [ "$#" -ge 2 ] || die "missing value for --jobs"
      CLI_JOBS="$2"
      shift 2
      ;;
    --build-steps)
      [ "$#" -ge 2 ] || die "missing value for --build-steps"
      CLI_BUILD_STEPS="$2"
      shift 2
      ;;
    --build-step)
      die "option removed: --build-step (use --build-steps)"
      ;;
    --tools-root)
      [ "$#" -ge 2 ] || die "missing value for --tools-root"
      CLI_TOOLS_ROOT="$2"
      shift 2
      ;;
    --tools-dir)
      [ "$#" -ge 2 ] || die "missing value for --tools-dir"
      CLI_TOOLS_DIR="$2"
      shift 2
      ;;
    --reuse-tools)
      [ "$#" -ge 2 ] || die "missing value for --reuse-tools"
      CLI_REUSE_TOOLS_SET=1
      CLI_REUSE_TOOLS="$(bool_to_01 "$2")"
      shift 2
      ;;
    --obj-root)
      [ "$#" -ge 2 ] || die "missing value for --obj-root"
      CLI_OBJ_ROOT="$2"
      shift 2
      ;;
    --obj-dir)
      [ "$#" -ge 2 ] || die "missing value for --obj-dir"
      CLI_OBJ_DIR="$2"
      shift 2
      ;;
    --release-tag)
      [ "$#" -ge 2 ] || die "missing value for --release-tag"
      CLI_RELEASE_TAG="$2"
      shift 2
      ;;
    --release-id)
      [ "$#" -ge 2 ] || die "missing value for --release-id"
      CLI_RELEASE_ID="$2"
      shift 2
      ;;
    --clean)
      CLI_CLEAN=1
      shift 1
      ;;
    --publish-mode)
      [ "$#" -ge 2 ] || die "missing value for --publish-mode"
      CLI_PUBLISH_MODE="$2"
      shift 2
      ;;
    --publish-dir)
      [ "$#" -ge 2 ] || die "missing value for --publish-dir"
      CLI_PUBLISH_DIR="$2"
      shift 2
      ;;
    --publish-script)
      [ "$#" -ge 2 ] || die "missing value for --publish-script"
      CLI_PUBLISH_SCRIPT="$2"
      shift 2
      ;;
    --rsync-dest)
      [ "$#" -ge 2 ] || die "missing value for --rsync-dest"
      CLI_RSYNC_DEST="$2"
      shift 2
      ;;
    --rsync-rsh)
      [ "$#" -ge 2 ] || die "missing value for --rsync-rsh"
      CLI_RSYNC_RSH="$2"
      shift 2
      ;;
    --no-build)
      CLI_DO_BUILD_SET=1
      CLI_DO_BUILD=0
      shift 1
      ;;
    --build)
      CLI_DO_BUILD_SET=1
      CLI_DO_BUILD=1
      shift 1
      ;;
    --no-x)
      CLI_NO_X_SET=1
      CLI_NO_X=1
      shift 1
      ;;
    --with-x)
      CLI_NO_X_SET=1
      CLI_NO_X=0
      shift 1
      ;;
    --check-prefix-order)
      [ "$#" -ge 2 ] || die "missing value for --check-prefix-order"
      CLI_CHECK_PREFIX_ORDER_SET=1
      CLI_CHECK_PREFIX_ORDER="$(bool_to_01 "$2")"
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

TARGET=""
SRC_DIR="$ROOT/../netbsd-src"
SRC_REPO="https://github.com/NetBSD/src.git"
XSRC_REPO="https://github.com/NetBSD/xsrc.git"
FETCH_MODE="auto"

MACHINE="amd64"
MACHINE_ARCHITECTURE=""
XSRC_DIR="$ROOT/../netbsd-xsrc"
JOBS=""
BUILD_STEPS="all"
NO_X="1"

TOOLS_ROOT="$ROOT/../tools"
TOOLS_DIR=""
REUSE_TOOLS="0"

OBJ_ROOT="$ROOT/../obj"
OBJ_DIR=""

RELEASE_TAG=""
RELEASE_ID=""

DO_BUILD="1"
PUBLISH_MODE="none"
PUBLISH_DIR=""
PUBLISH_SCRIPT=""
RSYNC_DEST=""
RSYNC_RSH=""
CHECK_PREFIX_ORDER="1"
CLEAN="0"

PROFILE_FILE="$CLI_PROFILE_FILE"
if [ -z "$PROFILE_FILE" ] && [ -n "$CLI_TARGET" ]; then
  AUTO_MACHINE="$MACHINE"
  if [ -n "$CLI_MACHINE" ]; then
    AUTO_MACHINE="$CLI_MACHINE"
  fi

  AUTO_MACHINE_ARCHITECTURE="$MACHINE_ARCHITECTURE"
  if [ -n "$CLI_MACHINE_ARCHITECTURE" ]; then
    AUTO_MACHINE_ARCHITECTURE="$CLI_MACHINE_ARCHITECTURE"
  fi

  if [ -z "$AUTO_MACHINE_ARCHITECTURE" ]; then
    AUTO_MACHINE_ARCHITECTURE="$(default_machine_architecture_for_machine "$AUTO_MACHINE")"
  fi

  if [ -z "$AUTO_MACHINE_ARCHITECTURE" ]; then
    die "missing machine architecture for profile auto-load: set --machine-architecture or pass --profile explicitly"
  fi

  candidate="$ROOT/profiles/$CLI_TARGET-$AUTO_MACHINE-$AUTO_MACHINE_ARCHITECTURE"

  if [ -f "$candidate" ]; then
    PROFILE_FILE="$candidate"
  else
    die "auto profile not found: $candidate (pass --profile explicitly or create that profile)"
  fi
fi

if [ -n "$PROFILE_FILE" ]; then
  [ -f "$PROFILE_FILE" ] || die "profile file not found: $PROFILE_FILE"
  # shellcheck source=/dev/null
  . "$PROFILE_FILE"
fi

if [ "${BUILD_STEP+x}" = "x" ]; then
  die "profile variable removed: BUILD_STEP (use BUILD_STEPS)"
fi

if [ -n "${GIT_COMMITTER_NAME:-}" ] || [ -n "${GIT_COMMITTER_EMAIL:-}" ]; then
  [ -n "${GIT_COMMITTER_NAME:-}" ] || die "GIT_COMMITTER_EMAIL is set but GIT_COMMITTER_NAME is missing"
  [ -n "${GIT_COMMITTER_EMAIL:-}" ] || die "GIT_COMMITTER_NAME is set but GIT_COMMITTER_EMAIL is missing"
  export GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
fi

if [ -z "${XSRC_DIR:-}" ] && [ -n "${XSRCDIR:-}" ]; then
  XSRC_DIR="$XSRCDIR"
  log_warn "XSRCDIR is deprecated; use XSRC_DIR"
fi

if [ -n "$CLI_TARGET" ]; then TARGET="$CLI_TARGET"; fi
if [ -n "$CLI_SRC_DIR" ]; then SRC_DIR="$CLI_SRC_DIR"; fi
if [ -n "$CLI_SRC_REPO" ]; then SRC_REPO="$CLI_SRC_REPO"; fi
if [ -n "$CLI_XSRC_REPO" ]; then XSRC_REPO="$CLI_XSRC_REPO"; fi
if [ -n "$CLI_FETCH_MODE" ]; then FETCH_MODE="$CLI_FETCH_MODE"; fi
if [ -n "$CLI_MACHINE" ]; then MACHINE="$CLI_MACHINE"; fi
if [ -n "$CLI_MACHINE_ARCHITECTURE" ]; then MACHINE_ARCHITECTURE="$CLI_MACHINE_ARCHITECTURE"; fi
if [ -n "$CLI_XSRC_DIR" ]; then XSRC_DIR="$CLI_XSRC_DIR"; fi
if [ -n "$CLI_JOBS" ]; then JOBS="$CLI_JOBS"; fi
if [ -n "$CLI_BUILD_STEPS" ]; then BUILD_STEPS="$CLI_BUILD_STEPS"; fi
if [ -n "$CLI_TOOLS_ROOT" ]; then TOOLS_ROOT="$CLI_TOOLS_ROOT"; fi
if [ -n "$CLI_TOOLS_DIR" ]; then TOOLS_DIR="$CLI_TOOLS_DIR"; fi
if [ -n "$CLI_OBJ_ROOT" ]; then OBJ_ROOT="$CLI_OBJ_ROOT"; fi
if [ -n "$CLI_OBJ_DIR" ]; then OBJ_DIR="$CLI_OBJ_DIR"; fi
if [ -n "$CLI_RELEASE_TAG" ]; then RELEASE_TAG="$CLI_RELEASE_TAG"; fi
if [ -n "$CLI_RELEASE_ID" ]; then RELEASE_ID="$CLI_RELEASE_ID"; fi
if [ "$CLI_CLEAN" -eq 1 ]; then CLEAN="1"; fi
if [ -n "$CLI_PUBLISH_MODE" ]; then PUBLISH_MODE="$CLI_PUBLISH_MODE"; fi
if [ -n "$CLI_PUBLISH_DIR" ]; then PUBLISH_DIR="$CLI_PUBLISH_DIR"; fi
if [ -n "$CLI_PUBLISH_SCRIPT" ]; then PUBLISH_SCRIPT="$CLI_PUBLISH_SCRIPT"; fi
if [ -n "$CLI_RSYNC_DEST" ]; then RSYNC_DEST="$CLI_RSYNC_DEST"; fi
if [ -n "$CLI_RSYNC_RSH" ]; then RSYNC_RSH="$CLI_RSYNC_RSH"; fi
if [ "$CLI_DO_BUILD_SET" -eq 1 ]; then DO_BUILD="$CLI_DO_BUILD"; fi
if [ "$CLI_NO_X_SET" -eq 1 ]; then NO_X="$CLI_NO_X"; fi
if [ "$CLI_REUSE_TOOLS_SET" -eq 1 ]; then REUSE_TOOLS="$CLI_REUSE_TOOLS"; fi
if [ "$CLI_CHECK_PREFIX_ORDER_SET" -eq 1 ]; then CHECK_PREFIX_ORDER="$CLI_CHECK_PREFIX_ORDER"; fi

resolve_machine_architecture_default
validate_machine_values

PLATFORM_KEY="$(platform_key_for_machine "$MACHINE" "$MACHINE_ARCHITECTURE")"

DO_BUILD="$(bool_to_01 "$DO_BUILD")"
NO_X="$(bool_to_01 "$NO_X")"
REUSE_TOOLS="$(bool_to_01 "$REUSE_TOOLS")"
CHECK_PREFIX_ORDER="$(bool_to_01 "$CHECK_PREFIX_ORDER")"
CLEAN="$(bool_to_01 "$CLEAN")"

resolve_release_tag
validate_release_tag "$RELEASE_TAG"

[ -n "$TARGET" ] || die "missing target. pass --target or set TARGET in profile"

resolve_release_id

TARGET_DIR="$ROOT/targets/$TARGET"
BASE_FILE="$TARGET_DIR/base"
COMMIT_FILE="$TARGET_DIR/commit"

[ -f "$BASE_FILE" ] || die "missing target file: $BASE_FILE"
[ -f "$COMMIT_FILE" ] || die "missing target file: $COMMIT_FILE"

BASE_NAME="$(tr -d '\r\n' < "$BASE_FILE")"
BASE_COMMIT="$(tr -d '\r\n' < "$COMMIT_FILE")"

if [ "$REUSE_TOOLS" = "1" ] && [ -z "$TOOLS_DIR" ]; then
  TOOLS_DIR="$TOOLS_ROOT/$TARGET/$RELEASE_ID/$PLATFORM_KEY"
fi

if [ -z "$OBJ_DIR" ]; then
  OBJ_DIR="$OBJ_ROOT/$TARGET/$RELEASE_ID/$PLATFORM_KEY"
fi

preflight_dir "obj" "$OBJ_DIR" "$CLEAN" "--clean"

mkdir -p "$OBJ_DIR"

info "orchestrator"
info "target: $TARGET"
info "release tag: ${RELEASE_TAG:-<none>}"
info "release id: $RELEASE_ID"
info "profile: ${PROFILE_FILE:-<none>}"
info "src repo: $SRC_REPO"
info "src dir: $SRC_DIR"
info "xsrc repo: $XSRC_REPO"
info "xsrc dir: $XSRC_DIR"
info "fetch mode: $FETCH_MODE"
info "machine: $MACHINE"
info "machine architecture: ${MACHINE_ARCHITECTURE:-<default>}"
info "platform key: $PLATFORM_KEY"
info "tools root: $TOOLS_ROOT"
info "tools dir: ${TOOLS_DIR:-<auto>}"
info "reuse tools: $REUSE_TOOLS"
info "clean: $CLEAN"
info "obj dir: $OBJ_DIR"
info "build steps: $BUILD_STEPS"

info "stage: prepare-repos"

set -- \
  --src-dir "$SRC_DIR" \
  --src-repo "$SRC_REPO" \
  --xsrc-dir "$XSRC_DIR" \
  --xsrc-repo "$XSRC_REPO" \
  --base-name "$BASE_NAME" \
  --base-commit "$BASE_COMMIT" \
  --fetch-mode "$FETCH_MODE"

if [ "$NO_X" = "1" ]; then
  set -- "$@" --no-x
else
  set -- "$@" --with-x
fi

"$SCRIPT_DIR/prepare-repos.sh" "$@"

info "stage: apply"
"$SCRIPT_DIR/apply-patches.sh" \
  --target "$TARGET" \
  --src-dir "$SRC_DIR" \
  --targets-dir "$ROOT/targets" \
  --patch-dir "$ROOT/patches" \
  --base-name "$BASE_NAME" \
  --base-commit "$BASE_COMMIT" \
  --check-prefix-order "$CHECK_PREFIX_ORDER"

if [ "$DO_BUILD" = "1" ]; then
  info "stage: build"

  set -- \
    --src-dir "$SRC_DIR" \
    --steps "$BUILD_STEPS" \
    --machine "$MACHINE" \
    --obj-dir "$OBJ_DIR" \
    --xsrc-dir "$XSRC_DIR"

  if [ -n "$MACHINE_ARCHITECTURE" ]; then
    set -- "$@" --machine-architecture "$MACHINE_ARCHITECTURE"
  fi

  if [ -n "$TOOLS_DIR" ]; then
    set -- "$@" --tools-dir "$TOOLS_DIR"
  fi

  set -- "$@" --reuse-tools "$REUSE_TOOLS"

  if [ -n "$JOBS" ]; then
    set -- "$@" --jobs "$JOBS"
  fi

  if [ "$NO_X" = "1" ]; then
    set -- "$@" --no-x
  else
    set -- "$@" --with-x
  fi

  "$SCRIPT_DIR/build-netbsd.sh" "$@"
else
  info "stage: build skipped"
fi

info "stage: publish"

RELEASE_DIR="$OBJ_DIR/releasedir"

"$SCRIPT_DIR/publish-artifacts.sh" \
  --mode "$PUBLISH_MODE" \
  --source-dir "$RELEASE_DIR" \
  --target "$TARGET" \
  --release-id "$RELEASE_ID" \
  --release-tag "${RELEASE_TAG:-}" \
  --machine "$MACHINE" \
  --machine-architecture "$MACHINE_ARCHITECTURE" \
  --platform-key "$PLATFORM_KEY" \
  --base-name "$BASE_NAME" \
  --base-commit "$BASE_COMMIT" \
  --publish-dir "$PUBLISH_DIR" \
  --publish-script "$PUBLISH_SCRIPT" \
  --rsync-dest "$RSYNC_DEST" \
  --rsync-rsh "$RSYNC_RSH"

info "pipeline done"
