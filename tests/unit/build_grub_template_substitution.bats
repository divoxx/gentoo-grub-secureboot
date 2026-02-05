#!/usr/bin/env bats
# Tests for template rendering via sed in scripts/build-grub.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    # Copy template into mock repo
    cp "${PROJECT_ROOT}/grub/initial.cfg.template" "${TEST_REPO_ROOT}/grub/initial.cfg.template"
}

teardown() {
    common_teardown
}

@test "template substitution: replaces %%LINUX_ESP_UUID%%" {
    run bash -c "
        sed 's/%%LINUX_ESP_UUID%%/D728-8DD1/g' '${TEST_REPO_ROOT}/grub/initial.cfg.template'
    "
    assert_success
    assert_output --partial "D728-8DD1"
    refute_output --partial "%%LINUX_ESP_UUID%%"
}

@test "template substitution: preserves other content" {
    run bash -c "
        sed 's/%%LINUX_ESP_UUID%%/D728-8DD1/g' '${TEST_REPO_ROOT}/grub/initial.cfg.template'
    "
    assert_success
    assert_output --partial "set check_signatures=enforce"
    assert_output --partial "configfile"
}

@test "template substitution: handles lowercase UUID" {
    run bash -c "
        sed 's/%%LINUX_ESP_UUID%%/d728-8dd1/g' '${TEST_REPO_ROOT}/grub/initial.cfg.template'
    "
    assert_success
    assert_output --partial "d728-8dd1"
    refute_output --partial "%%LINUX_ESP_UUID%%"
}
