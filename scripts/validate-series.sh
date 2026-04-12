#!/bin/sh
set -eu

LC_ALL=C
export LC_ALL

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/lib/common.sh"

TARGET=""
TARGETS_DIR="$ROOT/targets"
PATCH_DIR="$ROOT/patches"
SERIES_FILE=""
BASE_NAME=""
CHECK_PREFIX_ORDER="1"
REQUIRE_PREFIX="1"

usage() {
  cat <<EOF
usage: $0 [options]

options:
  --target <name>               target name (required)
  --targets-dir <path>          targets directory (default: $ROOT/targets)
  --patch-dir <path>            patches directory (default: $ROOT/patches)
  --series-file <path>          explicit series file (default: targets/<target>/series)
  --base-name <name>            base patch fallback name (default: targets/<target>/base)
  --check-prefix-order <bool>   enforce non-decreasing numeric prefixes (default: 1)
  --require-prefix <bool>       require NNNN- prefix in entry basename (default: 1)
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
    --check-prefix-order)
      [ "$#" -ge 2 ] || die "missing value for --check-prefix-order"
      CHECK_PREFIX_ORDER="$(bool_to_01 "$2")"
      shift 2
      ;;
    --require-prefix)
      [ "$#" -ge 2 ] || die "missing value for --require-prefix"
      REQUIRE_PREFIX="$(bool_to_01 "$2")"
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

if [ -z "$SERIES_FILE" ]; then
  SERIES_FILE="$TARGETS_DIR/$TARGET/series"
fi

if [ -z "$BASE_NAME" ]; then
  BASE_FILE="$TARGETS_DIR/$TARGET/base"
  [ -f "$BASE_FILE" ] || die "missing base file: $BASE_FILE"
  BASE_NAME="$(tr -d '\r\n' < "$BASE_FILE")"
fi

[ -f "$SERIES_FILE" ] || die "missing series file: $SERIES_FILE"
[ -d "$PATCH_DIR" ] || die "missing patch directory: $PATCH_DIR"

line_no=0
count=0
seen_entries=''
prev_prefix=''

while IFS= read -r entry || [ -n "$entry" ]; do
  line_no=$((line_no + 1))

  case "$entry" in
    ''|\#*)
      continue
      ;;
  esac

  case "$entry" in
    /*)
      die "series line $line_no: entry must be relative: $entry"
      ;;
    *'..'*)
      die "series line $line_no: entry must not contain '..': $entry"
      ;;
  esac

  case "$seen_entries" in
    *"
$entry
"*)
      die "series line $line_no: duplicate entry: $entry"
      ;;
  esac
  seen_entries="$seen_entries
$entry
"

  patch_base="$PATCH_DIR/$entry/$BASE_NAME.patch"

  if [ ! -f "$patch_base" ]; then
    die "series line $line_no: missing patch: $patch_base"
  fi

  base_name="${entry##*/}"
  case "$base_name" in
    [0-9][0-9][0-9][0-9]-*)
      prefix="${base_name%%-*}"

      if [ "$CHECK_PREFIX_ORDER" = "1" ] && [ -n "$prev_prefix" ]; then
        if [ "$prefix" \< "$prev_prefix" ]; then
          die "series line $line_no: decreasing prefix $prefix after $prev_prefix"
        fi
      fi

      prev_prefix="$prefix"
      ;;
    *)
      if [ "$REQUIRE_PREFIX" = "1" ]; then
        die "series line $line_no: basename must start with NNNN-: $entry"
      fi
      ;;
  esac

  count=$((count + 1))
done < "$SERIES_FILE"

info "validated target: $TARGET"
info "series file: $SERIES_FILE"
info "entries: $count"
info "base fallback: $BASE_NAME"
