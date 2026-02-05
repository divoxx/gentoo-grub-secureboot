#!/usr/bin/env bats
# Tests for load_config() validation logic from scripts/lib.sh

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
    "
}

@test "load_config: accepts valid BOOTLOADER_ID" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo123"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_success
}

@test "load_config: accepts hyphens and underscores in BOOTLOADER_ID" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo-test_1"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_success
}

@test "load_config: rejects BOOTLOADER_ID with spaces" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="my gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_failure
    assert_output --partial "invalid characters"
}

@test "load_config: rejects BOOTLOADER_ID with slashes" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo/test"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_failure
    assert_output --partial "invalid characters"
}

@test "load_config: validates ESP_MOUNT is absolute path" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo"
ESP_MOUNT="boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_failure
    assert_output --partial "absolute path"
}

@test "load_config: accepts absolute ESP_MOUNT" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_success
}

@test "load_config: detects missing required var" {
    create_machine_conf_from 'BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    run_load_config
    assert_failure
    assert_output --partial "missing required"
    assert_output --partial "LINUX_ESP_UUID"
}

@test "load_config: detects multiple missing vars" {
    create_machine_conf_from 'BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"'
    run_load_config
    assert_failure
    assert_output --partial "LINUX_ESP_UUID"
    assert_output --partial "GPG_KEY_NAME"
}

@test "load_config: rejects unusual GPG_KEY_NAME" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="key with spaces"'
    run_load_config
    # GPG_KEY_NAME with spaces triggers the unusual warning (which goes to stderr)
    assert_output --partial "unusual characters"
}

@test "load_config: accepts email GPG_KEY_NAME" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub@localhost"'
    run_load_config
    assert_success
}

@test "load_config: fails when machine.conf missing" {
    # Don't create machine.conf
    run_load_config
    assert_failure
    assert_output --partial "machine.conf not found"
}

@test "load_config: fails on wrong ownership" {
    create_machine_conf_from 'LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"'
    # Override stat mock to report non-root owner
    create_mock_stat "1000:1000" "user:user" "600"
    run_load_config
    assert_failure
    assert_output --partial "owned by root"
}
