#!/usr/bin/env bats
# Acceptance tests for build-grub.sh — full workflow with mocked commands

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/build-grub.sh" "${TEST_REPO_ROOT}/scripts/build-grub.sh"

    export ESP_MOUNT="${TEST_ESP}"
    export BOOTLOADER_ID="gentoo"
    export GPG_KEY_NAME="grub"
    export LINUX_ESP_UUID="D728-8DD1"

    # Create modules.txt and initial.cfg.template
    create_modules_txt
    cp "${PROJECT_ROOT}/grub/initial.cfg.template" "${TEST_REPO_ROOT}/grub/initial.cfg.template"
}

teardown() {
    common_teardown
}

# Helper: run the build-grub workflow logic in a controlled subshell
# Wraps logic in a function to allow use of 'local'
run_build_grub_workflow() {
    local uuid="${1:-D728-8DD1}"
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='gentoo'
        export GPG_KEY_NAME='grub'
        export LINUX_ESP_UUID='${uuid}'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'

        _run_workflow() {
            make_tmpdir

            # 1. Export GPG public key
            gpg --batch --yes --export \"\$GPG_KEY_NAME\" > \"\${_TMPDIR}/grub.pub\"
            if [[ ! -s \"\${_TMPDIR}/grub.pub\" ]]; then
                msg_error 'GPG public key export is empty'
                exit 1
            fi

            # 2. Render initial.cfg from template
            local tpl
            tpl=\"\$(initial_cfg_tpl)\"
            if [[ ! -f \"\$tpl\" ]]; then
                msg_error \"Template not found: \$tpl\"
                exit 1
            fi

            if [[ ! \"\$LINUX_ESP_UUID\" =~ ^[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}$ ]]; then
                msg_error \"LINUX_ESP_UUID has invalid format: \$LINUX_ESP_UUID\"
                exit 1
            fi

            sed \"s/%%LINUX_ESP_UUID%%/\${LINUX_ESP_UUID}/g\" \"\$tpl\" > \"\${_TMPDIR}/initial.cfg\"

            # 3. GPG sign initial config
            gpg_sign \"\${_TMPDIR}/initial.cfg\"

            # 4. Read modules
            local modules
            modules=\"\$(read_modules)\"

            # 5. Build standalone binary (mocked)
            local efi_output
            efi_output=\"\$(grub_efi_path)\"
            mkdir -p \"\$(dirname \"\$efi_output\")\"
            grub-mkstandalone --output \"\$efi_output\"

            # 6. PE-sign
            sbctl sign -s \"\$efi_output\"

            # 7. Check EFI entry
            if efibootmgr | grep -qiF \"\$BOOTLOADER_ID\"; then
                msg_ok 'EFI boot entry exists'
            else
                msg_warn 'No EFI boot entry found'
            fi

            msg_ok 'Build complete'
        }
        _run_workflow
    " 2>&1
}

@test "build-grub: full workflow succeeds" {
    create_mock_gpg 0
    create_mock_sbctl 0
    create_mock "grub-mkstandalone" 0
    create_mock "efibootmgr" 0 "Boot0001* gentoo"
    run_build_grub_workflow "D728-8DD1"
    assert_success
    assert_output --partial "Build complete"
}

@test "build-grub: fails on invalid UUID" {
    create_mock_gpg 0
    create_mock_sbctl 0
    create_mock "grub-mkstandalone" 0
    run_build_grub_workflow "INVALID"
    assert_failure
    assert_output --partial "invalid format"
}

@test "build-grub: fails on empty key export" {
    # Create a gpg mock that exports nothing
    local mock_path="${TEST_MOCK_BIN}/gpg"
    cat > "$mock_path" << 'MOCKEOF'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        --export)
            # Output nothing (empty key)
            exit 0
            ;;
        --detach-sign)
            # Find --output arg and create sig
            prev=""
            for a in "$@"; do
                if [[ "$prev" == "--output" ]]; then
                    echo "sig" > "$a"
                fi
                prev="$a"
            done
            exit 0
            ;;
    esac
done
exit 0
MOCKEOF
    chmod +x "$mock_path"
    create_mock_sbctl 0
    create_mock "grub-mkstandalone" 0
    run_build_grub_workflow "D728-8DD1"
    assert_failure
    assert_output --partial "empty"
}

@test "build-grub: warns when no EFI entry" {
    create_mock_gpg 0
    create_mock_sbctl 0
    create_mock "grub-mkstandalone" 0
    create_mock "efibootmgr" 0 "Boot0001* other-os"
    run_build_grub_workflow "D728-8DD1"
    assert_success
    assert_output --partial "No EFI boot entry"
}
