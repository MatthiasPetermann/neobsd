#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

SRC_DIR=""
SRC_REPO="https://github.com/NetBSD/src.git"
XSRC_DIR=""
XSRC_REPO="https://github.com/NetBSD/xsrc.git"
BASE_NAME=""
BASE_COMMIT=""
FETCH_MODE="auto"
USE_X="0"

checkout_xsrc_branch() {
  info "checking out xsrc branch: $BASE_NAME"

  if git -C "$XSRC_DIR" show-ref --verify --quiet "refs/heads/$BASE_NAME"; then
    git -C "$XSRC_DIR" checkout "$BASE_NAME"
    return
  fi

  if git -C "$XSRC_DIR" show-ref --verify --quiet "refs/remotes/origin/$BASE_NAME"; then
    git -C "$XSRC_DIR" checkout -B "$BASE_NAME" "origin/$BASE_NAME"
    return
  fi

  die "xsrc branch not available locally: $BASE_NAME"
}

usage() {
  cat <<EOF
usage: $0 [options]

options:
  --src-dir <path>         path to netbsd-src checkout (required)
  --src-repo <url>         source repository (default: NetBSD/src)
  --xsrc-dir <path>        path to netbsd-xsrc checkout
  --xsrc-repo <url>        xsrc repository (default: NetBSD/xsrc)
  --base-name <name>       base branch name (required)
  --base-commit <sha>      base commit that must exist locally (required)
  --fetch-mode <mode>      auto|none (default: auto)
  --no-x                   do not prepare xsrc
  --with-x                 prepare xsrc checkout
  --help                   show this message
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --src-dir)
      [ "$#" -ge 2 ] || die "missing value for --src-dir"
      SRC_DIR="$2"
      shift 2
      ;;
    --src-repo)
      [ "$#" -ge 2 ] || die "missing value for --src-repo"
      SRC_REPO="$2"
      shift 2
      ;;
    --xsrc-dir)
      [ "$#" -ge 2 ] || die "missing value for --xsrc-dir"
      XSRC_DIR="$2"
      shift 2
      ;;
    --xsrc-repo)
      [ "$#" -ge 2 ] || die "missing value for --xsrc-repo"
      XSRC_REPO="$2"
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
    --fetch-mode)
      [ "$#" -ge 2 ] || die "missing value for --fetch-mode"
      FETCH_MODE="$2"
      shift 2
      ;;
    --no-x)
      USE_X="0"
      shift 1
      ;;
    --with-x)
      USE_X="1"
      shift 1
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

[ -n "$SRC_DIR" ] || die "missing required option: --src-dir"
[ -n "$BASE_NAME" ] || die "missing required option: --base-name"
[ -n "$BASE_COMMIT" ] || die "missing required option: --base-commit"

case "$FETCH_MODE" in
  auto|none)
    ;;
  *)
    die "invalid fetch mode: $FETCH_MODE"
    ;;
esac

if [ ! -d "$SRC_DIR/.git" ]; then
  if [ "$FETCH_MODE" = "none" ]; then
    die "source repo missing and fetch-mode=none: $SRC_DIR"
  fi

  info "cloning netbsd-src"
  git clone "$SRC_REPO" "$SRC_DIR"
fi

if [ "$FETCH_MODE" = "auto" ]; then
  info "fetching base branch: $BASE_NAME"
  git -C "$SRC_DIR" fetch --prune "$SRC_REPO" "$BASE_NAME"
fi

if ! git -C "$SRC_DIR" cat-file -e "$BASE_COMMIT^{commit}" 2>/dev/null; then
  if [ "$FETCH_MODE" = "auto" ]; then
    info "base commit missing locally, fetching complete refs"
    git -C "$SRC_DIR" fetch --prune --tags "$SRC_REPO"
  fi
fi

if ! git -C "$SRC_DIR" cat-file -e "$BASE_COMMIT^{commit}" 2>/dev/null; then
  die "base commit not available after fetch: $BASE_COMMIT"
fi

if [ "$USE_X" = "1" ]; then
  [ -n "$XSRC_DIR" ] || die "--with-x requires --xsrc-dir"

  fetched_xsrc=0

  if [ -d "$XSRC_DIR/.git" ]; then
    if [ "$FETCH_MODE" = "auto" ]; then
      info "fetching xsrc branch: $BASE_NAME"
      if ! git -C "$XSRC_DIR" fetch --prune "$XSRC_REPO" "$BASE_NAME"; then
        log_warn "xsrc branch '$BASE_NAME' fetch failed; fetching full refs"
        git -C "$XSRC_DIR" fetch --prune --tags "$XSRC_REPO"
      else
        fetched_xsrc=1
      fi
    fi
  elif [ -d "$XSRC_DIR" ]; then
    log_warn "xsrc dir exists but is not a git repo: $XSRC_DIR (reuse as-is)"
  else
    if [ "$FETCH_MODE" = "none" ]; then
      die "xsrc repo missing and fetch-mode=none: $XSRC_DIR"
    fi

    info "cloning netbsd-xsrc"
    git clone "$XSRC_REPO" "$XSRC_DIR"

    if [ "$FETCH_MODE" = "auto" ]; then
      info "fetching xsrc branch: $BASE_NAME"
      if ! git -C "$XSRC_DIR" fetch --prune "$XSRC_REPO" "$BASE_NAME"; then
        log_warn "xsrc branch '$BASE_NAME' fetch failed; fetching full refs"
        git -C "$XSRC_DIR" fetch --prune --tags "$XSRC_REPO"
      else
        fetched_xsrc=1
      fi
    fi
  fi

  if [ -d "$XSRC_DIR/.git" ]; then
    if [ "$fetched_xsrc" = "1" ]; then
      info "checking out xsrc branch: $BASE_NAME (fetched)"
      git -C "$XSRC_DIR" checkout -B "$BASE_NAME" FETCH_HEAD
    else
      checkout_xsrc_branch
    fi
  fi
fi
