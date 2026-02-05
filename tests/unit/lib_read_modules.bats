#!/usr/bin/env bats
# Tests for read_modules() from scripts/lib.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

# Helper: run read_modules in a subshell with REPO_ROOT set
run_read_modules() {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        read_modules
    "
}

@test "read_modules: parses valid modules with comments and blanks" {
    cp "${TESTS_DIR}/fixtures/modules.txt.valid" "${TEST_REPO_ROOT}/grub/modules.txt"
    run_read_modules
    assert_success
    assert_output --partial "normal"
    assert_output --partial "configfile"
    assert_output --partial "linux"
    assert_output --partial "search"
    assert_output --partial "pgp"
    assert_output --partial "gcry_sha512"
}

@test "read_modules: strips trailing whitespace" {
    printf 'normal  \n' > "${TEST_REPO_ROOT}/grub/modules.txt"
    run_read_modules
    assert_success
    assert_output "normal"
}

@test "read_modules: rejects invalid chars (dots)" {
    printf 'some.module\n' > "${TEST_REPO_ROOT}/grub/modules.txt"
    run_read_modules
    assert_failure
    assert_output --partial "Invalid module name"
}

@test "read_modules: treats space-separated words as separate modules" {
    printf 'bad module\n' > "${TEST_REPO_ROOT}/grub/modules.txt"
    run_read_modules
    assert_success
    assert_output --partial "bad"
    assert_output --partial "module"
}

@test "read_modules: accepts hyphens and underscores" {
    printf 'gcry_sha512\nefi-gop\n' > "${TEST_REPO_ROOT}/grub/modules.txt"
    run_read_modules
    assert_success
    assert_output --partial "gcry_sha512"
    assert_output --partial "efi-gop"
}

@test "read_modules: fails if file missing" {
    # No modules.txt created
    run_read_modules
    assert_failure
    assert_output --partial "Module list not found"
}

@test "read_modules: fails if all comments" {
    cp "${TESTS_DIR}/fixtures/modules.txt.empty" "${TEST_REPO_ROOT}/grub/modules.txt"
    run_read_modules
    assert_failure
    assert_output --partial "No modules found"
}

@test "read_modules: handles single module" {
    printf 'normal\n' > "${TEST_REPO_ROOT}/grub/modules.txt"
    run_read_modules
    assert_success
    assert_output "normal"
}
