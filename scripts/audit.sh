#!/usr/bin/env bash
# audit.sh — Health check and verification for Secure Boot + GRUB GPG
#
# Read-only verification script. Works with degraded output if not root
# (some checks require root access).
#
# Checks:
#   1. Secure Boot status (sbctl)
#   2. PE signature verification (sbctl verify)
#   3. GPG signature verification for boot files
#   4. Stale/missing signature detection
#   5. GPG key availability
#   6. Embedded signature enforcement in GRUB binary
#   7. /etc/default/grub settings
#   8. EFI boot entry

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# Audit can run without root, but with degraded output
IS_ROOT=false
[[ $EUID -eq 0 ]] && IS_ROOT=true

# Try to load config; continue without it for degraded mode
try_load_config || true

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
WARN=0

audit_pass() { PASS=$((PASS + 1)); msg_ok "PASS: $*"; }
audit_fail() { FAIL=$((FAIL + 1)); msg_error "FAIL: $*"; }
audit_warn() { WARN=$((WARN + 1)); msg_warn "WARN: $*"; }

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

check_secure_boot_status() {
    msg_info "--- Secure Boot Status ---"

    if ! command -v sbctl &>/dev/null; then
        audit_fail "sbctl not installed"
        return
    fi

    if ! $IS_ROOT; then
        audit_warn "Cannot check sbctl status without root"
        return
    fi

    local status
    status="$(sbctl status 2>&1)" || true

    if echo "$status" | grep -q "Secure Boot:.*Enabled"; then
        audit_pass "Secure Boot is enabled"
    elif echo "$status" | grep -q "Secure Boot:.*Disabled"; then
        audit_fail "Secure Boot is disabled"
    else
        audit_warn "Cannot determine Secure Boot status"
    fi

    echo "$status" | head -5
    echo ""
}

check_pe_signatures() {
    msg_info "--- PE Signature Verification ---"

    if ! $IS_ROOT; then
        audit_warn "Cannot verify PE signatures without root"
        return
    fi

    local output
    output="$(sbctl verify 2>&1)" || true
    echo "$output"
    echo ""

    local fail_count
    fail_count="$(echo "$output" | grep -c "not signed" || true)"

    if [[ "$fail_count" -gt 0 ]]; then
        audit_fail "$fail_count PE files not signed"
    else
        audit_pass "All enrolled PE files are signed"
    fi
}

check_gpg_signatures() {
    msg_info "--- GPG Signature Verification ---"

    local esp="$ESP_MOUNT"
    local files=()

    # Collect files that should be signed
    [[ -f "${esp}/grub/grub.cfg" ]] && files+=("${esp}/grub/grub.cfg")

    for f in "${esp}"/kernel-*; do
        [[ -f "$f" && "$f" != *.sig ]] && files+=("$f")
    done

    for f in "${esp}"/initramfs-*.img; do
        [[ -f "$f" && "$f" != *.sig ]] && files+=("$f")
    done

    [[ -f "${esp}/amd-uc.img" ]] && files+=("${esp}/amd-uc.img")
    [[ -f "${esp}/intel-uc.img" ]] && files+=("${esp}/intel-uc.img")

    if [[ ${#files[@]} -eq 0 ]]; then
        audit_warn "No boot files found to verify"
        return
    fi

    for file in "${files[@]}"; do
        local basename
        basename="$(basename "$file")"
        local sig="${file}.sig"

        if [[ ! -f "$sig" ]]; then
            audit_fail "Missing signature: ${basename}.sig"
            continue
        fi

        # Check for stale signatures (file newer than .sig)
        if [[ "$file" -nt "$sig" ]]; then
            audit_fail "Stale signature: $basename is newer than its .sig"
            continue
        fi

        # Verify GPG signature
        if gpg --batch --verify "$sig" "$file" 2>/dev/null; then
            audit_pass "GPG verified: $basename"
        else
            audit_fail "GPG verification FAILED: $basename"
        fi
    done
}

check_gpg_key() {
    msg_info "--- GPG Key ---"

    if gpg --list-keys "$GPG_KEY_NAME" &>/dev/null; then
        audit_pass "GPG key '$GPG_KEY_NAME' available"
    else
        audit_fail "GPG key '$GPG_KEY_NAME' not found in keyring"
    fi

    if [[ -f /root/grub.pub ]]; then
        audit_pass "/root/grub.pub exists"
    else
        audit_fail "/root/grub.pub not found"
    fi
}

check_grub_binary() {
    msg_info "--- GRUB Binary ---"

    local efi="${ESP_MOUNT}/EFI/${BOOTLOADER_ID}/grubx64.efi"

    if [[ ! -f "$efi" ]]; then
        audit_fail "GRUB binary not found: $efi"
        return
    fi

    audit_pass "GRUB binary exists: $efi"

    # Check for embedded signature enforcement
    if command -v strings &>/dev/null; then
        if strings "$efi" | grep -q "check_signatures"; then
            audit_pass "check_signatures found in GRUB binary"
        else
            audit_warn "check_signatures not found in GRUB binary (may be false negative)"
        fi
    fi
}

check_grub_defaults() {
    msg_info "--- /etc/default/grub ---"

    local grub_file="/etc/default/grub"
    if [[ ! -f "$grub_file" ]]; then
        audit_fail "/etc/default/grub not found"
        return
    fi

    local expected_settings=(
        "GRUB_DISABLE_OS_PROBER=true"
        "GRUB_DISABLE_LINUX_UUID=true"
        "GRUB_DISABLE_LINUX_PARTUUID=true"
        "GRUB_GFXPAYLOAD_LINUX=keep"
    )

    for setting in "${expected_settings[@]}"; do
        local key="${setting%%=*}"
        local value="${setting#*=}"
        if grep -q "^${key}=${value}" "$grub_file" 2>/dev/null; then
            audit_pass "$setting"
        else
            audit_fail "$setting not set in /etc/default/grub"
        fi
    done

    # Check LUKS-specific setting
    if [[ -n "${LUKS_UUID:-}" ]]; then
        if grep -q "^GRUB_ENABLE_CRYPTODISK=y" "$grub_file" 2>/dev/null; then
            audit_pass "GRUB_ENABLE_CRYPTODISK=y"
        else
            audit_fail "GRUB_ENABLE_CRYPTODISK=y not set (required for LUKS)"
        fi
    fi

    # Warn about deprecated settings
    if grep -q "^GRUB_OS_PROBER_SKIP_LIST=" "$grub_file" 2>/dev/null; then
        audit_warn "GRUB_OS_PROBER_SKIP_LIST is set (unnecessary with os-prober disabled)"
    fi
}

check_efi_boot_entry() {
    msg_info "--- EFI Boot Entry ---"

    if ! $IS_ROOT; then
        audit_warn "Cannot check EFI boot entries without root"
        return
    fi

    if ! command -v efibootmgr &>/dev/null; then
        audit_fail "efibootmgr not installed"
        return
    fi

    if efibootmgr | grep -qiF "$BOOTLOADER_ID"; then
        audit_pass "EFI boot entry for '$BOOTLOADER_ID' exists"
        efibootmgr | grep -iF "$BOOTLOADER_ID"
    else
        audit_fail "No EFI boot entry for '$BOOTLOADER_ID'"
    fi
}

check_file_permissions() {
    msg_info "--- File Permissions ---"

    if [[ -f "$MACHINE_CONF" ]]; then
        local perms
        perms="$(stat -c '%a' "$MACHINE_CONF")"
        if [[ "$perms" == "600" ]]; then
            audit_pass "machine.conf has restrictive permissions ($perms)"
        else
            audit_warn "machine.conf has permissive permissions: $perms (expected 600)"
        fi
    else
        audit_warn "machine.conf not found — cannot check permissions"
    fi
}

check_kernel_hook() {
    msg_info "--- Kernel Hook ---"

    local hook="/etc/kernel/install.d/99-update-boot.install"
    if [[ -f "$hook" ]]; then
        if [[ -x "$hook" ]]; then
            audit_pass "Kernel hook installed and executable"
        else
            audit_fail "Kernel hook exists but not executable: $hook"
        fi
    else
        audit_warn "Kernel hook not installed: $hook"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    msg_info "========================================="
    msg_info "  Secure Boot Audit"
    msg_info "========================================="
    echo ""

    if ! $IS_ROOT; then
        msg_warn "Running without root — some checks will be skipped"
        echo ""
    fi

    check_secure_boot_status
    echo ""
    check_pe_signatures
    echo ""
    check_gpg_signatures
    echo ""
    check_gpg_key
    echo ""
    check_grub_binary
    echo ""
    check_grub_defaults
    echo ""
    check_efi_boot_entry
    echo ""
    check_file_permissions
    echo ""
    check_kernel_hook

    echo ""
    msg_info "========================================="
    msg_info "  Audit Summary"
    msg_info "========================================="
    msg_ok   "  PASS: $PASS"
    [[ $WARN -gt 0 ]] && msg_warn "  WARN: $WARN"
    [[ $FAIL -gt 0 ]] && msg_error "  FAIL: $FAIL"

    if [[ $FAIL -gt 0 ]]; then
        echo ""
        msg_error "Issues found. Review failures above and run the appropriate fix."
        exit 1
    elif [[ $WARN -gt 0 ]]; then
        echo ""
        msg_warn "Warnings found but no critical failures."
        exit 0
    else
        echo ""
        msg_ok "All checks passed."
        exit 0
    fi
}

main "$@"
