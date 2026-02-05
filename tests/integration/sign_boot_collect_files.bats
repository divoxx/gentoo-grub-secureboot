#!/usr/bin/env bats
# Tests for collect_files() from scripts/sign-boot.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    # Copy sign-boot.sh for function extraction
    cp "${PROJECT_ROOT}/scripts/sign-boot.sh" "${TEST_REPO_ROOT}/scripts/sign-boot.sh"

    # Set up config vars that collect_files needs
    export ESP_MOUNT="${TEST_ESP}"
    export BOOTLOADER_ID="gentoo"
}

teardown() {
    common_teardown
}

# Helper: extract and run collect_files with lib.sh sourced
run_collect_files() {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='gentoo'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        # Extract collect_files function from sign-boot.sh
        eval \"\$(sed -n '/^collect_files()/,/^}/p' '${TEST_REPO_ROOT}/scripts/sign-boot.sh')\"
        collect_files
    " 2>&1
}

@test "collect_files: finds grub.cfg" {
    touch "${TEST_ESP}/grub/grub.cfg"
    run_collect_files
    assert_output --partial "grub.cfg"
}

@test "collect_files: finds kernel files" {
    touch "${TEST_ESP}/kernel-6.1.0-gentoo"
    run_collect_files
    assert_output --partial "kernel-6.1.0-gentoo"
}

@test "collect_files: finds initramfs" {
    touch "${TEST_ESP}/initramfs-6.1.0.img"
    run_collect_files
    assert_output --partial "initramfs-6.1.0.img"
}

@test "collect_files: finds amd-uc.img" {
    touch "${TEST_ESP}/amd-uc.img"
    run_collect_files
    assert_output --partial "amd-uc.img"
}

@test "collect_files: finds intel-uc.img" {
    touch "${TEST_ESP}/intel-uc.img"
    run_collect_files
    assert_output --partial "intel-uc.img"
}

@test "collect_files: skips .sig files" {
    touch "${TEST_ESP}/kernel-6.1.0-gentoo"
    touch "${TEST_ESP}/kernel-6.1.0-gentoo.sig"
    run_collect_files
    assert_output --partial "kernel-6.1.0-gentoo"
    # The .sig line should not appear as a standalone entry
    refute_line "kernel-6.1.0-gentoo.sig"
}

@test "collect_files: handles multiple kernels" {
    touch "${TEST_ESP}/kernel-6.1.0-gentoo"
    touch "${TEST_ESP}/kernel-6.2.0-gentoo"
    run_collect_files
    assert_output --partial "kernel-6.1.0-gentoo"
    assert_output --partial "kernel-6.2.0-gentoo"
}
