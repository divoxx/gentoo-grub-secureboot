#!/usr/bin/env bats
# Tests for audit_pass/fail/warn counters from scripts/audit.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

# Helper: source lib.sh and define audit functions in a subshell
run_audit_counter() {
    local code="$1"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        PASS=0; FAIL=0; WARN=0
        audit_pass() { PASS=\$((PASS + 1)); msg_ok \"PASS: \$*\"; }
        audit_fail() { FAIL=\$((FAIL + 1)); msg_error \"FAIL: \$*\"; }
        audit_warn() { WARN=\$((WARN + 1)); msg_warn \"WARN: \$*\"; }
        ${code}
    "
}

@test "audit_pass increments PASS" {
    run_audit_counter '
        audit_pass "test check"
        echo "PASS=$PASS"
    '
    assert_success
    assert_output --partial "PASS=1"
}

@test "audit_fail increments FAIL" {
    run_audit_counter '
        audit_fail "test check"
        echo "FAIL=$FAIL"
    '
    assert_output --partial "FAIL=1"
}

@test "audit_warn increments WARN" {
    run_audit_counter '
        audit_warn "test check"
        echo "WARN=$WARN"
    '
    assert_output --partial "WARN=1"
}

@test "audit_pass outputs PASS:" {
    run_audit_counter 'audit_pass "something passed"'
    assert_output --partial "PASS:"
}

@test "audit_fail outputs FAIL:" {
    run_audit_counter 'audit_fail "something failed" 2>&1'
    assert_output --partial "FAIL:"
}

@test "audit_warn outputs WARN:" {
    run_audit_counter 'audit_warn "something warned" 2>&1'
    assert_output --partial "WARN:"
}

@test "counters accumulate correctly" {
    run_audit_counter '
        audit_pass "p1"; audit_pass "p2"; audit_pass "p3"
        audit_fail "f1"; audit_fail "f2"
        audit_warn "w1"
        echo "PASS=$PASS FAIL=$FAIL WARN=$WARN"
    ' 2>&1
    assert_output --partial "PASS=3 FAIL=2 WARN=1"
}
