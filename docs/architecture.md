# Architecture

This document explains the two-layer boot chain architecture implemented by gentoo-grub-secureboot.

## Table of Contents

- [Overview](#overview)
- [Boot Chain](#boot-chain)
- [Two-Layer Security Model](#two-layer-security-model)
- [Implementation Strategy](#implementation-strategy)
- [File Signatures](#file-signatures)
- [Signing Order](#signing-order)
- [Disk Layout](#disk-layout)
- [Security Model](#security-model)

## Overview

The gentoo-grub-secureboot project implements a dual-signature boot chain combining UEFI Secure Boot (PE/Authenticode) with GRUB's GPG signature verification. This architecture provides defense-in-depth against unauthorized boot-time modifications.

## Boot Chain

The boot process follows this sequence:

1. **UEFI Firmware Validation**: The UEFI firmware validates `grubx64.efi` using PE/Authenticode signatures with sbctl custom keys and Microsoft keys.

2. **GRUB Initialization**: GRUB starts as a standalone binary with an embedded GPG public key and initial configuration.

3. **Signature Enforcement**: The initial embedded configuration sets `check_signatures=enforce` before processing any external files.

4. **GPG Verification**: GRUB verifies GPG signatures on all critical boot files:
   - `grub.cfg`
   - `kernel-*`
   - `initramfs-*.img`
   - CPU microcode (`amd-uc.img`, `intel-uc.img`)

5. **Windows Boot Path**: When booting Windows, GRUB temporarily disables GPG signature checking and chainloads `bootmgfw.efi`. The UEFI firmware continues to validate the Microsoft PE signature on the Windows bootloader.

## Two-Layer Security Model

### Layer 1: UEFI Secure Boot (PE/Authenticode)

- Validates EFI binaries using platform firmware
- Uses custom sbctl keys + Microsoft keys
- Protects against bootloader replacement attacks

### Layer 2: GRUB GPG Signatures

- Validates configuration files, kernels, and initramfs images
- Enforced before loading any external files
- Provides protection even if UEFI validation is bypassed

### Firmware Quirk Mitigation

This system has a firmware quirk where the firmware may execute binaries even when Secure Boot validation fails. This makes the GRUB GPG layer the **primary security layer** rather than a supplementary one.

## Implementation Strategy

### Why grub-mkstandalone

The project uses `grub-mkstandalone` instead of traditional `grub-install` for several reasons:

- **Recommended Approach**: The Gentoo Security Handbook and wiki recommend this method for Secure Boot setups.

- **Reliability**: `grub-install --pubkey` has documented reliability issues on some distributions.

- **Module Embedding**: All GRUB modules are embedded directly into the EFI binary, eliminating the need for separate `.mod` files on disk.

- **Reduced Signature Burden**: Only ~5 files require GPG signatures instead of 360+ module files.

- **Guaranteed Enforcement**: Signature checking is more reliably enforced when modules are embedded.

### How grub-mkstandalone Works

1. **Module Bundling**: `grub-mkstandalone` bundles all specified GRUB modules into the EFI binary itself.

2. **Implicit Enforcement**: The `--pubkey` flag causes `grub-mkimage` to implicitly set `check_signatures=enforce` in the core image.

3. **Embedded Configuration**: An initial embedded configuration provides fallback enforcement and basic boot logic.

4. **PE Signing**: The resulting EFI binary is PE-signed by sbctl for UEFI validation.

## File Signatures

Different files require different signature types:

| File              | GPG Signed | PE Signed |
|-------------------|:----------:|:---------:|
| grubx64.efi       | No         | Yes       |
| grub.cfg          | Yes        | No        |
| kernel-*          | Yes        | Yes       |
| initramfs-*.img   | Yes        | No        |
| amd-uc.img        | Yes        | No        |
| intel-uc.img      | Yes        | No        |

### Notes

- **grubx64.efi**: PE-signed only because it's an EFI binary validated by firmware.
- **grub.cfg**: GPG-signed because GRUB validates it after starting.
- **kernel-***: Dual-signed because it's both an EFI binary (validated by firmware when using EFI stub) and a file loaded by GRUB (validated by GRUB's GPG).
- **initramfs-*.img**: GPG-signed only because it's loaded by GRUB/kernel, not by firmware.
- **amd-uc.img / intel-uc.img**: GPG-signed only because they're loaded by GRUB, not by firmware.

## Signing Order

The signing order is critical:

1. **PE Signature First**: Use sbctl to PE-sign binaries. This modifies the binary in-place.

2. **GPG Signature Last**: Create GPG signatures after all binary modifications are complete.

This order ensures that GPG signatures remain valid and are not invalidated by subsequent binary modifications.

## Disk Layout

The system uses the following partition structure:

- **nvme1n1p1**: Linux EFI System Partition (ESP), FAT32 filesystem, mounted at `/boot`
- **nvme2n1p1**: Windows EFI System Partition (ESP), FAT32 filesystem
- **Encrypted Root**: LUKS-encrypted partition containing LVM with XFS root filesystem and swap

## Security Model

### Key Management

- **Private Keys**: Never stored in the repository. Keys are machine-specific and managed locally.

- **Machine Configuration**: Machine-specific values are stored in `machine.conf`, which is gitignored.

- **GPG Key Storage**: GPG private keys are maintained in root's keyring.

- **sbctl Keys**: Secure Boot keys managed by sbctl are stored in `/usr/share/secureboot/`.

### Security Principles

1. **Defense in Depth**: Two independent signature validation layers.
2. **Key Isolation**: Private keys never leave the local system.
3. **Configuration Separation**: Machine-specific configuration is separated from version-controlled code.
4. **Minimal Trust**: Only essential files are signed and validated.
5. **Fail Secure**: Signature enforcement is mandatory, not optional.
