#!/usr/bin/env bats
# Tests for msg_info/ok/warn/error from scripts/lib.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

@test "msg_info: outputs to stdout" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        msg_info 'test message'
    "
    assert_success
    assert_output --partial "test message"
}

@test "msg_ok: outputs to stdout" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        msg_ok 'test message'
    "
    assert_success
    assert_output --partial "test message"
}

@test "msg_warn: outputs to stderr" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        msg_warn 'warning message' 2>&1
    "
    assert_success
    assert_output --partial "warning message"
}

@test "msg_error: outputs to stderr" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        msg_error 'error message' 2>&1
    "
    assert_success
    assert_output --partial "error message"
}

@test "msg_warn: does not appear on stdout" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        msg_warn 'warning message' 2>/dev/null
    "
    assert_success
    refute_output --partial "warning message"
}

@test "msg_error: does not appear on stdout" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        msg_error 'error message' 2>/dev/null
    "
    assert_success
    refute_output --partial "error message"
}
