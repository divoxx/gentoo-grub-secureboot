#!/usr/bin/env bash
# update-boot.sh — Combined boot maintenance command
#
# Run this after:
#   - Kernel updates (also runs automatically via installkernel hook)
#   - Kernel cmdline changes
#   - GRUB config changes
#
# Steps:
#   1. sbctl sign-all  (ensure all PE files are current)
#   2. grub-mkconfig   (regenerate grub.cfg)
#   3. sign-boot.sh    (GPG sign all boot files)
#
# Does NOT rebuild the standalone GRUB binary.
# For that, run build-grub separately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

require_root
load_config

# Prevent concurrent execution
readonly _LOCKFILE="/var/lock/secureboot-update.lock"
exec 9>"$_LOCKFILE"
if ! flock -n 9; then
    msg_error "Another instance of update-boot is running. Aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    msg_info "=== Boot Update ==="
    echo ""

    # 1. PE-sign all enrolled files
    msg_info "Running sbctl sign-all..."
    sbctl sign-all
    msg_ok "PE signatures updated."
    echo ""

    # 2. Regenerate grub.cfg (with rollback on failure)
    local grub_cfg
    grub_cfg="$(grub_cfg_path)"
    msg_info "Regenerating GRUB config..."
    mkdir -p "$(dirname "$grub_cfg")"

    # Back up current signed state
    if [[ -f "$grub_cfg" && -f "${grub_cfg}.sig" ]]; then
        cp "$grub_cfg" "${grub_cfg}.bak"
        cp "${grub_cfg}.sig" "${grub_cfg}.sig.bak"
    fi

    if ! grub-mkconfig -o "$grub_cfg"; then
        msg_error "grub-mkconfig failed — restoring backup"
        if [[ -f "${grub_cfg}.bak" ]]; then
            mv "${grub_cfg}.bak" "$grub_cfg"
            [[ -f "${grub_cfg}.sig.bak" ]] && mv "${grub_cfg}.sig.bak" "${grub_cfg}.sig"
            msg_ok "Backup restored"
        fi
        exit 1
    fi
    msg_ok "GRUB config written to $grub_cfg"
    echo ""

    # 3. GPG sign everything
    msg_info "Signing boot files..."
    if ! "${SCRIPT_DIR}/sign-boot.sh"; then
        msg_error "sign-boot failed — restoring backup"
        if [[ -f "${grub_cfg}.bak" ]]; then
            mv "${grub_cfg}.bak" "$grub_cfg"
            [[ -f "${grub_cfg}.sig.bak" ]] && mv "${grub_cfg}.sig.bak" "${grub_cfg}.sig"
            msg_ok "Backup restored — previous signed state preserved"
        fi
        exit 1
    fi

    # Clean up backups only after everything succeeds
    rm -f "${grub_cfg}.bak" "${grub_cfg}.sig.bak"
    echo ""

    msg_ok "=== Boot update complete ==="
}

main "$@"
