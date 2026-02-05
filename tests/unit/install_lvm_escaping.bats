#!/usr/bin/env bats
# Tests for LVM device path escaping in scripts/install.sh

setup() {
    load '../helpers/test_helper'
    common_setup
}

teardown() {
    common_teardown
}

# The LVM escaping logic is at install.sh:187-189:
#   local vg_escaped="${LVM_VG//-/--}"
#   local lv_escaped="${LVM_LV_ROOT//-/--}"
#   cmdline="... root=/dev/mapper/${vg_escaped}-${lv_escaped}"

@test "LVM escaping: double-hyphens in VG name" {
    run bash -c '
        LVM_VG="gentoo-vg0"
        vg_escaped="${LVM_VG//-/--}"
        echo "$vg_escaped"
    '
    assert_success
    assert_output "gentoo--vg0"
}

@test "LVM escaping: double-hyphens in LV name" {
    run bash -c '
        LVM_LV_ROOT="root-fs"
        lv_escaped="${LVM_LV_ROOT//-/--}"
        echo "$lv_escaped"
    '
    assert_success
    assert_output "root--fs"
}

@test "LVM escaping: no-op when no hyphens" {
    run bash -c '
        LVM_VG="gentoovg0"
        LVM_LV_ROOT="root"
        vg_escaped="${LVM_VG//-/--}"
        lv_escaped="${LVM_LV_ROOT//-/--}"
        echo "/dev/mapper/${vg_escaped}-${lv_escaped}"
    '
    assert_success
    assert_output "/dev/mapper/gentoovg0-root"
}
