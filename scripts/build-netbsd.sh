#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

STEPS="all"
SRC_DIR="."
MACHINE="${MACHINE:-amd64}"
MACHINE_ARCHITECTURE="${MACHINE_ARCHITECTURE:-}"
XSRC_DIR="${XSRC_DIR:-${XSRCDIR:-../netbsd-xsrc}}"
OBJ_DIR="${OBJ_DIR:-${OBJDIR:-../obj}}"
TOOLS_DIR="${TOOLS_DIR:-${TOOLDIR:-}}"
NO_X="${NO_X:-1}"
JOBS="${JOBS:-}"
REUSE_TOOLS="${REUSE_TOOLS:-0}"

detect_jobs() {
  if command -v getconf >/dev/null 2>&1; then
    n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
      printf '%s\n' "$n"
      return
    fi
  fi

  if command -v nproc >/dev/null 2>&1; then
    n="$(nproc 2>/dev/null || true)"
    if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
      printf '%s\n' "$n"
      return
    fi
  fi

  if command -v sysctl >/dev/null 2>&1; then
    n="$(sysctl -n hw.ncpu 2>/dev/null || true)"
    if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
      printf '%s\n' "$n"
      return
    fi
  fi

  printf '1\n'
}

usage() {
  cat <<EOF
usage: $0 [options]

options:
  --src-dir <path>      path to netbsd src checkout (default: .)
  --steps <names>       space-separated list: tools|release|sourcesets|iso-image|install-image|all (default: all)
  --machine <name>      NetBSD MACHINE (default: amd64)
  --machine-architecture <name>
                        NetBSD MACHINE_ARCH (optional)
  --obj-dir <path>      object directory (default: ../obj)
  --xsrc-dir <path>     netbsd-xsrc directory (default: ../netbsd-xsrc)
  --tools-dir <path>    explicit tooldir path (optional)
  --reuse-tools <bool>  skip tools build if tools already exist (default: 0)
  --jobs <n>            build parallelism (default: auto-detect)
  --no-x                build without X11 (default)
  --with-x              build with X11 (passes -x and uses --xsrc-dir)
  --help                show this message
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --src-dir)
      [ "$#" -ge 2 ] || die "missing value for --src-dir"
      SRC_DIR="$2"
      shift 2
      ;;
    --steps)
      [ "$#" -ge 2 ] || die "missing value for --steps"
      STEPS="$2"
      shift 2
      ;;
    --step)
      die "option removed: --step (use --steps)"
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
    --obj-dir)
      [ "$#" -ge 2 ] || die "missing value for --obj-dir"
      OBJ_DIR="$2"
      shift 2
      ;;
    --xsrc-dir)
      [ "$#" -ge 2 ] || die "missing value for --xsrc-dir"
      XSRC_DIR="$2"
      shift 2
      ;;
    --tools-dir)
      [ "$#" -ge 2 ] || die "missing value for --tools-dir"
      TOOLS_DIR="$2"
      shift 2
      ;;
    --reuse-tools)
      [ "$#" -ge 2 ] || die "missing value for --reuse-tools"
      REUSE_TOOLS="$(bool_to_01 "$2")"
      shift 2
      ;;
    --jobs)
      [ "$#" -ge 2 ] || die "missing value for --jobs"
      JOBS="$2"
      shift 2
      ;;
    --no-x)
      NO_X="1"
      shift 1
      ;;
    --with-x)
      NO_X="0"
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

if [ -z "$JOBS" ]; then
  JOBS="$(detect_jobs)"
fi

REUSE_TOOLS="$(bool_to_01 "$REUSE_TOOLS")"

normalize_step_name() {
  case "$1" in
    iso)
      printf 'iso-image\n'
      ;;
    install)
      printf 'install-image\n'
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

validate_step_name() {
  case "$1" in
    tools|release|sourcesets|iso-image|install-image|all)
      ;;
    *)
      die "invalid step: $1"
      ;;
  esac
}

resolve_steps() {
  raw_steps="$1"
  resolved_steps=""
  saw_all="0"

  for raw_step in $raw_steps; do
    step_name="$(normalize_step_name "$raw_step")"
    validate_step_name "$step_name"

    if [ "$step_name" = "all" ]; then
      if [ -n "$resolved_steps" ]; then
        die "step 'all' cannot be combined with other steps"
      fi

      resolved_steps="tools release sourcesets iso-image install-image"
      saw_all="1"
      continue
    fi

    if [ "$saw_all" = "1" ]; then
      die "step 'all' cannot be combined with other steps"
    fi

    if [ -n "$resolved_steps" ]; then
      resolved_steps="$resolved_steps $step_name"
    else
      resolved_steps="$step_name"
    fi
  done

  [ -n "$resolved_steps" ] || die "missing build steps"
  printf '%s\n' "$resolved_steps"
}

STEPS="$(resolve_steps "$STEPS")"

[ -f "$SRC_DIR/build.sh" ] || die "must point --src-dir to a netbsd src directory"

if [ "$NO_X" = "0" ] && [ ! -d "$XSRC_DIR" ]; then
  die "--with-x requires an existing xsrc directory: $XSRC_DIR"
fi

if [ "$REUSE_TOOLS" = "1" ] && [ -z "$TOOLS_DIR" ]; then
  die "--reuse-tools requires --tools-dir"
fi

if [ -n "$TOOLS_DIR" ]; then
  mkdir -p "$TOOLS_DIR"
fi

info "machine: $MACHINE"
info "machine architecture: ${MACHINE_ARCHITECTURE:-<default>}"
info "jobs: $JOBS"
info "obj: $OBJ_DIR"
info "tools: ${TOOLS_DIR:-<auto>}"
info "reuse_tools: $REUSE_TOOLS"
info "no_x: $NO_X"
info "xsrc: $XSRC_DIR"
info "steps: $STEPS"

run_step() {
  step_name="$1"

  info "$step_name"

  set -- \
    -m "$MACHINE" \
    -O "$OBJ_DIR" \
    -j "$JOBS" \
    -U

  if [ -n "$MACHINE_ARCHITECTURE" ]; then
    set -- "$@" -a "$MACHINE_ARCHITECTURE"
  fi

  if [ -n "$TOOLS_DIR" ]; then
    set -- "$@" -T "$TOOLS_DIR"
  fi

  if [ "$NO_X" = "0" ]; then
    set -- "$@" -x
  fi

  if [ -d "$XSRC_DIR" ]; then
    set -- "$@" -X "$XSRC_DIR"
  fi

  if [ "$step_name" = "tools" ] && [ "$REUSE_TOOLS" = "1" ]; then
    if [ -d "$TOOLS_DIR/bin" ]; then
      for tool in "$TOOLS_DIR/bin/nbmake" "$TOOLS_DIR/bin/nbmake-$MACHINE" "$TOOLS_DIR/bin/nbmake."*; do
        if [ -x "$tool" ]; then
          info "reusing tools from: $TOOLS_DIR"
          return
        fi
      done
    fi

    info "tools reuse requested, but no reusable tools found in: $TOOLS_DIR"
  fi

  "$SRC_DIR/build.sh" "$@" "$step_name"
}

for step_name in $STEPS; do
  run_step "$step_name"
done

info "done"
