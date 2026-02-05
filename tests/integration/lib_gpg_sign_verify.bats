#!/usr/bin/env bats
# Tests for gpg_sign() and gpg_verify() from scripts/lib.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    # Create a test file to sign
    TEST_FILE="${TEST_TMPDIR}/testfile"
    echo "test content" > "$TEST_FILE"

    export GPG_KEY_NAME="grub"
}

teardown() {
    common_teardown
}

# Helper: source lib.sh and run gpg_sign
run_gpg_sign() {
    local file="$1"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export GPG_KEY_NAME='grub'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        gpg_sign '${file}'
    "
}

# Helper: source lib.sh and run gpg_verify
run_gpg_verify() {
    local file="$1"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export GPG_KEY_NAME='grub'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        gpg_verify '${file}'
    "
}

@test "gpg_sign: creates .sig file" {
    create_mock_gpg 0
    run_gpg_sign "$TEST_FILE"
    assert_success
    assert [ -f "${TEST_FILE}.sig" ]
}

@test "gpg_sign: no .sig.tmp left on success" {
    create_mock_gpg 0
    run_gpg_sign "$TEST_FILE"
    assert_success
    assert [ ! -f "${TEST_FILE}.sig.tmp" ]
}

@test "gpg_sign: cleans .sig.tmp on failure" {
    create_mock_gpg_failing_sign
    run_gpg_sign "$TEST_FILE"
    assert_failure
    assert [ ! -f "${TEST_FILE}.sig.tmp" ]
}

@test "gpg_sign: preserves old .sig on failure" {
    echo "original-signature" > "${TEST_FILE}.sig"
    create_mock_gpg_failing_sign
    run_gpg_sign "$TEST_FILE"
    assert_failure
    # Original .sig should be intact
    run cat "${TEST_FILE}.sig"
    assert_output "original-signature"
}

@test "gpg_verify: returns 0 on valid signature" {
    create_mock_gpg 0
    touch "${TEST_FILE}.sig"
    run_gpg_verify "$TEST_FILE"
    assert_success
}

@test "gpg_verify: returns 1 if .sig missing" {
    create_mock_gpg 0
    # Don't create .sig file
    run_gpg_verify "$TEST_FILE"
    assert_failure
    assert_output --partial "Signature missing"
}

@test "gpg_verify: returns 1 on verification failure" {
    # Create a gpg mock that fails on --verify
    local mock_path="${TEST_MOCK_BIN}/gpg"
    cat > "$mock_path" << 'MOCKEOF'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        --verify) echo "gpg: BAD signature" >&2; exit 1 ;;
    esac
done
exit 0
MOCKEOF
    chmod +x "$mock_path"
    touch "${TEST_FILE}.sig"
    run_gpg_verify "$TEST_FILE"
    assert_failure
}
