#!/usr/bin/env bash
# mock_commands.bash — Mock generators for external commands
#
# All mocks log their invocations to TEST_MOCK_BIN/<cmd>.calls
# for assertion purposes.

# ---------------------------------------------------------------------------
# Generic mock creator
# ---------------------------------------------------------------------------
# create_mock <cmd> [exit_code] [stdout_output]
create_mock() {
    local cmd="$1"
    local exit_code="${2:-0}"
    local output="${3:-}"
    local mock_path="${TEST_MOCK_BIN}/${cmd}"

    cat > "$mock_path" << MOCKEOF
#!/usr/bin/env bash
# Mock for: ${cmd}
echo "\$0 \$*" >> "${TEST_MOCK_BIN}/${cmd}.calls"
MOCKEOF

    if [[ -n "$output" ]]; then
        # Use printf to handle multi-line output
        printf 'cat << '"'"'OUTPUT'"'"'\n%s\nOUTPUT\n' "$output" >> "$mock_path"
    fi

    echo "exit ${exit_code}" >> "$mock_path"
    chmod +x "$mock_path"
}

# ---------------------------------------------------------------------------
# Stat mock (for machine.conf ownership checks)
# ---------------------------------------------------------------------------
# create_mock_stat_root_owned — reports 0:0 owner, root:root names, 600 perms
create_mock_stat_root_owned() {
    local mock_path="${TEST_MOCK_BIN}/stat"
    cat > "$mock_path" << 'MOCKEOF'
#!/usr/bin/env bash
echo "$0 $*" >> "${TEST_MOCK_BIN}/stat.calls"

# Parse the format string
for arg in "$@"; do
    case "$arg" in
        -c) continue ;;
        '%u:%g') echo "0:0"; exit 0 ;;
        '%U:%G') echo "root:root"; exit 0 ;;
        '%a')    echo "600"; exit 0 ;;
        -*)      continue ;;
        *)       continue ;;
    esac
done
# Fallback: pass through format string
# Handle combined -c 'format' usage
local fmt=""
local next_is_fmt=false
for arg in "$@"; do
    if [[ "$next_is_fmt" == true ]]; then
        fmt="$arg"
        next_is_fmt=false
        continue
    fi
    case "$arg" in
        -c) next_is_fmt=true ;;
    esac
done

case "$fmt" in
    '%u:%g') echo "0:0"; exit 0 ;;
    '%U:%G') echo "root:root"; exit 0 ;;
    '%a')    echo "600"; exit 0 ;;
esac
exit 0
MOCKEOF
    # Inject TEST_MOCK_BIN path
    sed -i "s|\${TEST_MOCK_BIN}|${TEST_MOCK_BIN}|g" "$mock_path"
    chmod +x "$mock_path"
}

# create_mock_stat — reports custom owner and perms
# Usage: create_mock_stat <uid:gid> <user:group> <perms>
create_mock_stat() {
    local owner_ids="$1"
    local owner_names="$2"
    local perms="$3"
    local mock_path="${TEST_MOCK_BIN}/stat"
    cat > "$mock_path" << MOCKEOF
#!/usr/bin/env bash
echo "\$0 \$*" >> "${TEST_MOCK_BIN}/stat.calls"

fmt=""
next_is_fmt=false
for arg in "\$@"; do
    if [[ "\$next_is_fmt" == true ]]; then
        fmt="\$arg"
        next_is_fmt=false
        continue
    fi
    case "\$arg" in
        -c) next_is_fmt=true ;;
    esac
done

case "\$fmt" in
    '%u:%g') echo "${owner_ids}"; exit 0 ;;
    '%U:%G') echo "${owner_names}"; exit 0 ;;
    '%a')    echo "${perms}"; exit 0 ;;
esac
exit 0
MOCKEOF
    sed -i "s|\${TEST_MOCK_BIN}|${TEST_MOCK_BIN}|g" "$mock_path"
    chmod +x "$mock_path"
}

# ---------------------------------------------------------------------------
# GPG mock
# ---------------------------------------------------------------------------
create_mock_gpg() {
    local default_exit="${1:-0}"
    local mock_path="${TEST_MOCK_BIN}/gpg"
    cat > "$mock_path" << MOCKEOF
#!/usr/bin/env bash
echo "\$0 \$*" >> "${TEST_MOCK_BIN}/gpg.calls"

# Parse arguments
action=""
output_file=""
prev=""
for arg in "\$@"; do
    case "\$prev" in
        --output) output_file="\$arg" ;;
    esac
    case "\$arg" in
        --detach-sign) action="sign" ;;
        --verify)      action="verify" ;;
        --export)      action="export" ;;
        --list-keys)   action="list-keys" ;;
    esac
    prev="\$arg"
done

case "\$action" in
    sign)
        if [[ -n "\$output_file" ]]; then
            echo "mock-signature-data" > "\$output_file"
        fi
        exit ${default_exit}
        ;;
    verify)
        exit ${default_exit}
        ;;
    export)
        echo "mock-gpg-public-key-data"
        exit ${default_exit}
        ;;
    list-keys)
        exit ${default_exit}
        ;;
esac
exit ${default_exit}
MOCKEOF
    sed -i "s|\${TEST_MOCK_BIN}|${TEST_MOCK_BIN}|g" "$mock_path"
    chmod +x "$mock_path"
}

# create_mock_gpg_failing_sign — GPG that fails on --detach-sign only
create_mock_gpg_failing_sign() {
    local mock_path="${TEST_MOCK_BIN}/gpg"
    cat > "$mock_path" << MOCKEOF
#!/usr/bin/env bash
echo "\$0 \$*" >> "${TEST_MOCK_BIN}/gpg.calls"

action=""
output_file=""
prev=""
for arg in "\$@"; do
    case "\$prev" in
        --output) output_file="\$arg" ;;
    esac
    case "\$arg" in
        --detach-sign) action="sign" ;;
        --verify)      action="verify" ;;
        --export)      action="export" ;;
        --list-keys)   action="list-keys" ;;
    esac
    prev="\$arg"
done

case "\$action" in
    sign)
        exit 1
        ;;
    verify)
        exit 0
        ;;
    export)
        echo "mock-gpg-public-key-data"
        exit 0
        ;;
    list-keys)
        exit 0
        ;;
esac
exit 0
MOCKEOF
    sed -i "s|\${TEST_MOCK_BIN}|${TEST_MOCK_BIN}|g" "$mock_path"
    chmod +x "$mock_path"
}

# ---------------------------------------------------------------------------
# sbctl mock
# ---------------------------------------------------------------------------
create_mock_sbctl() {
    local default_exit="${1:-0}"
    local mock_path="${TEST_MOCK_BIN}/sbctl"
    cat > "$mock_path" << MOCKEOF
#!/usr/bin/env bash
echo "\$0 \$*" >> "${TEST_MOCK_BIN}/sbctl.calls"

action="\$1"
case "\$action" in
    sign)     exit ${default_exit} ;;
    verify)   echo "\$2 is signed"; exit ${default_exit} ;;
    sign-all) exit ${default_exit} ;;
    status)   echo "Secure Boot: Enabled"; exit ${default_exit} ;;
esac
exit ${default_exit}
MOCKEOF
    sed -i "s|\${TEST_MOCK_BIN}|${TEST_MOCK_BIN}|g" "$mock_path"
    chmod +x "$mock_path"
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

# assert_mock_called <cmd>
assert_mock_called() {
    local cmd="$1"
    local calls_file="${TEST_MOCK_BIN}/${cmd}.calls"
    assert [ -f "$calls_file" ]
}

# assert_mock_not_called <cmd>
assert_mock_not_called() {
    local cmd="$1"
    local calls_file="${TEST_MOCK_BIN}/${cmd}.calls"
    assert [ ! -f "$calls_file" ]
}

# assert_mock_called_with <cmd> <substring>
assert_mock_called_with() {
    local cmd="$1"
    local expected="$2"
    local calls_file="${TEST_MOCK_BIN}/${cmd}.calls"
    assert [ -f "$calls_file" ]
    run grep -F "$expected" "$calls_file"
    assert_success
}

# get_mock_call_count <cmd>
get_mock_call_count() {
    local cmd="$1"
    local calls_file="${TEST_MOCK_BIN}/${cmd}.calls"
    if [[ -f "$calls_file" ]]; then
        wc -l < "$calls_file"
    else
        echo "0"
    fi
}
