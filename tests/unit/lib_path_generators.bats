#!/usr/bin/env bats
# Tests for path generator functions from scripts/lib.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

@test "grub_efi_path: returns correct path" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        ESP_MOUNT='/boot'
        BOOTLOADER_ID='gentoo'
        grub_efi_path
    "
    assert_success
    assert_output "/boot/EFI/gentoo/grubx64.efi"
}

@test "grub_cfg_path: returns correct path" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        ESP_MOUNT='/boot'
        grub_cfg_path
    "
    assert_success
    assert_output "/boot/grub/grub.cfg"
}

@test "modules_file: returns correct path" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        modules_file
    "
    assert_success
    assert_output "${TEST_REPO_ROOT}/grub/modules.txt"
}

@test "initial_cfg_tpl: returns correct path" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        initial_cfg_tpl
    "
    assert_success
    assert_output "${TEST_REPO_ROOT}/grub/initial.cfg.template"
}
