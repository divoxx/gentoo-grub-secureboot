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

    # 2. Regenerate grub.cfg
    local grub_cfg
    grub_cfg="$(grub_cfg_path)"
    msg_info "Regenerating GRUB config..."
    mkdir -p "$(dirname "$grub_cfg")"
    grub-mkconfig -o "$grub_cfg"
    msg_ok "GRUB config written to $grub_cfg"
    echo ""

    # 3. GPG sign everything
    msg_info "Signing boot files..."
    "${SCRIPT_DIR}/sign-boot.sh"
    echo ""

    msg_ok "=== Boot update complete ==="
}

main "$@"
