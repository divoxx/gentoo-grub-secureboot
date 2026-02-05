# Maintenance Guide

This document covers routine maintenance procedures for the gentoo-secureboot project.

## Table of Contents

- [Automatic Maintenance](#automatic-maintenance)
- [Manual Maintenance Tasks](#manual-maintenance-tasks)
- [System Health Verification](#system-health-verification)
- [Command Reference](#command-reference)
- [Cleanup Procedures](#cleanup-procedures)
- [GPG Key Management](#gpg-key-management)

## Automatic Maintenance

### After Kernel Update

The system automatically handles kernel updates through kernel install hooks:

1. `91-sbctl.install` performs PE signing of the kernel
2. `99-update-boot.install` executes `update-boot`:
   - Runs `sbctl sign-all` to sign all PE binaries
   - Generates new GRUB configuration via `grub-mkconfig`
   - Executes `sign-boot.sh` to GPG sign boot components

**Requirements for full automation:**
- GPG key without passphrase (recommended for encrypted root)
- Both install hooks properly configured in `/etc/kernel/install.d/`

## Manual Maintenance Tasks

### After GRUB Package Update

When the GRUB package is updated by the package manager:

```bash
build-grub    # Rebuild standalone binary and PE sign
update-boot   # Regenerate configuration and GPG sign
```

### After Configuration Changes

When modifying kernel command line parameters or other boot configuration:

```bash
update-boot   # Regenerate configuration and GPG sign
```

### After Changing Module List

When modifying the list of GRUB modules included in the standalone binary:

```bash
build-grub    # Rebuild standalone binary with new modules
update-boot   # Regenerate configuration and GPG sign
```

## System Health Verification

Verify the integrity and health of your secure boot setup:

```bash
audit-secureboot
```

This performs a read-only check of:
- Secure Boot status and mode
- PE signature verification for EFI binaries
- GPG signature verification for boot files
- Configuration consistency

Run this command after any maintenance operation to confirm proper setup.

## Command Reference

### update-boot

Regenerates boot configuration and signs all necessary files:

1. Executes `sbctl sign-all` for PE binary signatures
2. Runs `grub-mkconfig` to generate `/boot/grub/grub.cfg`
3. Calls `sign-boot.sh` to GPG sign:
   - `grub.cfg`
   - Kernel images
   - Initramfs images
   - Microcode files

### build-grub

Builds the standalone GRUB EFI binary:

1. Exports GPG public key to `/root/grub.pub`
2. Renders `initial.cfg` from template
3. Signs `initial.cfg` with GPG
4. Runs `grub-mkstandalone` to create monolithic EFI binary
5. Signs the EFI binary with `sbctl sign`

### sign-boot.sh

GPG signs boot components for GRUB verification:
- GRUB configuration file
- All kernel images
- All initramfs images
- CPU microcode files

### audit-secureboot

Performs comprehensive read-only verification:
- Checks Secure Boot firmware status
- Validates PE signatures on EFI binaries
- Validates GPG signatures on boot files
- Reports any configuration issues

## Cleanup Procedures

### Removing Old GRUB Files

After migrating from `grub-install` to `grub-mkstandalone`, the following files are obsolete:

**Safe to remove:**
- `/boot/grub/x86_64-efi/*.mod` (individual module files)
- `/boot/grub/x86_64-efi/*.sig` (module signatures)
- `/boot/grub/x86_64-efi/core.efi` (old core image)
- `/boot/grub/x86_64-efi/grub.efi` (old GRUB binary)

**Must keep:**
- `/boot/grub/grub.cfg` (configuration file, still required)
- `/boot/grub/fonts/` (font files, needed if using GRUB themes)
- `/boot/EFI/gentoo/grubx64.efi` (standalone binary, contains embedded public key)

**Cleanup example:**

```bash
# Review files before deletion
ls -la /boot/grub/x86_64-efi/

# Remove obsolete module files
rm -f /boot/grub/x86_64-efi/*.mod
rm -f /boot/grub/x86_64-efi/*.sig
rm -f /boot/grub/x86_64-efi/core.efi
rm -f /boot/grub/x86_64-efi/grub.efi

# Optionally remove the directory if empty
rmdir /boot/grub/x86_64-efi/ 2>/dev/null || true
```

## GPG Key Management

### Passphrase Considerations

**No passphrase (recommended):**
- Enables full automation for kernel updates
- Key protected by LUKS encryption at rest
- Follows Gentoo wiki recommendation for root-only keys on encrypted systems
- Suitable for single-user systems with encrypted root filesystem

**With passphrase:**
- Requires `gpg-agent` running during kernel installations and updates
- Manual intervention needed for automated kernel updates
- Provides additional layer of security
- May be preferred for multi-user or shared systems

### Key Security

The GPG key is used exclusively for signing boot components. Security considerations:

- Key stored in `/root/.gnupg/` (root access required)
- Root filesystem encryption (LUKS) protects key at rest
- Key never leaves the local system
- Only public key exported to `/root/grub.pub`

### Changing Passphrase

To add or change the GPG key passphrase:

```bash
gpg --edit-key <key-id>
# At the gpg> prompt, enter: passwd
# Follow prompts to set new passphrase
# Enter: save
```

After changing the passphrase, test automated updates or ensure `gpg-agent` is properly configured.

## Troubleshooting

### Kernel Update Fails to Sign

**Symptom:** Kernel install hook fails during automatic signing

**Solutions:**
1. Verify `sbctl` is installed and configured
2. Check that Secure Boot keys are enrolled: `sbctl status`
3. If using GPG passphrase, ensure `gpg-agent` is running
4. Manually run: `update-boot` to diagnose issues

### GRUB Configuration Not Updated

**Symptom:** Boot configuration changes not reflected in GRUB menu

**Solutions:**
1. Manually run: `update-boot`
2. Verify `/etc/default/grub` changes are saved
3. Check for errors in `/var/log/` or `journalctl -xe`
4. Run `audit-secureboot` to verify configuration state

### Signature Verification Failures

**Symptom:** GRUB reports signature verification errors at boot

**Solutions:**
1. Boot to system (if possible) and run: `update-boot`
2. Rebuild GRUB binary: `build-grub && update-boot`
3. Verify GPG key integrity: check `/boot/grub/pubkey.gpg` exists
4. Check signature files exist (`.sig` extensions on boot files)

## Best Practices

1. **After any manual changes:** Run `audit-secureboot` to verify system state
2. **Before major updates:** Document current configuration and test recovery procedures
3. **Regular verification:** Periodically run `audit-secureboot` to catch issues early
4. **Keep backups:** Maintain copies of working configuration files
5. **Test updates:** If possible, test kernel updates in non-production first

## Related Documentation

- [Architecture](architecture.md) — Boot chain design and security model
- [Recovery](recovery.md) — Emergency recovery procedures
