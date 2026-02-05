#!/usr/bin/env bats
# Acceptance tests for update-boot.sh — full workflow with mocked commands

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/update-boot.sh" "${TEST_REPO_ROOT}/scripts/update-boot.sh"

    export ESP_MOUNT="${TEST_ESP}"
    export BOOTLOADER_ID="gentoo"
    export GPG_KEY_NAME="grub"
}

teardown() {
    common_teardown
}

# Helper: run update-boot workflow with mocked commands
run_update_boot_workflow() {
    local mkconfig_exit="${1:-0}"
    local sign_boot_exit="${2:-0}"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='gentoo'
        export GPG_KEY_NAME='grub'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'

        grub_cfg=\"\$(grub_cfg_path)\"
        mkdir -p \"\$(dirname \"\$grub_cfg\")\"

        # Step 1: sbctl sign-all
        sbctl sign-all
        msg_ok 'PE signatures updated.'

        # Step 2: Backup + grub-mkconfig
        if [[ -f \"\$grub_cfg\" && -f \"\${grub_cfg}.sig\" ]]; then
            cp \"\$grub_cfg\" \"\${grub_cfg}.bak\"
            cp \"\${grub_cfg}.sig\" \"\${grub_cfg}.sig.bak\"
        fi

        if ! grub-mkconfig -o \"\$grub_cfg\"; then
            msg_error 'grub-mkconfig failed — restoring backup'
            if [[ -f \"\${grub_cfg}.bak\" ]]; then
                mv \"\${grub_cfg}.bak\" \"\$grub_cfg\"
                [[ -f \"\${grub_cfg}.sig.bak\" ]] && mv \"\${grub_cfg}.sig.bak\" \"\${grub_cfg}.sig\"
                msg_ok 'Backup restored'
            fi
            exit 1
        fi

        # Step 3: sign-boot
        if ! sign-boot; then
            msg_error 'sign-boot failed — restoring backup'
            if [[ -f \"\${grub_cfg}.bak\" ]]; then
                mv \"\${grub_cfg}.bak\" \"\$grub_cfg\"
                [[ -f \"\${grub_cfg}.sig.bak\" ]] && mv \"\${grub_cfg}.sig.bak\" \"\${grub_cfg}.sig\"
                msg_ok 'Backup restored'
            fi
            exit 1
        fi

        rm -f \"\${grub_cfg}.bak\" \"\${grub_cfg}.sig.bak\"
        msg_ok 'Boot update complete'
    " 2>&1
}

@test "update-boot: full workflow in order" {
    echo "original-cfg" > "${TEST_ESP}/grub/grub.cfg"
    echo "original-sig" > "${TEST_ESP}/grub/grub.cfg.sig"
    create_mock_sbctl 0
    create_mock "grub-mkconfig" 0 "# new config"
    create_mock "sign-boot" 0
    run_update_boot_workflow
    assert_success
    assert_output --partial "PE signatures updated"
    assert_output --partial "Boot update complete"
    # Verify mocks were called in order
    assert_mock_called "sbctl"
    assert_mock_called "grub-mkconfig"
    assert_mock_called "sign-boot"
}

@test "update-boot: rollback on grub-mkconfig failure" {
    echo "original-cfg" > "${TEST_ESP}/grub/grub.cfg"
    echo "original-sig" > "${TEST_ESP}/grub/grub.cfg.sig"
    create_mock_sbctl 0
    create_mock "grub-mkconfig" 1
    create_mock "sign-boot" 0
    run_update_boot_workflow
    assert_failure
    assert_output --partial "restoring backup"
    # Verify original content restored
    run cat "${TEST_ESP}/grub/grub.cfg"
    assert_output "original-cfg"
    run cat "${TEST_ESP}/grub/grub.cfg.sig"
    assert_output "original-sig"
}

@test "update-boot: rollback on sign-boot failure" {
    echo "original-cfg" > "${TEST_ESP}/grub/grub.cfg"
    echo "original-sig" > "${TEST_ESP}/grub/grub.cfg.sig"
    create_mock_sbctl 0
    create_mock "grub-mkconfig" 0 "# new config"
    create_mock "sign-boot" 1
    run_update_boot_workflow
    assert_failure
    assert_output --partial "restoring backup"
    # Verify original content restored
    run cat "${TEST_ESP}/grub/grub.cfg"
    assert_output "original-cfg"
    run cat "${TEST_ESP}/grub/grub.cfg.sig"
    assert_output "original-sig"
}
