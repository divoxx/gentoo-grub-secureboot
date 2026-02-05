# Emergency Recovery Procedures

This document provides step-by-step recovery procedures for common failure scenarios in the gentoo-secureboot setup.

## Table of Contents

- [Booting Without Signatures (Emergency)](#booting-without-signatures-emergency)
- [Re-signing All Boot Files](#re-signing-all-boot-files)
- [Rebuilding GRUB Binary](#rebuilding-grub-binary)
- [Fixing Broken Boot After GRUB Update](#fixing-broken-boot-after-grub-update)
- [Key Rotation - GPG](#key-rotation---gpg)
- [Key Rotation - sbctl / Secure Boot](#key-rotation---sbctl--secure-boot)
- [Recovering from Chroot](#recovering-from-chroot)
- [Windows Not Booting](#windows-not-booting)

## Booting Without Signatures (Emergency)

If GRUB refuses to load files due to signature verification failures, you have several options:

### Option 1: Disable Secure Boot Temporarily

1. Reboot and enter UEFI firmware settings (usually F2, F10, F12, or Del during boot)
2. Navigate to Secure Boot settings
3. Disable Secure Boot temporarily
4. Save changes and reboot
5. Once booted, fix signatures using procedures below
6. Re-enable Secure Boot after repairs

### Option 2: Use GRUB Shell

If the standalone GRUB binary loads but refuses to load signed files:

1. At GRUB prompt, disable signature checking:
   ```
   set check_signatures=no
   ```
   **Note:** This only works if no GRUB password is set

2. Load configuration manually:
   ```
   configfile (hd0,gpt1)/grub/grub.cfg
   ```

3. Boot normally and fix signatures once in the system

### Option 3: Boot from Live USB

1. Boot from a Gentoo or other Linux live USB
2. Follow the [Recovering from Chroot](#recovering-from-chroot) procedure below

## Re-signing All Boot Files

The quickest way to re-sign all boot files:

```bash
sign-boot
```

### Manual Re-signing

If the `sign-boot` script is unavailable or you need more control:

```bash
# Re-sign GRUB configuration
gpg --default-key grub --detach-sign /boot/grub/grub.cfg

# Re-sign all kernels
for kernel in /boot/kernel-*; do
    gpg --default-key grub --detach-sign "$kernel"
done

# Re-sign all initramfs images
for initramfs in /boot/initramfs-*.img; do
    gpg --default-key grub --detach-sign "$initramfs"
done

# Re-sign microcode if present
[ -f /boot/amd-uc.img ] && gpg --default-key grub --detach-sign /boot/amd-uc.img
```

## Rebuilding GRUB Binary

If the GRUB standalone binary is corrupted or needs to be rebuilt with new keys:

```bash
build-grub
update-boot
```

This will:
1. Rebuild the standalone GRUB binary with embedded GPG public key
2. Sign it with sbctl for Secure Boot
3. Regenerate and sign grub.cfg

## Fixing Broken Boot After GRUB Update

When GRUB is updated via `emerge` or package manager, the standalone binary may become outdated:

**Symptoms:**
- GRUB loads but can't verify signatures
- "error: bad signature" messages
- Boot stops at GRUB prompt

**Solution:**

```bash
build-grub
update-boot
```

Always run these commands after updating GRUB packages to ensure the standalone binary includes the correct GPG key.

## Key Rotation - GPG

When rotating GPG keys used for boot file signatures:

### Step 1: Generate New GPG Key

```bash
gpg --gen-key
```

Follow the prompts and use "grub" as the name/identifier.

### Step 2: Export Public Key

```bash
gpg --export grub > /root/grub.pub
```

### Step 3: Rebuild GRUB Binary

The new public key must be embedded in the GRUB standalone binary:

```bash
build-grub
```

### Step 4: Re-sign All Boot Files

```bash
update-boot
```

This regenerates grub.cfg and signs all boot files with the new key.

### Step 5: Verify

```bash
reboot
```

Monitor boot process to ensure signature verification succeeds.

### Step 6: Revoke Old Key (Optional)

After confirming the new key works:

```bash
gpg --list-keys
gpg --delete-secret-key OLD_KEY_ID
gpg --delete-key OLD_KEY_ID
```

## Key Rotation - sbctl / Secure Boot

When rotating Secure Boot signing keys:

### Step 1: Create New Keys

```bash
sbctl create-keys
```

This generates new Platform Key (PK), Key Exchange Key (KEK), and Database (db) keys.

### Step 2: Enroll Keys

```bash
sbctl enroll-keys --microsoft
```

The `--microsoft` flag includes Microsoft's keys, necessary for booting Windows and some hardware firmware.

### Step 3: Re-sign All PE Files

```bash
sbctl sign-all
```

### Step 4: Rebuild GRUB Binary

```bash
build-grub
```

### Step 5: Verify and Reboot

```bash
sbctl verify
reboot
```

### Step 6: Verify Keys in Firmware

After reboot:
1. Enter UEFI firmware settings
2. Navigate to Secure Boot configuration
3. Verify new keys are enrolled
4. Confirm Secure Boot is enabled

## Recovering from Chroot

When the system won't boot and you need to repair from a live USB:

### Step 1: Boot Live USB

Use any Linux live USB (Gentoo minimal install, SystemRescue, etc.)

### Step 2: Unlock Encrypted Volumes

If using LUKS encryption:

```bash
# Replace /dev/nvme1n1pX with your encrypted partition
cryptsetup open /dev/nvme1n1pX gentoo-lvm
```

### Step 3: Mount Partitions

```bash
# Mount root filesystem
mount /dev/mapper/gentoo--vg0-root /mnt/gentoo

# Mount boot partition (adjust device as needed)
mount /dev/nvme1n1p1 /mnt/gentoo/boot

# Mount other partitions if needed
# mount /dev/mapper/gentoo--vg0-home /mnt/gentoo/home
```

### Step 4: Prepare Chroot Environment

```bash
# Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/dev
```

### Step 5: Chroot Into System

```bash
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) $PS1"
```

### Step 6: Perform Repairs

```bash
# Rebuild GRUB binary
build-grub

# Update boot configuration and signatures
update-boot

# Or perform specific repairs as needed
```

### Step 7: Exit and Reboot

```bash
exit
umount -R /mnt/gentoo
reboot
```

## Windows Not Booting

If the Windows chainloader entry in GRUB doesn't work:

### Verify Windows ESP UUID

```bash
blkid | grep -i fat
```

Look for the Windows EFI System Partition UUID.

### Check GRUB Configuration

```bash
cat /etc/grub.d/26_windows
```

Verify the UUID in the search command matches your Windows ESP:

```bash
search --no-floppy --fs-uuid --set=root YOUR-UUID-HERE
```

### Update Configuration

If the UUID is incorrect:

1. Edit `/etc/grub.d/26_windows`
2. Update the UUID
3. Regenerate configuration:
   ```bash
   update-boot
   ```

### Alternative: Boot Windows Directly

If GRUB chainloading continues to fail:

1. Reboot and enter UEFI boot menu (usually F12)
2. Select Windows Boot Manager directly
3. This bypasses GRUB entirely

### Check Windows EFI Files

From a booted system (Linux or Windows recovery):

```bash
mount /dev/YOUR-WINDOWS-ESP /mnt
ls -la /mnt/EFI/Microsoft/Boot/
```

Verify `bootmgfw.efi` exists. If missing, Windows boot files need repair via Windows Recovery Environment.

## Related Documentation

- [Architecture](architecture.md) — Boot chain design and security model
- [Maintenance](maintenance.md) — Routine maintenance procedures
