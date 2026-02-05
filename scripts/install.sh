#!/usr/bin/env bash
# install.sh — Install/symlink repo files into system paths
#
# This script:
#   1. Installs 26_windows (with baked-in UUID) to /etc/grub.d/
#   2. Creates symlinks in /usr/local/sbin/ for main commands
#   3. Installs the installkernel hook
#   4. Configures /etc/default/grub settings
#
# Safe to run multiple times (idempotent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

require_root
load_config

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Set a key=value in /etc/default/grub. If the key exists (even commented),
# replace it. Otherwise append it.
grub_default_set() {
    local key="$1"
    local value="$2"
    local file="${3:-/etc/default/grub}"

    # Escape key for use in regex (handle potential metacharacters)
    local escaped_key
    escaped_key="$(printf '%s' "$key" | sed 's/[.[\*^$()+?{|]/\\&/g')"

    # Escape value for sed replacement (handle &, \, and | delimiter)
    local escaped_value
    escaped_value="$(printf '%s' "$value" | sed 's/[&\\/|]/\\&/g')"

    if grep -qE "^#?\s*${escaped_key}=" "$file" 2>/dev/null; then
        # Replace first matching line only (commented or not)
        sed -i "0,/^#\?\s*${escaped_key}=/{s|^#\?\s*${escaped_key}=.*|${key}=${escaped_value}|}" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# Remove a key from /etc/default/grub
grub_default_remove() {
    local key="$1"
    local file="${2:-/etc/default/grub}"

    local escaped_key
    escaped_key="$(printf '%s' "$key" | sed 's/[.[\*^$()+?{|]/\\&/g')"

    if grep -qE "^#?\s*${escaped_key}=" "$file" 2>/dev/null; then
        sed -i "/^#\?\s*${escaped_key}=/d" "$file"
        msg_info "Removed $key from /etc/default/grub"
    fi
}

# Create a symlink, replacing existing if needed
install_symlink() {
    local target="$1"
    local link="$2"

    if [[ -L "$link" ]]; then
        local current
        current="$(readlink "$link")"
        if [[ "$current" == "$target" ]]; then
            msg_ok "Symlink already correct: $link"
            return
        fi
        rm -f "$link"
    elif [[ -e "$link" ]]; then
        msg_warn "$link exists and is not a symlink — backing up"
        mv "$link" "${link}.bak"
    fi

    ln -s "$target" "$link"
    msg_ok "Symlink: $link → $target"
}

# ---------------------------------------------------------------------------
# 1. Install 26_windows
# ---------------------------------------------------------------------------
install_26_windows() {
    msg_info "Installing Windows boot entry..."

    local src="${REPO_ROOT}/grub/grub.d/26_windows"
    local dst="/etc/grub.d/26_windows"

    if [[ -z "${WINDOWS_ESP_UUID:-}" ]]; then
        msg_info "WINDOWS_ESP_UUID not set — skipping 26_windows"
        # Remove existing if Windows is not configured
        if [[ -f "$dst" ]]; then
            rm -f "$dst"
            msg_info "Removed $dst (Windows not configured)"
        fi
        return
    fi

    # Validate UUID format to prevent sed injection
    if [[ ! "$WINDOWS_ESP_UUID" =~ ^[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}$ ]]; then
        msg_error "WINDOWS_ESP_UUID has invalid format: $WINDOWS_ESP_UUID"
        msg_error "Expected FAT32 UUID like 90B1-2A22"
        exit 1
    fi

    # Generate self-contained version with UUID baked in
    sed "s/%%WINDOWS_ESP_UUID%%/${WINDOWS_ESP_UUID}/g" "$src" > "$dst"
    chmod +x "$dst"
    msg_ok "Installed $dst (UUID: $WINDOWS_ESP_UUID)"
}

# ---------------------------------------------------------------------------
# 2. Install symlinks
# ---------------------------------------------------------------------------
install_symlinks() {
    msg_info "Installing command symlinks..."

    install_symlink "${REPO_ROOT}/scripts/update-boot.sh" "/usr/local/sbin/update-boot"
    install_symlink "${REPO_ROOT}/scripts/build-grub.sh"  "/usr/local/sbin/build-grub"
    install_symlink "${REPO_ROOT}/scripts/sign-boot.sh"   "/usr/local/sbin/sign-boot"
    install_symlink "${REPO_ROOT}/scripts/audit.sh"       "/usr/local/sbin/audit-secureboot"
}

# ---------------------------------------------------------------------------
# 3. Install kernel hook
# ---------------------------------------------------------------------------
install_kernel_hook() {
    msg_info "Installing installkernel hook..."

    local src="${REPO_ROOT}/hooks/99-update-boot.install"
    local dst="/etc/kernel/install.d/99-update-boot.install"

    if [[ ! -f "$src" ]]; then
        msg_warn "Hook source not found: $src — skipping"
        return
    fi

    mkdir -p /etc/kernel/install.d
    cp "$src" "$dst"
    chmod +x "$dst"
    msg_ok "Installed $dst"
}

# ---------------------------------------------------------------------------
# 4. Configure /etc/default/grub
# ---------------------------------------------------------------------------
configure_grub_defaults() {
    msg_info "Configuring /etc/default/grub..."

    local grub_file="/etc/default/grub"
    if [[ ! -f "$grub_file" ]]; then
        msg_error "/etc/default/grub not found"
        exit 1
    fi

    # Build GRUB_CMDLINE_LINUX from machine.conf values
    local cmdline=""

    if [[ -n "${EXTRA_CMDLINE:-}" ]]; then
        cmdline="${EXTRA_CMDLINE}"
    fi

    if [[ -n "${LUKS_UUID:-}" ]]; then
        local luks_name="${LUKS_MAPPING_NAME:-gentoo-lvm}"
        cmdline="${cmdline:+${cmdline} }rd.luks.name=${LUKS_UUID}=${luks_name}"

        if [[ "${LUKS_ALLOW_DISCARDS:-}" == "true" ]]; then
            cmdline="${cmdline} rd.luks.allow-discards"
        fi
    fi

    if [[ -n "${LVM_VG:-}" ]]; then
        cmdline="${cmdline:+${cmdline} }rd.lvm.vg=${LVM_VG}"

        if [[ -n "${LVM_LV_ROOT:-}" ]]; then
            cmdline="${cmdline} rd.lvm.lv=${LVM_VG}/${LVM_LV_ROOT}"
        fi
        if [[ -n "${LVM_LV_SWAP:-}" ]]; then
            cmdline="${cmdline} rd.lvm.lv=${LVM_VG}/${LVM_LV_SWAP}"
        fi

        # Root device path
        if [[ -n "${LVM_LV_ROOT:-}" ]]; then
            local vg_escaped="${LVM_VG//-/--}"
            local lv_escaped="${LVM_LV_ROOT//-/--}"
            cmdline="${cmdline} root=/dev/mapper/${vg_escaped}-${lv_escaped}"
        fi
    fi

    if [[ -n "${ROOT_FSTYPE:-}" ]]; then
        cmdline="${cmdline:+${cmdline} }rootfstype=${ROOT_FSTYPE}"
    fi

    if [[ -n "${ROOT_MOUNT_OPTIONS:-}" ]]; then
        cmdline="${cmdline:+${cmdline} }rootflags=${ROOT_MOUNT_OPTIONS}"
    fi

    # Set values
    grub_default_set "GRUB_CMDLINE_LINUX" "\"${cmdline}\""
    msg_ok "GRUB_CMDLINE_LINUX set"

    if [[ -n "${CMDLINE_DEFAULT:-}" ]]; then
        grub_default_set "GRUB_CMDLINE_LINUX_DEFAULT" "\"${CMDLINE_DEFAULT}\""
        msg_ok "GRUB_CMDLINE_LINUX_DEFAULT set"
    fi

    if [[ -n "${LUKS_UUID:-}" ]]; then
        grub_default_set "GRUB_ENABLE_CRYPTODISK" "y"
        msg_ok "GRUB_ENABLE_CRYPTODISK=y"
    fi

    grub_default_set "GRUB_DISABLE_OS_PROBER" "true"
    msg_ok "GRUB_DISABLE_OS_PROBER=true"

    grub_default_set "GRUB_DISABLE_LINUX_UUID" "true"
    msg_ok "GRUB_DISABLE_LINUX_UUID=true"

    grub_default_set "GRUB_DISABLE_LINUX_PARTUUID" "true"
    msg_ok "GRUB_DISABLE_LINUX_PARTUUID=true"

    grub_default_set "GRUB_GFXPAYLOAD_LINUX" "keep"
    msg_ok "GRUB_GFXPAYLOAD_LINUX=keep"

    # Remove unnecessary settings
    grub_default_remove "GRUB_OS_PROBER_SKIP_LIST"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    msg_info "=== Installing gentoo-secureboot ==="
    echo ""

    install_26_windows
    echo ""
    install_symlinks
    echo ""
    install_kernel_hook
    echo ""
    configure_grub_defaults

    echo ""
    msg_ok "=== Installation complete ==="
    msg_info "Commands available: update-boot, build-grub, sign-boot, audit-secureboot"
}

main "$@"
