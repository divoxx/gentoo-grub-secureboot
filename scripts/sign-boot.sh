#!/usr/bin/env bash
# sign-boot.sh — GPG sign on-disk boot files
#
# Signs all files that GRUB loads from disk:
#   - grub.cfg
#   - kernel-* files
#   - initramfs-*.img files
#   - amd-uc.img (microcode, if present)
#
# Also PE-signs kernel files with sbctl (PE first, then GPG).
#
# Does NOT sign:
#   - EFI binaries in /boot/EFI/ (PE-signed by sbctl, verified by firmware)
#   - System.map-*, config-* (not loaded by GRUB)
#   - .mod files (embedded in standalone binary)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

require_root
load_config

# ---------------------------------------------------------------------------
# Collect files to sign
# ---------------------------------------------------------------------------
collect_files() {
    local esp="$ESP_MOUNT"
    local files=()

    # grub.cfg
    local cfg
    cfg="$(grub_cfg_path)"
    if [[ -f "$cfg" ]]; then
        files+=("$cfg")
    else
        msg_warn "grub.cfg not found at $cfg"
    fi

    # Kernels
    for f in "${esp}"/kernel-*; do
        [[ -f "$f" ]] || continue
        [[ "$f" == *.sig ]] && continue
        files+=("$f")
    done

    # Initramfs
    for f in "${esp}"/initramfs-*.img; do
        [[ -f "$f" ]] || continue
        [[ "$f" == *.sig ]] && continue
        files+=("$f")
    done

    # Microcode
    if [[ -f "${esp}/amd-uc.img" ]]; then
        files+=("${esp}/amd-uc.img")
    fi
    if [[ -f "${esp}/intel-uc.img" ]]; then
        files+=("${esp}/intel-uc.img")
    fi

    printf '%s\n' "${files[@]}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
cleanup_orphaned_sigs() {
    local esp="$ESP_MOUNT"

    for sig in "${esp}"/*.sig "${esp}"/grub/*.sig; do
        [[ -f "$sig" ]] || continue
        local base="${sig%.sig}"
        if [[ ! -f "$base" ]]; then
            msg_info "Removing orphaned signature: $(basename "$sig")"
            rm -f "$sig"
        fi
    done
}

main() {
    msg_info "Signing boot files..."

    # Clean up signatures for removed files
    cleanup_orphaned_sigs

    local files
    mapfile -t files < <(collect_files)

    if [[ ${#files[@]} -eq 0 ]]; then
        msg_error "No boot files found to sign."
        exit 1
    fi

    local signed=0
    local failed=0

    for file in "${files[@]}"; do
        local basename
        basename="$(basename "$file")"

        # PE-sign kernel files with sbctl first (modifies binary)
        if [[ "$basename" == kernel-* ]]; then
            msg_info "PE-signing $basename..."
            if ! sbctl sign -s "$file"; then
                # Distinguish "already signed" from real failure
                if sbctl verify "$file" 2>&1 | grep -q "is signed"; then
                    msg_info "Already PE-signed: $basename"
                else
                    msg_error "PE-signing failed for $basename — aborting"
                    exit 1
                fi
            else
                msg_ok "PE-signed: $basename"
            fi
        fi

        # GPG sign (must be after any PE signing)
        msg_info "GPG-signing $basename..."
        if gpg_sign "$file"; then
            msg_ok "GPG-signed: $basename"
            signed=$((signed + 1))
        else
            msg_error "GPG-sign failed: $basename"
            failed=$((failed + 1))
        fi
    done

    echo ""
    msg_info "--- Signature Summary ---"
    msg_info "Files signed: $signed"
    [[ $failed -gt 0 ]] && msg_error "Files failed: $failed"

    # Verify all signatures
    echo ""
    msg_info "Verifying signatures..."
    local verify_ok=0
    local verify_fail=0

    for file in "${files[@]}"; do
        if gpg_verify "$file"; then
            msg_ok "Verified: $(basename "$file")"
            verify_ok=$((verify_ok + 1))
        else
            msg_error "Verification FAILED: $(basename "$file")"
            verify_fail=$((verify_fail + 1))
        fi
    done

    echo ""
    msg_info "Verified: $verify_ok  Failed: $verify_fail"

    if [[ $verify_fail -gt 0 || $failed -gt 0 ]]; then
        msg_error "Some signatures failed. Do NOT reboot until resolved."
        exit 1
    fi

    msg_ok "All boot files signed and verified."
}

main "$@"
