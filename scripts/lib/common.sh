#!/bin/sh

if [ -n "${SCRIPT_DIR:-}" ]; then
  . "$SCRIPT_DIR/lib/logging.sh"
else
  . "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/logging.sh"
fi

log_init

die() {
  log_die "$@"
}

info() {
  log_info "$@"
}

bool_to_01() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      printf '1\n'
      ;;
    0|false|FALSE|no|NO|off|OFF)
      printf '0\n'
      ;;
    *)
      log_die "invalid boolean value: ${1:-<empty>}"
      ;;
  esac
}
