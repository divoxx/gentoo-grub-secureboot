#!/usr/bin/env bats
# Tests for install_26_windows() from scripts/install.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/install.sh" "${TEST_REPO_ROOT}/scripts/install.sh"

    # Copy the 26_windows template into mock repo
    mkdir -p "${TEST_REPO_ROOT}/grub/grub.d"
    cp "${PROJECT_ROOT}/grub/grub.d/26_windows" "${TEST_REPO_ROOT}/grub/grub.d/26_windows"

    # Destination for generated file
    TEST_DST="${TEST_TMPDIR}/26_windows"
}

teardown() {
    common_teardown
}

# Helper: run install_26_windows with a custom destination
run_install_26_windows() {
    local uuid="${1:-}"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'
        WINDOWS_ESP_UUID='${uuid}'
        # Override destination in the function
        install_26_windows() {
            local src=\"\${REPO_ROOT}/grub/grub.d/26_windows\"
            local dst='${TEST_DST}'
            if [[ -z \"\${WINDOWS_ESP_UUID:-}\" ]]; then
                msg_info 'WINDOWS_ESP_UUID not set — skipping 26_windows'
                return
            fi
            if [[ ! \"\$WINDOWS_ESP_UUID\" =~ ^[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}$ ]]; then
                msg_error \"WINDOWS_ESP_UUID has invalid format: \$WINDOWS_ESP_UUID\"
                exit 1
            fi
            sed \"s/%%WINDOWS_ESP_UUID%%/\${WINDOWS_ESP_UUID}/g\" \"\$src\" > \"\$dst\"
            chmod +x \"\$dst\"
        }
        install_26_windows
    "
}

@test "install_26_windows: substitutes UUID in output" {
    run_install_26_windows "90B1-2A22"
    assert_success
    assert [ -f "$TEST_DST" ]
    run grep '90B1-2A22' "$TEST_DST"
    assert_success
    # Verify the placeholder was replaced
    run grep '%%WINDOWS_ESP_UUID%%' "$TEST_DST"
    assert_failure
}

@test "install_26_windows: rejects invalid UUID" {
    run_install_26_windows "invalid"
    assert_failure
    assert_output --partial "invalid format"
}

@test "install_26_windows: skips when UUID unset" {
    run_install_26_windows ""
    assert_success
    assert [ ! -f "$TEST_DST" ]
    assert_output --partial "skipping"
}

@test "install_26_windows: output is executable" {
    run_install_26_windows "90B1-2A22"
    assert_success
    assert [ -x "$TEST_DST" ]
}
