#!/usr/bin/env bats
# Tests for load_config() with real file operations and mocked stat

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

# Helper: run load_config in a subshell
run_load_config() {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        load_config
        echo \"LINUX_ESP_UUID=\${LINUX_ESP_UUID}\"
        echo \"BOOTLOADER_ID=\${BOOTLOADER_ID}\"
        echo \"ESP_MOUNT=\${ESP_MOUNT}\"
        echo \"GPG_KEY_NAME=\${GPG_KEY_NAME}\"
    "
}

@test "load_config: loads valid config with all vars set" {
    cp "${TESTS_DIR}/fixtures/machine.conf.valid" "${TEST_REPO_ROOT}/machine.conf"
    create_mock_stat_root_owned
    run_load_config
    assert_success
    assert_output --partial 'LINUX_ESP_UUID=D728-8DD1'
    assert_output --partial 'BOOTLOADER_ID=gentoo'
    assert_output --partial 'ESP_MOUNT=/boot'
    assert_output --partial 'GPG_KEY_NAME=grub'
}

@test "load_config: fails on missing file" {
    # Don't create machine.conf
    run_load_config
    assert_failure
    assert_output --partial "machine.conf not found"
}

@test "load_config: fails on wrong owner" {
    cp "${TESTS_DIR}/fixtures/machine.conf.valid" "${TEST_REPO_ROOT}/machine.conf"
    create_mock_stat "1000:1000" "user:user" "600"
    run_load_config
    assert_failure
    assert_output --partial "owned by root"
}

@test "load_config: fails on wrong permissions" {
    cp "${TESTS_DIR}/fixtures/machine.conf.valid" "${TEST_REPO_ROOT}/machine.conf"
    create_mock_stat "0:0" "root:root" "644"
    run_load_config
    assert_failure
    assert_output --partial "unsafe permissions"
}

@test "load_config: fails on empty required var" {
    create_machine_conf_from 'LINUX_ESP_UUID=""
BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_failure
    assert_output --partial "missing required"
    assert_output --partial "LINUX_ESP_UUID"
}
