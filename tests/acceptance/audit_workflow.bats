#!/usr/bin/env bats
# Acceptance tests for audit.sh — full workflow with mock environment

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/audit.sh" "${TEST_REPO_ROOT}/scripts/audit.sh"

    export ESP_MOUNT="${TEST_ESP}"
    export BOOTLOADER_ID="gentoo"
    export GPG_KEY_NAME="grub"
}

teardown() {
    common_teardown
}

# Helper: build a healthy mock environment for audit
setup_healthy_env() {
    # machine.conf
    create_machine_conf

    # grub.cfg with signature
    touch "${TEST_ESP}/grub/grub.cfg"
    touch "${TEST_ESP}/grub/grub.cfg.sig"
    # Make sig newer than file (touch sig after file)
    sleep 0.1
    touch "${TEST_ESP}/grub/grub.cfg.sig"

    # Kernel + initramfs with sigs
    touch "${TEST_ESP}/kernel-6.1.0"
    touch "${TEST_ESP}/kernel-6.1.0.sig"
    touch "${TEST_ESP}/initramfs-6.1.0.img"
    touch "${TEST_ESP}/initramfs-6.1.0.img.sig"

    # GRUB binary
    mkdir -p "${TEST_ESP}/EFI/${BOOTLOADER_ID}"
    echo "check_signatures" > "${TEST_ESP}/EFI/${BOOTLOADER_ID}/grubx64.efi"

    # Mock external commands
    create_mock_sbctl 0
    create_mock_gpg 0
    create_mock "efibootmgr" 0 "Boot0001* ${BOOTLOADER_ID}"
    create_mock "strings" 0 "check_signatures"
}

# Helper: run audit check functions with test environment
# We don't set EUID (it's readonly); instead we control IS_ROOT directly
run_audit() {
    local is_root="${1:-true}"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='${BOOTLOADER_ID}'
        export GPG_KEY_NAME='${GPG_KEY_NAME}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'

        IS_ROOT=${is_root}

        PASS=0; FAIL=0; WARN=0
        audit_pass() { PASS=\$((PASS + 1)); msg_ok \"PASS: \$*\"; }
        audit_fail() { FAIL=\$((FAIL + 1)); msg_error \"FAIL: \$*\"; }
        audit_warn() { WARN=\$((WARN + 1)); msg_warn \"WARN: \$*\"; }

        # Import check functions from audit.sh
        eval \"\$(sed -n '/^check_gpg_signatures()/,/^}/p' '${TEST_REPO_ROOT}/scripts/audit.sh')\"
        eval \"\$(sed -n '/^check_grub_binary()/,/^}/p' '${TEST_REPO_ROOT}/scripts/audit.sh')\"

        # Run checks
        check_gpg_signatures
        check_grub_binary

        # Summary
        echo \"PASS=\$PASS FAIL=\$FAIL WARN=\$WARN\"
        if [[ \$FAIL -gt 0 ]]; then
            exit 1
        fi
    " 2>&1
}

@test "audit: exits 0 when all GPG checks pass" {
    setup_healthy_env
    run_audit true
    assert_success
    assert_output --partial "PASS="
    refute_output --partial "FAIL=1"
}

@test "audit: exits 1 on missing grub.cfg.sig" {
    setup_healthy_env
    rm "${TEST_ESP}/grub/grub.cfg.sig"
    run_audit true
    assert_failure
    assert_output --partial "FAIL:"
}

@test "audit: detects stale signatures" {
    setup_healthy_env
    # Make file newer than its signature
    sleep 0.1
    touch "${TEST_ESP}/kernel-6.1.0"
    run_audit true
    assert_failure
    assert_output --partial "Stale signature"
}

@test "audit: warns when no boot files found" {
    create_mock_gpg 0
    create_mock "strings" 0 "check_signatures"
    # ESP is empty (no grub.cfg, no kernels)
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='gentoo'
        export GPG_KEY_NAME='grub'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'

        PASS=0; FAIL=0; WARN=0
        audit_pass() { PASS=\$((PASS + 1)); msg_ok \"PASS: \$*\"; }
        audit_fail() { FAIL=\$((FAIL + 1)); msg_error \"FAIL: \$*\"; }
        audit_warn() { WARN=\$((WARN + 1)); msg_warn \"WARN: \$*\"; }

        eval \"\$(sed -n '/^check_gpg_signatures()/,/^}/p' '${TEST_REPO_ROOT}/scripts/audit.sh')\"
        check_gpg_signatures
        echo \"WARN=\$WARN\"
    " 2>&1
    assert_output --partial "WARN=1"
}

@test "audit: validates GRUB binary check_signatures presence" {
    setup_healthy_env
    run_audit true
    assert_output --partial "check_signatures found"
}

@test "audit: reports missing GRUB binary" {
    setup_healthy_env
    rm -f "${TEST_ESP}/EFI/${BOOTLOADER_ID}/grubx64.efi"
    run_audit true
    assert_failure
    assert_output --partial "GRUB binary not found"
}
