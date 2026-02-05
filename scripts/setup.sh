#!/usr/bin/env bash
# setup.sh — Interactive first-time setup for gentoo-secureboot
#
# Guides through:
#   1. Prerequisite checks
#   2. Auto-detection of machine values → machine.conf
#   3. GPG key setup
#   4. sbctl key setup
#   5. Running install.sh, build-grub.sh, update-boot.sh, audit.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

require_root

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
prompt_value() {
    local description="$1"
    local default="${2:-}"
    local value

    if [[ -n "$default" ]]; then
        echo -n "  ${description} [${default}]: " >&2
    else
        echo -n "  ${description}: " >&2
    fi
    read -r value
    value="${value:-$default}"
    echo "$value"
}

confirm() {
    local prompt="$1"
    local response
    echo -n "$prompt [y/N]: " >&2
    read -r response
    [[ "$response" =~ ^[Yy] ]]
}

check_command() {
    local cmd="$1"
    local pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        msg_ok "$cmd found"
        return 0
    else
        msg_error "$cmd not found — install $pkg"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# 1. Prerequisite checks
# ---------------------------------------------------------------------------
check_prerequisites() {
    msg_info "=== Checking Prerequisites ==="
    echo ""

    local ok=true

    check_command grub-mkstandalone sys-boot/grub    || ok=false
    check_command sbctl app-crypt/sbctl               || ok=false
    check_command gpg app-crypt/gnupg                 || ok=false
    check_command efibootmgr sys-boot/efibootmgr     || ok=false
    check_command grub-mkconfig sys-boot/grub         || ok=false
    check_command blkid sys-apps/util-linux           || ok=false

    echo ""

    # Check GRUB USE flags
    msg_info "Checking GRUB USE flags..."
    local grub_use
    if grub_use="$(equery -q uses sys-boot/grub 2>/dev/null)"; then
        if echo "$grub_use" | grep -q "+grub_platforms_efi-64"; then
            msg_ok "GRUB platform efi-64 enabled"
        else
            msg_error "GRUB missing USE flag: grub_platforms_efi-64"
            msg_error "Add to /etc/portage/package.use: sys-boot/grub grub_platforms_efi-64"
            ok=false
        fi

        if echo "$grub_use" | grep -q "+device-mapper"; then
            msg_ok "GRUB device-mapper support enabled"
        else
            msg_warn "GRUB device-mapper USE flag not set (needed for LUKS/LVM)"
        fi
    else
        msg_warn "Cannot check USE flags (equery not available)"
        msg_info "Ensure sys-boot/grub has USE: grub_platforms_efi-64 device-mapper"
    fi

    echo ""
    if [[ "$ok" == false ]]; then
        msg_error "Missing prerequisites. Install required packages and re-run setup."
        exit 1
    fi
    msg_ok "All prerequisites met."
}

# ---------------------------------------------------------------------------
# 2. Generate machine.conf
# ---------------------------------------------------------------------------
generate_machine_conf() {
    msg_info "=== Configuring machine.conf ==="
    echo ""

    if [[ -f "$MACHINE_CONF" ]]; then
        msg_info "machine.conf already exists."
        if ! confirm "  Overwrite?"; then
            msg_info "Keeping existing machine.conf"
            return
        fi
    fi

    # Auto-detect values
    msg_info "Auto-detecting disk layout..."
    echo ""

    # Find FAT32 partitions (ESPs)
    msg_info "FAT32 partitions found:"
    blkid -t TYPE=vfat -o list 2>/dev/null || true
    echo ""

    local linux_esp_uuid
    linux_esp_uuid="$(prompt_value "Linux ESP UUID (FAT32 fs UUID)" "")"

    local linux_esp_partuuid
    linux_esp_partuuid="$(prompt_value "Linux ESP PARTUUID" "")"

    local windows_esp_uuid
    windows_esp_uuid="$(prompt_value "Windows ESP UUID (empty if no Windows)" "")"

    echo ""

    # LUKS
    msg_info "LUKS partitions found:"
    blkid -t TYPE=crypto_LUKS -o list 2>/dev/null || true
    echo ""

    local luks_uuid
    luks_uuid="$(prompt_value "LUKS UUID (empty if no encryption)" "")"

    local luks_mapping="gentoo-lvm"
    local luks_discards="true"
    if [[ -n "$luks_uuid" ]]; then
        luks_mapping="$(prompt_value "LUKS mapping name" "gentoo-lvm")"
        luks_discards="$(prompt_value "Allow LUKS discards (true/false)" "true")"
    fi

    echo ""

    # LVM
    local lvm_vg="" lvm_lv_root="" lvm_lv_swap=""
    if command -v lvs &>/dev/null; then
        msg_info "LVM volumes found:"
        lvs 2>/dev/null || true
        echo ""
    fi

    lvm_vg="$(prompt_value "LVM volume group (empty if no LVM)" "")"
    if [[ -n "$lvm_vg" ]]; then
        lvm_lv_root="$(prompt_value "Root LV name" "root")"
        lvm_lv_swap="$(prompt_value "Swap LV name (empty if none)" "swap")"
    fi

    echo ""

    # Filesystem
    local root_fstype
    root_fstype="$(prompt_value "Root filesystem type" "xfs")"

    local root_mount_options
    root_mount_options="$(prompt_value "Root mount options (empty for defaults)" "")"

    echo ""

    # Kernel cmdline extras
    local extra_cmdline
    extra_cmdline="$(prompt_value "Extra kernel cmdline params" "")"

    local cmdline_default
    cmdline_default="$(prompt_value "GRUB_CMDLINE_LINUX_DEFAULT" "quiet systemd.show_status=y")"

    echo ""

    # GRUB
    local bootloader_id
    bootloader_id="$(prompt_value "UEFI boot entry name" "gentoo")"

    local esp_mount
    esp_mount="$(prompt_value "ESP mount point" "/boot")"

    # GPG
    local gpg_key_name
    gpg_key_name="$(prompt_value "GPG key UID for signing" "grub")"

    echo ""

    # Write machine.conf using printf to avoid shell expansion of user input
    msg_info "Writing machine.conf..."
    local _generated_date
    _generated_date="$(date -Iseconds)"
    cat > "$MACHINE_CONF" << 'CONFEOF'
# gentoo-secureboot machine configuration
# Generated by setup.sh
CONFEOF
    {
        printf '# Generated on %s\n\n' "$_generated_date"
        printf '# Disk Identifiers\n'
        printf 'LINUX_ESP_UUID="%s"\n' "$linux_esp_uuid"
        printf 'LINUX_ESP_PARTUUID="%s"\n' "$linux_esp_partuuid"
        printf 'WINDOWS_ESP_UUID="%s"\n\n' "$windows_esp_uuid"
        printf '# LUKS / LVM\n'
        printf 'LUKS_UUID="%s"\n' "$luks_uuid"
        printf 'LUKS_MAPPING_NAME="%s"\n' "$luks_mapping"
        printf 'LUKS_ALLOW_DISCARDS="%s"\n' "$luks_discards"
        printf 'LVM_VG="%s"\n' "$lvm_vg"
        printf 'LVM_LV_ROOT="%s"\n' "$lvm_lv_root"
        printf 'LVM_LV_SWAP="%s"\n\n' "$lvm_lv_swap"
        printf '# Root Filesystem\n'
        printf 'ROOT_FSTYPE="%s"\n' "$root_fstype"
        printf 'ROOT_MOUNT_OPTIONS="%s"\n\n' "$root_mount_options"
        printf '# Kernel Command Line\n'
        printf 'EXTRA_CMDLINE="%s"\n' "$extra_cmdline"
        printf 'CMDLINE_DEFAULT="%s"\n\n' "$cmdline_default"
        printf '# GRUB\n'
        printf 'BOOTLOADER_ID="%s"\n' "$bootloader_id"
        printf 'ESP_MOUNT="%s"\n\n' "$esp_mount"
        printf '# GPG\n'
        printf 'GPG_KEY_NAME="%s"\n' "$gpg_key_name"
    } >> "$MACHINE_CONF"

    chmod 600 "$MACHINE_CONF"
    msg_ok "machine.conf written"

    # Validate required fields are present
    load_config
}

# ---------------------------------------------------------------------------
# 3. GPG key setup
# ---------------------------------------------------------------------------
setup_gpg_key() {
    msg_info "=== GPG Key Setup ==="
    echo ""

    # Load config to get GPG_KEY_NAME (with validation)
    load_config

    if gpg --list-keys "$GPG_KEY_NAME" &>/dev/null; then
        msg_ok "GPG key '$GPG_KEY_NAME' found in root keyring"
    else
        msg_info "GPG key '$GPG_KEY_NAME' not found."
        if confirm "  Create a new GPG key for GRUB signing?"; then
            msg_info "Generating RSA 4096 key (no passphrase for automation)..."
            gpg --batch --gen-key <<GPGEOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: ${GPG_KEY_NAME}
Name-Email: ${GPG_KEY_NAME}-secureboot@localhost
Name-Comment: GRUB Secure Boot signing key
%commit
GPGEOF
            msg_ok "GPG key created"
        else
            msg_error "GPG key required. Create one manually and re-run setup."
            exit 1
        fi
    fi

    # Export public key
    gpg --batch --yes --export "$GPG_KEY_NAME" > /root/grub.pub
    msg_ok "GPG public key exported to /root/grub.pub"
}

# ---------------------------------------------------------------------------
# 4. sbctl key setup
# ---------------------------------------------------------------------------
setup_sbctl() {
    msg_info "=== Secure Boot Key Setup (sbctl) ==="
    echo ""

    local sb_status
    sb_status="$(sbctl status 2>&1)" || true

    if echo "$sb_status" | grep -q "Setup Mode"; then
        if echo "$sb_status" | grep -q "Setup Mode:.*Enabled"; then
            msg_info "Firmware is in Setup Mode — good for initial enrollment"
        fi
    fi

    # Check if sbctl keys exist
    if [[ -d /usr/share/secureboot/keys ]]; then
        msg_ok "sbctl keys found"
    else
        msg_info "sbctl keys not found."
        if confirm "  Create new sbctl keys?"; then
            sbctl create-keys
            msg_ok "sbctl keys created"
        else
            msg_error "sbctl keys required. Run 'sbctl create-keys' and re-run setup."
            exit 1
        fi
    fi

    # Enroll keys
    if confirm "  Enroll keys with Microsoft certificates? (required for Windows dual-boot)"; then
        sbctl enroll-keys --microsoft
        msg_ok "Keys enrolled with Microsoft certificates"
    else
        msg_info "Skipping key enrollment. Run 'sbctl enroll-keys --microsoft' when ready."
    fi
}

# ---------------------------------------------------------------------------
# 5. Run installation and build
# ---------------------------------------------------------------------------
run_installation() {
    msg_info "=== Running Installation ==="
    echo ""

    msg_info "Running install.sh..."
    "${SCRIPT_DIR}/install.sh"
    echo ""

    msg_info "Running build-grub.sh..."
    "${SCRIPT_DIR}/build-grub.sh"
    echo ""

    msg_info "Running update-boot.sh..."
    "${SCRIPT_DIR}/update-boot.sh"
    echo ""

    # Run audit if available
    if [[ -x "${SCRIPT_DIR}/audit.sh" ]]; then
        msg_info "Running audit..."
        "${SCRIPT_DIR}/audit.sh" || true
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    msg_info "========================================="
    msg_info "  gentoo-secureboot — First-Time Setup"
    msg_info "========================================="
    echo ""

    check_prerequisites
    echo ""
    generate_machine_conf
    echo ""
    setup_gpg_key
    echo ""
    setup_sbctl
    echo ""
    run_installation

    echo ""
    msg_ok "========================================="
    msg_ok "  Setup Complete!"
    msg_ok "========================================="
    echo ""
    msg_info "Next steps:"
    msg_info "  1. Reboot and verify Linux boots correctly"
    msg_info "  2. Verify Windows boots correctly (if dual-booting)"
    msg_info "  3. Run 'audit-secureboot' to verify everything"
    echo ""
    msg_info "Maintenance commands:"
    msg_info "  update-boot       — After kernel updates or config changes"
    msg_info "  build-grub        — After GRUB package updates"
    msg_info "  sign-boot         — Re-sign boot files only"
    msg_info "  audit-secureboot  — Health check"
}

main "$@"
