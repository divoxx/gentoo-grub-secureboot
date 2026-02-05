#!/usr/bin/env bats
# Tests for install_symlink() from scripts/install.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/install.sh" "${TEST_REPO_ROOT}/scripts/install.sh"

    # Create target file for symlinks
    TEST_TARGET="${TEST_TMPDIR}/target-script.sh"
    echo "#!/bin/bash" > "$TEST_TARGET"

    TEST_LINK="${TEST_TMPDIR}/test-link"
}

teardown() {
    common_teardown
}

# Helper: run install_symlink in a subshell
run_install_symlink() {
    local target="$1"
    local link="$2"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        # Extract install_symlink function
        eval \"\$(sed -n '/^install_symlink()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        install_symlink '${target}' '${link}'
    "
}

@test "install_symlink: creates new symlink" {
    run_install_symlink "$TEST_TARGET" "$TEST_LINK"
    assert_success
    assert [ -L "$TEST_LINK" ]
    run readlink "$TEST_LINK"
    assert_output "$TEST_TARGET"
}

@test "install_symlink: replaces wrong symlink" {
    ln -s "/wrong/target" "$TEST_LINK"
    run_install_symlink "$TEST_TARGET" "$TEST_LINK"
    assert_success
    assert [ -L "$TEST_LINK" ]
    run readlink "$TEST_LINK"
    assert_output "$TEST_TARGET"
}

@test "install_symlink: skips correct symlink" {
    ln -s "$TEST_TARGET" "$TEST_LINK"
    run_install_symlink "$TEST_TARGET" "$TEST_LINK"
    assert_success
    assert_output --partial "already correct"
}

@test "install_symlink: backs up regular file" {
    echo "regular file content" > "$TEST_LINK"
    run_install_symlink "$TEST_TARGET" "$TEST_LINK"
    assert_success
    assert [ -L "$TEST_LINK" ]
    assert [ -f "${TEST_LINK}.bak" ]
    run readlink "$TEST_LINK"
    assert_output "$TEST_TARGET"
    run cat "${TEST_LINK}.bak"
    assert_output "regular file content"
}
