#!/usr/bin/env bats
# Tests for UUID validation regex in scripts/build-grub.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

# Helper: test UUID validation using the same regex from build-grub.sh:53
validate_uuid() {
    local uuid="$1"
    [[ "$uuid" =~ ^[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}$ ]]
}

@test "UUID validation: accepts valid D728-8DD1" {
    run validate_uuid "D728-8DD1"
    assert_success
}

@test "UUID validation: accepts lowercase d728-8dd1" {
    run validate_uuid "d728-8dd1"
    assert_success
}

@test "UUID validation: rejects short D72-8DD1" {
    run validate_uuid "D72-8DD1"
    assert_failure
}

@test "UUID validation: rejects no hyphen D7288DD1" {
    run validate_uuid "D7288DD1"
    assert_failure
}

@test "UUID validation: rejects full GPT UUID" {
    run validate_uuid "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
    assert_failure
}

@test "UUID validation: rejects empty string" {
    run validate_uuid ""
    assert_failure
}

@test "UUID validation: rejects non-hex GHIJ-KLMN" {
    run validate_uuid "GHIJ-KLMN"
    assert_failure
}
