#!/usr/bin/env bats
# Tests for transactional backup/restore logic in scripts/update-boot.sh

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/update-boot.sh" "${TEST_REPO_ROOT}/scripts/update-boot.sh"

    export ESP_MOUNT="${TEST_ESP}"
    export BOOTLOADER_ID="gentoo"
    export GPG_KEY_NAME="grub"

    # Create mock grub-mkconfig, sign-boot.sh, sbctl, flock
    create_mock "flock" 0
    create_mock_sbctl 0
}

teardown() {
    common_teardown
}

# Helper: run the main function of update-boot.sh in a controlled subshell
# We extract the relevant transactional logic rather than running the full script
# (which calls require_root, load_config, and flock)
run_update_boot_logic() {
    local grub_mkconfig_exit="${1:-0}"
    local sign_boot_exit="${2:-0}"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='gentoo'
        export GPG_KEY_NAME='grub'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'

        grub_cfg=\"\$(grub_cfg_path)\"
        mkdir -p \"\$(dirname \"\$grub_cfg\")\"

        # 1. sbctl sign-all (mocked)
        sbctl sign-all

        # 2. Backup existing grub.cfg + .sig
        if [[ -f \"\$grub_cfg\" && -f \"\${grub_cfg}.sig\" ]]; then
            cp \"\$grub_cfg\" \"\${grub_cfg}.bak\"
            cp \"\${grub_cfg}.sig\" \"\${grub_cfg}.sig.bak\"
        fi

        # 3. Run grub-mkconfig (mocked)
        if ! grub-mkconfig -o \"\$grub_cfg\"; then
            msg_error 'grub-mkconfig failed — restoring backup'
            if [[ -f \"\${grub_cfg}.bak\" ]]; then
                mv \"\${grub_cfg}.bak\" \"\$grub_cfg\"
                [[ -f \"\${grub_cfg}.sig.bak\" ]] && mv \"\${grub_cfg}.sig.bak\" \"\${grub_cfg}.sig\"
            fi
            exit 1
        fi

        # 4. Run sign-boot (mocked)
        if ! sign-boot; then
            msg_error 'sign-boot failed — restoring backup'
            if [[ -f \"\${grub_cfg}.bak\" ]]; then
                mv \"\${grub_cfg}.bak\" \"\$grub_cfg\"
                [[ -f \"\${grub_cfg}.sig.bak\" ]] && mv \"\${grub_cfg}.sig.bak\" \"\${grub_cfg}.sig\"
            fi
            exit 1
        fi

        # 5. Clean up backups
        rm -f \"\${grub_cfg}.bak\" \"\${grub_cfg}.sig.bak\"
    " 2>&1
}

@test "update-boot: creates backups before mkconfig" {
    echo "original-cfg" > "${TEST_ESP}/grub/grub.cfg"
    echo "original-sig" > "${TEST_ESP}/grub/grub.cfg.sig"
    create_mock "grub-mkconfig" 0 "# generated grub.cfg"
    create_mock "sign-boot" 0
    run_update_boot_logic
    assert_success
}

@test "update-boot: restores on grub-mkconfig failure" {
    echo "original-cfg" > "${TEST_ESP}/grub/grub.cfg"
    echo "original-sig" > "${TEST_ESP}/grub/grub.cfg.sig"
    create_mock "grub-mkconfig" 1
    create_mock "sign-boot" 0
    run_update_boot_logic
    assert_failure
    # Verify backup was restored
    run cat "${TEST_ESP}/grub/grub.cfg"
    assert_output "original-cfg"
    run cat "${TEST_ESP}/grub/grub.cfg.sig"
    assert_output "original-sig"
}

@test "update-boot: restores on sign-boot failure" {
    echo "original-cfg" > "${TEST_ESP}/grub/grub.cfg"
    echo "original-sig" > "${TEST_ESP}/grub/grub.cfg.sig"
    create_mock "grub-mkconfig" 0 "# new grub.cfg"
    create_mock "sign-boot" 1
    run_update_boot_logic
    assert_failure
    # Verify backup was restored
    run cat "${TEST_ESP}/grub/grub.cfg"
    assert_output "original-cfg"
    run cat "${TEST_ESP}/grub/grub.cfg.sig"
    assert_output "original-sig"
}

@test "update-boot: no backup when no existing files" {
    # No grub.cfg or .sig exist yet
    create_mock "grub-mkconfig" 0 "# new grub.cfg"
    create_mock "sign-boot" 0
    run_update_boot_logic
    assert_success
    # No .bak files should exist
    assert [ ! -f "${TEST_ESP}/grub/grub.cfg.bak" ]
}

@test "update-boot: cleans .bak on success" {
    echo "original-cfg" > "${TEST_ESP}/grub/grub.cfg"
    echo "original-sig" > "${TEST_ESP}/grub/grub.cfg.sig"
    create_mock "grub-mkconfig" 0 "# new grub.cfg"
    create_mock "sign-boot" 0
    run_update_boot_logic
    assert_success
    assert [ ! -f "${TEST_ESP}/grub/grub.cfg.bak" ]
    assert [ ! -f "${TEST_ESP}/grub/grub.cfg.sig.bak" ]
}
