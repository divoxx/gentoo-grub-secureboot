#!/usr/bin/env bats
# Tests for try_load_config() from scripts/lib.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

@test "try_load_config: returns 1 with defaults when file missing" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        rc=0
        try_load_config || rc=\$?
        echo \"rc=\${rc}\"
        echo \"ESP_MOUNT=\${ESP_MOUNT}\"
        echo \"BOOTLOADER_ID=\${BOOTLOADER_ID}\"
        echo \"GPG_KEY_NAME=\${GPG_KEY_NAME}\"
    " 2>&1
    assert_success
    assert_output --partial "rc=1"
    assert_output --partial "ESP_MOUNT=/boot"
    assert_output --partial "BOOTLOADER_ID=gentoo"
    assert_output --partial "GPG_KEY_NAME=grub"
}

@test "try_load_config: returns 1 with defaults on bad owner" {
    cp "${TESTS_DIR}/fixtures/machine.conf.valid" "${TEST_REPO_ROOT}/machine.conf"
    create_mock_stat "1000:1000" "user:user" "600"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        rc=0
        try_load_config || rc=\$?
        echo \"rc=\${rc}\"
        echo \"ESP_MOUNT=\${ESP_MOUNT}\"
    " 2>&1
    assert_success
    assert_output --partial "rc=1"
    assert_output --partial "ESP_MOUNT=/boot"
}

@test "try_load_config: returns 0 and loads on valid file" {
    cp "${TESTS_DIR}/fixtures/machine.conf.valid" "${TEST_REPO_ROOT}/machine.conf"
    create_mock_stat_root_owned
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        rc=0
        try_load_config || rc=\$?
        echo \"rc=\${rc}\"
        echo \"ESP_MOUNT=\${ESP_MOUNT}\"
        echo \"BOOTLOADER_ID=\${BOOTLOADER_ID}\"
    " 2>&1
    assert_success
    assert_output --partial "rc=0"
    assert_output --partial "ESP_MOUNT=/boot"
    assert_output --partial "BOOTLOADER_ID=gentoo"
}

@test "try_load_config: preserves pre-set variables" {
    # File missing scenario — defaults should preserve pre-set ESP_MOUNT
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='/efi'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        try_load_config || true
        echo \"ESP_MOUNT=\${ESP_MOUNT}\"
    " 2>&1
    assert_success
    assert_output --partial "ESP_MOUNT=/efi"
}
