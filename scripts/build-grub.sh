#!/usr/bin/env bash
# build-grub.sh — Build standalone GRUB EFI binary with embedded GPG key
#
# Run this after:
#   - GRUB package update (emerge sys-boot/grub)
#   - Changes to grub/modules.txt
#   - Changes to grub/initial.cfg.template
#   - GPG key changes
#
# This builds a self-contained GRUB binary with all modules embedded,
# the GPG public key baked in, and signature enforcement enabled.
# The resulting binary is then PE-signed by sbctl for UEFI Secure Boot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

require_root
load_config

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    msg_info "Building standalone GRUB EFI binary..."

    make_tmpdir

    # 1. Export GPG public key
    msg_info "Exporting GPG public key..."
    gpg --batch --yes --export "$GPG_KEY_NAME" > "${_TMPDIR}/grub.pub"

    if [[ ! -s "${_TMPDIR}/grub.pub" ]]; then
        msg_error "GPG public key export is empty. Is the key '$GPG_KEY_NAME' in root's keyring?"
        exit 1
    fi

    # Keep a persistent copy at /root/grub.pub
    cp "${_TMPDIR}/grub.pub" /root/grub.pub
    msg_ok "GPG public key exported to /root/grub.pub"

    # 2. Render initial.cfg from template
    msg_info "Generating initial config..."
    local tpl
    tpl="$(initial_cfg_tpl)"
    if [[ ! -f "$tpl" ]]; then
        msg_error "Initial config template not found: $tpl"
        exit 1
    fi

    sed "s/%%LINUX_ESP_UUID%%/${LINUX_ESP_UUID}/g" "$tpl" \
        > "${_TMPDIR}/initial.cfg"

    # 3. GPG sign the initial config
    msg_info "Signing initial config..."
    gpg_sign "${_TMPDIR}/initial.cfg"

    # 4. Read module list
    local modules
    modules="$(read_modules)"
    msg_info "Modules: ${modules}"

    # 5. Build standalone binary
    local efi_output
    efi_output="$(grub_efi_path)"

    msg_info "Running grub-mkstandalone..."
    mkdir -p "$(dirname "$efi_output")"

    grub-mkstandalone \
        --pubkey "${_TMPDIR}/grub.pub" \
        --directory /usr/lib/grub/x86_64-efi \
        --format x86_64-efi \
        --modules "$modules" \
        --disable-shim-lock \
        --output "$efi_output" \
        "boot/grub/grub.cfg=${_TMPDIR}/initial.cfg" \
        "boot/grub/grub.cfg.sig=${_TMPDIR}/initial.cfg.sig"

    msg_ok "Standalone GRUB binary built: $efi_output"

    # 6. PE-sign with sbctl
    msg_info "PE-signing with sbctl..."
    sbctl sign -s "$efi_output"
    msg_ok "PE-signed: $efi_output"

    # 7. Verify EFI boot entry
    msg_info "Checking EFI boot entries..."
    if efibootmgr | grep -qi "$BOOTLOADER_ID"; then
        msg_ok "EFI boot entry for '${BOOTLOADER_ID}' exists"
    else
        msg_warn "No EFI boot entry found for '${BOOTLOADER_ID}'."
        msg_warn "You may need to create one with efibootmgr."
    fi

    # 8. Quick verification
    msg_info "Verifying embedded signature enforcement..."
    if strings "$efi_output" | grep -q "check_signatures"; then
        msg_ok "check_signatures found in binary"
    else
        msg_warn "check_signatures not found in binary strings"
    fi

    echo ""
    msg_ok "GRUB standalone build complete."
    msg_info "Next: run 'update-boot' to regenerate grub.cfg and sign boot files."
}

main "$@"
