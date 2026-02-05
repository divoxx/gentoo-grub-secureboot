#!/usr/bin/env bats
# Tests for cleanup_orphaned_sigs() from scripts/sign-boot.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/sign-boot.sh" "${TEST_REPO_ROOT}/scripts/sign-boot.sh"

    export ESP_MOUNT="${TEST_ESP}"
    export BOOTLOADER_ID="gentoo"
}

teardown() {
    common_teardown
}

# Helper: extract and run cleanup_orphaned_sigs
run_cleanup_orphaned_sigs() {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='gentoo'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^cleanup_orphaned_sigs()/,/^}/p' '${TEST_REPO_ROOT}/scripts/sign-boot.sh')\"
        cleanup_orphaned_sigs
    "
}

@test "cleanup_orphaned_sigs: removes sig without base file" {
    touch "${TEST_ESP}/old-kernel.sig"
    run_cleanup_orphaned_sigs
    assert_success
    assert [ ! -f "${TEST_ESP}/old-kernel.sig" ]
}

@test "cleanup_orphaned_sigs: keeps sig with base file" {
    touch "${TEST_ESP}/kernel-6.1.0"
    touch "${TEST_ESP}/kernel-6.1.0.sig"
    run_cleanup_orphaned_sigs
    assert_success
    assert [ -f "${TEST_ESP}/kernel-6.1.0" ]
    assert [ -f "${TEST_ESP}/kernel-6.1.0.sig" ]
}

@test "cleanup_orphaned_sigs: handles grub/*.sig" {
    touch "${TEST_ESP}/grub/old-config.sig"
    # No base file for old-config
    run_cleanup_orphaned_sigs
    assert_success
    assert [ ! -f "${TEST_ESP}/grub/old-config.sig" ]
}

@test "cleanup_orphaned_sigs: no-op when no orphans" {
    touch "${TEST_ESP}/kernel-6.1.0"
    touch "${TEST_ESP}/kernel-6.1.0.sig"
    touch "${TEST_ESP}/grub/grub.cfg"
    touch "${TEST_ESP}/grub/grub.cfg.sig"
    run_cleanup_orphaned_sigs
    assert_success
    assert [ -f "${TEST_ESP}/kernel-6.1.0.sig" ]
    assert [ -f "${TEST_ESP}/grub/grub.cfg.sig" ]
}
