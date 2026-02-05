#!/usr/bin/env bash
# test_helper.bash — Shared setup for all bats tests
#
# Provides per-test isolation via temporary directories and loads
# bats helper libraries.

# Locate tests/ directory relative to this file
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Load bats helpers
load "${TESTS_DIR}/bats-support/load"
load "${TESTS_DIR}/bats-assert/load"
load "${TESTS_DIR}/bats-file/load"

# Load mock command generators
load "${TESTS_DIR}/helpers/mock_commands"

# ---------------------------------------------------------------------------
# Per-test setup / teardown — call common_setup in your test's setup()
# ---------------------------------------------------------------------------
common_setup() {
    # Ephemeral temp dir per test
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats-test.XXXXXXXXXX")"

    # Mock repo tree
    TEST_REPO_ROOT="${TEST_TMPDIR}/repo"
    mkdir -p "${TEST_REPO_ROOT}/scripts"
    mkdir -p "${TEST_REPO_ROOT}/grub/grub.d"
    mkdir -p "${TEST_REPO_ROOT}/hooks"

    # Mock ESP
    TEST_ESP="${TEST_TMPDIR}/esp"
    mkdir -p "${TEST_ESP}/EFI/gentoo"
    mkdir -p "${TEST_ESP}/grub"

    # Mock bin directory (prepended to PATH for mock command injection)
    TEST_MOCK_BIN="${TEST_TMPDIR}/mock-bin"
    mkdir -p "$TEST_MOCK_BIN"
    export PATH="${TEST_MOCK_BIN}:${PATH}"

    # Copy real lib.sh into mock repo
    cp "${PROJECT_ROOT}/scripts/lib.sh" "${TEST_REPO_ROOT}/scripts/lib.sh"

    # Export REPO_ROOT override so lib.sh uses our mock tree
    export REPO_ROOT="$TEST_REPO_ROOT"
}

common_teardown() {
    if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR:-}" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Default setup/teardown — overridden by test files that define their own
setup() {
    common_setup
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# Helper: create a valid machine.conf in the mock repo
# ---------------------------------------------------------------------------
create_machine_conf() {
    local conf="${TEST_REPO_ROOT}/machine.conf"
    cat > "$conf" << 'EOF'
LINUX_ESP_UUID="D728-8DD1"
BOOTLOADER_ID="gentoo"
ESP_MOUNT="/boot"
GPG_KEY_NAME="grub"
EOF
    # Mock stat to report root ownership and 600 perms
    create_mock_stat_root_owned
}

# Helper: create machine.conf with custom content
create_machine_conf_from() {
    local content="$1"
    local conf="${TEST_REPO_ROOT}/machine.conf"
    echo "$content" > "$conf"
    create_mock_stat_root_owned
}

# Helper: create a valid modules.txt in mock repo
create_modules_txt() {
    local content="${1:-}"
    local file="${TEST_REPO_ROOT}/grub/modules.txt"
    if [[ -n "$content" ]]; then
        echo "$content" > "$file"
    else
        cat > "$file" << 'EOF'
# Core modules
normal
configfile
linux

# Search
search
search_fs_uuid

# Crypto
pgp
gcry_sha512
EOF
    fi
}

# Helper: source lib.sh in a subshell with test environment
# Usage: run source_lib_sh
source_lib_sh() {
    export REPO_ROOT="$TEST_REPO_ROOT"
    source "${TEST_REPO_ROOT}/scripts/lib.sh"
}
