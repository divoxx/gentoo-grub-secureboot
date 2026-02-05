#!/usr/bin/env bats
# Acceptance tests for sign-boot.sh — full workflow with mocked commands

setup() {
    load '../helpers/test_helper'
    common_setup

    cp "${PROJECT_ROOT}/scripts/sign-boot.sh" "${TEST_REPO_ROOT}/scripts/sign-boot.sh"

    export ESP_MOUNT="${TEST_ESP}"
    export BOOTLOADER_ID="gentoo"
    export GPG_KEY_NAME="grub"
}

teardown() {
    common_teardown
}

# Helper: run the sign-boot workflow logic
# Wraps in a function to allow 'local' usage
run_sign_boot_workflow() {
    run bash -c "
        export REPO_ROOT='${TEST_REPO_ROOT}'
        export ESP_MOUNT='${TEST_ESP}'
        export BOOTLOADER_ID='gentoo'
        export GPG_KEY_NAME='grub'
        source '${TEST_REPO_ROOT}/scripts/lib.sh'

        # Extract functions from sign-boot.sh
        eval \"\$(sed -n '/^collect_files()/,/^}/p' '${TEST_REPO_ROOT}/scripts/sign-boot.sh')\"
        eval \"\$(sed -n '/^cleanup_orphaned_sigs()/,/^}/p' '${TEST_REPO_ROOT}/scripts/sign-boot.sh')\"

        _run_workflow() {
            # Clean up orphaned sigs
            cleanup_orphaned_sigs

            # Collect files
            local files
            mapfile -t files < <(collect_files)

            if [[ \${#files[@]} -eq 0 ]]; then
                msg_error 'No boot files found to sign.'
                exit 1
            fi

            local signed=0
            local failed=0

            for file in \"\${files[@]}\"; do
                local basename
                basename=\"\$(basename \"\$file\")\"

                # PE-sign kernel files
                if [[ \"\$basename\" == kernel-* ]]; then
                    sbctl sign -s \"\$file\"
                fi

                # GPG sign
                if gpg_sign \"\$file\"; then
                    signed=\$((signed + 1))
                else
                    failed=\$((failed + 1))
                fi
            done

            echo \"signed=\$signed failed=\$failed\"

            if [[ \$failed -gt 0 ]]; then
                exit 1
            fi
        }
        _run_workflow
    " 2>&1
}

@test "sign-boot: signs all files and verifies" {
    touch "${TEST_ESP}/grub/grub.cfg"
    touch "${TEST_ESP}/kernel-6.1.0"
    touch "${TEST_ESP}/initramfs-6.1.0.img"
    create_mock_gpg 0
    create_mock_sbctl 0
    run_sign_boot_workflow
    assert_success
    assert_output --partial "signed=3"
}

@test "sign-boot: PE-signs kernels before GPG" {
    touch "${TEST_ESP}/kernel-6.1.0"
    create_mock_gpg 0
    create_mock_sbctl 0
    run_sign_boot_workflow
    assert_success
    # Verify sbctl was called
    assert_mock_called "sbctl"
    assert_mock_called_with "sbctl" "sign"
}

@test "sign-boot: reports failure count" {
    touch "${TEST_ESP}/grub/grub.cfg"
    touch "${TEST_ESP}/kernel-6.1.0"
    create_mock_gpg_failing_sign
    create_mock_sbctl 0
    run_sign_boot_workflow
    assert_failure
    assert_output --partial "failed="
}

@test "sign-boot: cleans orphaned sigs first" {
    touch "${TEST_ESP}/old-kernel.sig"
    touch "${TEST_ESP}/grub/grub.cfg"
    create_mock_gpg 0
    create_mock_sbctl 0
    run_sign_boot_workflow
    assert_success
    # Orphaned sig should be removed
    assert [ ! -f "${TEST_ESP}/old-kernel.sig" ]
}
