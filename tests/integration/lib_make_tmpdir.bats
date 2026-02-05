#!/usr/bin/env bats
# Tests for make_tmpdir() from scripts/lib.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

@test "make_tmpdir: creates a temporary directory" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        make_tmpdir
        echo \"\$_TMPDIR\"
        [[ -d \"\$_TMPDIR\" ]]
    "
    assert_success
}

@test "make_tmpdir: directory has secureboot prefix" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        make_tmpdir
        basename \"\$_TMPDIR\"
    "
    assert_success
    assert_output --partial "secureboot."
}

@test "make_tmpdir: cleanup removes directory on EXIT" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        make_tmpdir
        tmpdir=\"\$_TMPDIR\"
        echo \"\$tmpdir\"
        # Trigger EXIT trap by exiting the subshell
    "
    assert_success
    # The directory should be gone after the subshell exits
    local tmpdir_path
    tmpdir_path="$output"
    assert [ ! -d "$tmpdir_path" ]
}
