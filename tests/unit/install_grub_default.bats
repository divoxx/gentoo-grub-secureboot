#!/usr/bin/env bats
# Tests for grub_default_set() and grub_default_remove() from scripts/install.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    # Copy install.sh into mock repo
    cp "${PROJECT_ROOT}/scripts/install.sh" "${TEST_REPO_ROOT}/scripts/install.sh"

    # Create a test grub defaults file
    TEST_GRUB_FILE="${TEST_TMPDIR}/grub_defaults"
    cp "${TESTS_DIR}/fixtures/grub_defaults_basic" "$TEST_GRUB_FILE"
}

teardown() {
    common_teardown
}

# Helper: source only the functions we need (skip main, require_root, load_config)
source_install_functions() {
    export REPO_ROOT="$TEST_REPO_ROOT"
    source "${TEST_REPO_ROOT}/scripts/lib.sh"
    # Re-define grub_default_set and grub_default_remove by extracting them
    eval "$(sed -n '/^grub_default_set()/,/^}/p' "${TEST_REPO_ROOT}/scripts/install.sh")"
    eval "$(sed -n '/^grub_default_remove()/,/^}/p' "${TEST_REPO_ROOT}/scripts/install.sh")"
}

@test "grub_default_set: appends new key to file" {
    local file="${TEST_TMPDIR}/grub_empty"
    touch "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        $(declare -f source_install_functions 2>/dev/null || true)
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_TIMEOUT' '5' '${file}'
    "
    assert_success
    run grep -c 'GRUB_TIMEOUT=5' "$file"
    assert_output "1"
}

@test "grub_default_set: replaces existing key" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_TIMEOUT' '10' '${TEST_GRUB_FILE}'
    "
    assert_success
    run grep 'GRUB_TIMEOUT' "$TEST_GRUB_FILE"
    assert_output "GRUB_TIMEOUT=10"
}

@test "grub_default_set: uncomments and replaces commented key" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_CMDLINE_LINUX_DEFAULT' '\"quiet splash\"' '${TEST_GRUB_FILE}'
    "
    assert_success
    run grep 'GRUB_CMDLINE_LINUX_DEFAULT' "$TEST_GRUB_FILE"
    assert_output 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"'
}

@test "grub_default_set: uncomments '# KEY=val' format" {
    local file="${TEST_TMPDIR}/grub_spaced"
    echo '# GRUB_TIMEOUT=10' > "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_TIMEOUT' '5' '${file}'
    "
    assert_success
    run grep 'GRUB_TIMEOUT' "$file"
    assert_output "GRUB_TIMEOUT=5"
}

@test "grub_default_set: handles value with quotes" {
    local file="${TEST_TMPDIR}/grub_quotes"
    touch "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_CMDLINE_LINUX' '\"quiet splash\"' '${file}'
    "
    assert_success
    run grep 'GRUB_CMDLINE_LINUX' "$file"
    assert_output 'GRUB_CMDLINE_LINUX="quiet splash"'
}

@test "grub_default_set: preserves other lines" {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_TIMEOUT' '10' '${TEST_GRUB_FILE}'
    "
    assert_success
    run grep 'GRUB_DEFAULT=0' "$TEST_GRUB_FILE"
    assert_success
}

@test "grub_default_set: handles special sed chars in value" {
    local file="${TEST_TMPDIR}/grub_special"
    touch "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_CMDLINE_LINUX' '\"root=/dev/mapper/vg-root\"' '${file}'
    "
    assert_success
    run grep 'GRUB_CMDLINE_LINUX' "$file"
    assert_output 'GRUB_CMDLINE_LINUX="root=/dev/mapper/vg-root"'
}

@test "grub_default_set: replaces only first match" {
    local file="${TEST_TMPDIR}/grub_dupe"
    printf 'GRUB_TIMEOUT=5\nGRUB_TIMEOUT=5\n' > "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_set()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_set 'GRUB_TIMEOUT' '10' '${file}'
    "
    assert_success
    # First line should be changed, second should remain
    run sed -n '1p' "$file"
    assert_output "GRUB_TIMEOUT=10"
    run sed -n '2p' "$file"
    assert_output "GRUB_TIMEOUT=5"
}

@test "grub_default_remove: deletes existing key" {
    local file="${TEST_TMPDIR}/grub_remove"
    printf 'GRUB_TIMEOUT=5\nGRUB_OS_PROBER_SKIP_LIST=""\nGRUB_DEFAULT=0\n' > "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_remove()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_remove 'GRUB_OS_PROBER_SKIP_LIST' '${file}'
    "
    assert_success
    run grep 'GRUB_OS_PROBER_SKIP_LIST' "$file"
    assert_failure
}

@test "grub_default_remove: deletes commented key" {
    local file="${TEST_TMPDIR}/grub_remove_comment"
    printf 'GRUB_TIMEOUT=5\n#GRUB_OS_PROBER_SKIP_LIST=""\n' > "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_remove()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_remove 'GRUB_OS_PROBER_SKIP_LIST' '${file}'
    "
    assert_success
    run grep 'GRUB_OS_PROBER_SKIP_LIST' "$file"
    assert_failure
}

@test "grub_default_remove: no-op if key absent" {
    local file="${TEST_TMPDIR}/grub_noop"
    printf 'GRUB_TIMEOUT=5\nGRUB_DEFAULT=0\n' > "$file"
    local before
    before="$(cat "$file")"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_remove()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_remove 'GRUB_NONEXISTENT' '${file}'
    "
    assert_success
    local after
    after="$(cat "$file")"
    [[ "$before" == "$after" ]]
}

@test "grub_default_remove: preserves other lines" {
    local file="${TEST_TMPDIR}/grub_preserve"
    printf 'GRUB_TIMEOUT=5\nGRUB_OS_PROBER_SKIP_LIST=""\nGRUB_DEFAULT=0\n' > "$file"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        eval \"\$(sed -n '/^grub_default_remove()/,/^}/p' '${TEST_REPO_ROOT}/scripts/install.sh')\"
        grub_default_remove 'GRUB_OS_PROBER_SKIP_LIST' '${file}'
    "
    assert_success
    run grep 'GRUB_TIMEOUT=5' "$file"
    assert_success
    run grep 'GRUB_DEFAULT=0' "$file"
    assert_success
}
