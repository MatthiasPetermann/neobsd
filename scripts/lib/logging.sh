#!/bin/sh
# Shared logging helpers for shell scripts.
#
# Usage:
#   . /path/to/lib/logging.sh
#   log_init
#   section "Preflight"
#   log_info "Starting"
#   log_ok "Done"
#   log_warn "Caution"
#   log_err "Failure"
#   log_die "Fatal"   # logs error and exits 1

# Initialize color sequences.
# Colors are enabled only for interactive stderr by default.
# Set LOG_FORCE_COLOR=1 to force colors.
log_init() {
    if [ "${LOG_FORCE_COLOR:-0}" -eq 1 ] || [ -t 2 ]; then
        LOG_C_RST="$(printf '\033[0m')"
        LOG_C_DIM="$(printf '\033[2m')"
        LOG_C_INF="$(printf '\033[1;34m')"
        LOG_C_OK="$(printf '\033[1;32m')"
        LOG_C_WRN="$(printf '\033[1;33m')"
        LOG_C_ERR="$(printf '\033[1;31m')"
    else
        LOG_C_RST=""
        LOG_C_DIM=""
        LOG_C_INF=""
        LOG_C_OK=""
        LOG_C_WRN=""
        LOG_C_ERR=""
    fi
}

section() {
    printf '\n%s== %s ==%s\n' "$LOG_C_DIM" "$*" "$LOG_C_RST" >&2
}

log_info() {
    printf '%s[INFO]%s %s\n' "$LOG_C_INF" "$LOG_C_RST" "$*" >&2
}

log_ok() {
    printf '%s[ OK ]%s %s\n' "$LOG_C_OK" "$LOG_C_RST" "$*" >&2
}

log_warn() {
    printf '%s[WARN]%s %s\n' "$LOG_C_WRN" "$LOG_C_RST" "$*" >&2
}

log_err() {
    printf '%s[ERR ]%s %s\n' "$LOG_C_ERR" "$LOG_C_RST" "$*" >&2
}

log_die() {
    log_err "$*"
    exit 1
}
