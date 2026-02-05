#!/usr/bin/env bash
# lib.sh — Shared utilities for gentoo-secureboot scripts
# Sourced by all scripts; do not execute directly.

# Strict mode
set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------
# Resolve REPO_ROOT by following symlinks (scripts may be symlinked from
# /usr/local/sbin/ into this repo).
_resolve_repo_root() {
    local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    # Follow symlinks to find the real script location
    while [[ -L "$source" ]]; do
        local dir
        dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        # Resolve relative symlinks
        [[ "$source" != /* ]] && source="$dir/$source"
    done
    local script_dir
    script_dir="$(cd -P "$(dirname "$source")" && pwd)"
    # lib.sh is in scripts/, so REPO_ROOT is one level up
    cd -P "$script_dir/.." && pwd
}

REPO_ROOT="$(_resolve_repo_root)"
readonly REPO_ROOT

# ---------------------------------------------------------------------------
# Color output (auto-detect tty)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly _CLR_RED=$'\033[0;31m'
    readonly _CLR_GREEN=$'\033[0;32m'
    readonly _CLR_YELLOW=$'\033[0;33m'
    readonly _CLR_BLUE=$'\033[0;34m'
    readonly _CLR_BOLD=$'\033[1m'
    readonly _CLR_RESET=$'\033[0m'
else
    readonly _CLR_RED=''
    readonly _CLR_GREEN=''
    readonly _CLR_YELLOW=''
    readonly _CLR_BLUE=''
    readonly _CLR_BOLD=''
    readonly _CLR_RESET=''
fi

msg_info()  { echo "${_CLR_BLUE}::${_CLR_RESET} $*"; }
msg_ok()    { echo "${_CLR_GREEN}OK${_CLR_RESET} $*"; }
msg_warn()  { echo "${_CLR_YELLOW}WARNING${_CLR_RESET} $*" >&2; }
msg_error() { echo "${_CLR_RED}ERROR${_CLR_RESET} $*" >&2; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_error "This script must be run as root."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Temp file management (trap-based cleanup)
# ---------------------------------------------------------------------------
_TMPDIR=""

make_tmpdir() {
    _TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/secureboot.XXXXXXXXXX")"
    trap '_cleanup_tmp' EXIT INT TERM
}

_cleanup_tmp() {
    if [[ -n "$_TMPDIR" && -d "$_TMPDIR" ]]; then
        rm -rf "$_TMPDIR"
    fi
}

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------
readonly MACHINE_CONF="${REPO_ROOT}/machine.conf"

# Required variables that must be set (non-empty) in machine.conf
readonly _REQUIRED_VARS=(
    LINUX_ESP_UUID
    BOOTLOADER_ID
    ESP_MOUNT
    GPG_KEY_NAME
)

load_config() {
    if [[ ! -f "$MACHINE_CONF" ]]; then
        msg_error "machine.conf not found at: $MACHINE_CONF"
        msg_error "Copy machine.conf.example to machine.conf and fill in your values."
        exit 1
    fi

    # shellcheck source=../machine.conf.example
    source "$MACHINE_CONF"

    local missing=()
    for var in "${_REQUIRED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        msg_error "machine.conf is missing required values:"
        for var in "${missing[@]}"; do
            msg_error "  $var"
        done
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Common paths (available after load_config)
# ---------------------------------------------------------------------------
grub_efi_path()   { echo "${ESP_MOUNT}/EFI/${BOOTLOADER_ID}/grubx64.efi"; }
grub_cfg_path()   { echo "${ESP_MOUNT}/grub/grub.cfg"; }
modules_file()    { echo "${REPO_ROOT}/grub/modules.txt"; }
initial_cfg_tpl() { echo "${REPO_ROOT}/grub/initial.cfg.template"; }

# ---------------------------------------------------------------------------
# Module list reader
# ---------------------------------------------------------------------------
# Reads grub/modules.txt, strips comments and blank lines, returns
# space-separated module list.
read_modules() {
    local file
    file="$(modules_file)"
    if [[ ! -f "$file" ]]; then
        msg_error "Module list not found: $file"
        exit 1
    fi
    grep -v '^\s*#' "$file" | grep -v '^\s*$' | tr '\n' ' ' | sed 's/ *$//'
}

# ---------------------------------------------------------------------------
# GPG signing helper
# ---------------------------------------------------------------------------
gpg_sign() {
    local file="$1"
    local sig="${file}.sig"

    # Remove old signature if it exists
    [[ -f "$sig" ]] && rm -f "$sig"

    gpg --batch --yes --default-key "$GPG_KEY_NAME" --detach-sign "$file"
}

gpg_verify() {
    local file="$1"
    local sig="${file}.sig"

    if [[ ! -f "$sig" ]]; then
        msg_error "Signature missing: $sig"
        return 1
    fi

    gpg --batch --verify "$sig" "$file" 2>/dev/null
}
