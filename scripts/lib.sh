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

# Try to load config in degraded mode (for audit.sh).
# Returns 0 if loaded, 1 if skipped (with defaults set).
try_load_config() {
    if [[ ! -f "$MACHINE_CONF" ]]; then
        msg_warn "machine.conf not found — using defaults"
        ESP_MOUNT="${ESP_MOUNT:-/boot}"
        BOOTLOADER_ID="${BOOTLOADER_ID:-gentoo}"
        GPG_KEY_NAME="${GPG_KEY_NAME:-grub}"
        return 1
    fi

    local conf_owner conf_perms
    conf_owner="$(stat -c '%u:%g' "$MACHINE_CONF" 2>/dev/null || echo "unknown")"
    conf_perms="$(stat -c '%a' "$MACHINE_CONF" 2>/dev/null || echo "000")"

    if [[ "$conf_owner" != "0:0" ]]; then
        msg_warn "machine.conf not owned by root — skipping (owner: $(stat -c '%U:%G' "$MACHINE_CONF" 2>/dev/null))"
        ESP_MOUNT="${ESP_MOUNT:-/boot}"
        BOOTLOADER_ID="${BOOTLOADER_ID:-gentoo}"
        GPG_KEY_NAME="${GPG_KEY_NAME:-grub}"
        return 1
    fi

    if [[ "$conf_perms" != "600" ]]; then
        msg_warn "machine.conf has unsafe permissions (mode $conf_perms) — skipping"
        ESP_MOUNT="${ESP_MOUNT:-/boot}"
        BOOTLOADER_ID="${BOOTLOADER_ID:-gentoo}"
        GPG_KEY_NAME="${GPG_KEY_NAME:-grub}"
        return 1
    fi

    # shellcheck source=../machine.conf.example
    source "$MACHINE_CONF"
    return 0
}

load_config() {
    if [[ ! -f "$MACHINE_CONF" ]]; then
        msg_error "machine.conf not found at: $MACHINE_CONF"
        msg_error "Copy machine.conf.example to machine.conf and fill in your values."
        exit 1
    fi

    # Verify machine.conf ownership and permissions (sourced as root)
    local conf_owner conf_perms
    conf_owner="$(stat -c '%u:%g' "$MACHINE_CONF")"
    conf_perms="$(stat -c '%a' "$MACHINE_CONF")"
    if [[ "$conf_owner" != "0:0" ]]; then
        msg_error "machine.conf must be owned by root:root (current: $(stat -c '%U:%G' "$MACHINE_CONF"))"
        msg_error "Fix with: chown root:root $MACHINE_CONF"
        exit 1
    fi
    if [[ "$conf_perms" != "600" ]]; then
        msg_error "machine.conf has unsafe permissions (mode $conf_perms, expected 600)"
        msg_error "Fix with: chmod 600 $MACHINE_CONF"
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

    # Validate ESP_MOUNT is an absolute path
    if [[ "$ESP_MOUNT" != /* ]]; then
        msg_error "ESP_MOUNT must be an absolute path: $ESP_MOUNT"
        exit 1
    fi

    # Validate BOOTLOADER_ID format (used in filesystem paths)
    if [[ ! "$BOOTLOADER_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        msg_error "BOOTLOADER_ID contains invalid characters: $BOOTLOADER_ID"
        msg_error "Only alphanumeric, hyphen, and underscore are allowed."
        exit 1
    fi

    # Validate GPG_KEY_NAME is not empty (already caught by _REQUIRED_VARS,
    # but warn if it looks unusual)
    if [[ ! "$GPG_KEY_NAME" =~ ^[a-zA-Z0-9@._-]+$ ]]; then
        msg_warn "GPG_KEY_NAME contains unusual characters: $GPG_KEY_NAME"
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
    local modules
    modules="$(grep -v '^\s*#' "$file" | grep -v '^\s*$' | tr '\n' ' ' | sed 's/ *$//' || true)"
    if [[ -z "$modules" ]]; then
        msg_error "No modules found in $file"
        exit 1
    fi
    # Validate module names contain only safe characters
    local mod
    for mod in $modules; do
        if [[ ! "$mod" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            msg_error "Invalid module name in $file: $mod"
            exit 1
        fi
    done
    echo "$modules"
}

# ---------------------------------------------------------------------------
# GPG signing helper
# ---------------------------------------------------------------------------
gpg_sign() {
    local file="$1"
    local sig="${file}.sig"
    local sig_tmp="${sig}.tmp"

    # Sign to a temporary file first, then atomically move into place.
    # This preserves the old signature if signing fails.
    rm -f "$sig_tmp"
    if gpg --batch --yes --default-key "$GPG_KEY_NAME" --output "$sig_tmp" --detach-sign "$file"; then
        mv -f "$sig_tmp" "$sig"
    else
        rm -f "$sig_tmp"
        return 1
    fi
}

gpg_verify() {
    local file="$1"
    local sig="${file}.sig"

    if [[ ! -f "$sig" ]]; then
        msg_error "Signature missing: $sig"
        return 1
    fi

    local gpg_output
    if ! gpg_output="$(gpg --batch --verify "$sig" "$file" 2>&1)"; then
        msg_error "GPG verification details: $gpg_output"
        return 1
    fi
}
