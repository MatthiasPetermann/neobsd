#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/lib/common.sh"

TARGET=""
SRC_DIR=""
TARGETS_DIR="$ROOT/targets"
PATCH_DIR="$ROOT/patches"
SERIES_FILE=""
BASE_NAME=""
BASE_COMMIT=""
BRANCH_NAME="build"
DO_VALIDATE="1"
CHECK_PREFIX_ORDER="1"

usage() {
  cat <<EOF
usage: $0 [options]

options:
  --target <name>               target in targets/<name> (required)
  --src-dir <path>              netbsd src git checkout (required)
  --targets-dir <path>          targets directory (default: $ROOT/targets)
  --patch-dir <path>            patches directory (default: $ROOT/patches)
  --series-file <path>          explicit series file (default: targets/<target>/series)
  --base-name <name>            base name fallback for patches (default: targets/<target>/base)
  --base-commit <sha>           base commit to reset/apply onto (default: targets/<target>/commit)
  --branch <name>               branch to reset/recreate (default: build)
  --validate-series <bool>      run validate-series before applying (default: 1)
  --check-prefix-order <bool>   enforce non-decreasing prefixes in validation (default: 1)
  --help                        show this message

bool values:
  1|0, true|false, yes|no, on|off
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      [ "$#" -ge 2 ] || die "missing value for --target"
      TARGET="$2"
      shift 2
      ;;
    --src-dir)
      [ "$#" -ge 2 ] || die "missing value for --src-dir"
      SRC_DIR="$2"
      shift 2
      ;;
    --targets-dir)
      [ "$#" -ge 2 ] || die "missing value for --targets-dir"
      TARGETS_DIR="$2"
      shift 2
      ;;
    --patch-dir)
      [ "$#" -ge 2 ] || die "missing value for --patch-dir"
      PATCH_DIR="$2"
      shift 2
      ;;
    --series-file)
      [ "$#" -ge 2 ] || die "missing value for --series-file"
      SERIES_FILE="$2"
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
    --branch)
      [ "$#" -ge 2 ] || die "missing value for --branch"
      BRANCH_NAME="$2"
      shift 2
      ;;
    --validate-series)
      [ "$#" -ge 2 ] || die "missing value for --validate-series"
      DO_VALIDATE="$(bool_to_01 "$2")"
      shift 2
      ;;
    --check-prefix-order)
      [ "$#" -ge 2 ] || die "missing value for --check-prefix-order"
      CHECK_PREFIX_ORDER="$(bool_to_01 "$2")"
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
[ -n "$SRC_DIR" ] || die "missing required option: --src-dir"

TARGET_DIR="$TARGETS_DIR/$TARGET"

if [ -z "$SERIES_FILE" ]; then
  SERIES_FILE="$TARGET_DIR/series"
fi

if [ -z "$BASE_NAME" ]; then
  BASE_FILE="$TARGET_DIR/base"
  [ -f "$BASE_FILE" ] || die "missing base mapping file: $BASE_FILE"
  BASE_NAME="$(tr -d '\r\n' < "$BASE_FILE")"
fi

if [ -z "$BASE_COMMIT" ]; then
  COMMIT_FILE="$TARGET_DIR/commit"
  [ -f "$COMMIT_FILE" ] || die "missing commit file: $COMMIT_FILE"
  BASE_COMMIT="$(tr -d '\r\n' < "$COMMIT_FILE")"
fi

if [ "$DO_VALIDATE" = "1" ]; then
  "$SCRIPT_DIR/validate-series.sh" \
    --target "$TARGET" \
    --targets-dir "$TARGETS_DIR" \
    --patch-dir "$PATCH_DIR" \
    --series-file "$SERIES_FILE" \
    --base-name "$BASE_NAME" \
    --check-prefix-order "$CHECK_PREFIX_ORDER"
fi

info "target: $TARGET"
info "source: $SRC_DIR"
info "base name: $BASE_NAME"
info "base commit: $BASE_COMMIT"

[ -d "$SRC_DIR/.git" ] || die "$SRC_DIR is not a git repository"
[ -f "$SERIES_FILE" ] || die "missing series file: $SERIES_FILE"

if ! git -C "$SRC_DIR" cat-file -e "$BASE_COMMIT^{commit}" 2>/dev/null; then
  die "base commit not found locally: $BASE_COMMIT"
fi

info "preparing working tree"
git -C "$SRC_DIR" checkout -f -B "$BRANCH_NAME" "$BASE_COMMIT"
git -C "$SRC_DIR" reset --hard "$BASE_COMMIT"
git -C "$SRC_DIR" clean -fdx

info "applying patches"

i=1
while IFS= read -r entry || [ -n "$entry" ]; do
  case "$entry" in
    ''|\#*)
      continue
      ;;
  esac

  patch_base="$PATCH_DIR/$entry/$BASE_NAME.patch"

  if [ -f "$patch_base" ]; then
    patch_file="$patch_base"
  else
    die "missing patch: $patch_base"
  fi

  printf '  [%03d] %s\n' "$i" "$entry" >&2

  if ! git -C "$SRC_DIR" am "$patch_file"; then
    die "failed to apply patch: $entry (hint: git -C \"$SRC_DIR\" am --abort)"
  fi

  i=$((i + 1))
done < "$SERIES_FILE"

info "done"
info "resulting HEAD: $(git -C "$SRC_DIR" rev-parse HEAD)"
