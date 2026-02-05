# Gentoo GRUB Secure Boot

Automated setup and maintenance for a two-layer verified boot chain on Gentoo Linux with Windows dual-boot support.

## Overview

This project implements a comprehensive verified boot architecture:

- **Layer 1: UEFI Secure Boot** — Validates PE/EFI binaries using sbctl
- **Layer 2: GRUB GPG Verification** — Validates grub.cfg, kernels, initramfs, and microcode

Uses `grub-mkstandalone` to build a self-contained GRUB binary with embedded modules and GPG public key, ensuring the entire boot chain is cryptographically verified.

## Features

- Automated setup and maintenance scripts
- Dual-boot support (Gentoo + Windows)
- LUKS encryption with LVM
- XFS root filesystem on LVM
- Automatic kernel update hooks via installkernel
- Health check and audit tooling
- Recovery documentation

## System Requirements

### Target Configuration

- **Distribution**: Gentoo Linux (systemd profile)
- **Kernel**: sys-kernel/gentoo-kernel-bin or dist-kernel
- **Bootloader**: sys-boot/grub 2.12+
- **Encryption**: LUKS + LVM
- **Filesystem**: XFS root on LVM on LUKS, FAT32 ESP

### Required Packages

```bash
emerge -av sys-boot/grub app-crypt/sbctl app-crypt/gnupg sys-boot/efibootmgr
```

Ensure GRUB is built with:
```
USE="grub_platforms_efi-64 device-mapper"
```

## Quick Start

### 1. Clone Repository

```bash
git clone <your-repo-url>
cd gentoo-grub-secureboot
```

### 2. Configure Machine Settings

Copy the example configuration and edit for your system:

```bash
cp machine.conf.example machine.conf
editor machine.conf
```

### 3. Run Setup

Execute the interactive setup script:

```bash
sudo scripts/setup.sh
```

The setup script will:
- Generate GPG key for GRUB verification
- Create Secure Boot keys with sbctl
- Install scripts to system paths
- Build standalone GRUB binary
- Configure GRUB with GPG verification
- Sign all boot files
- Install installkernel hook

### 4. Reboot and Enable Secure Boot

1. Reboot into firmware settings
2. Enable Secure Boot
3. Enroll custom keys (sbctl will guide you)
4. Boot into your system

### 5. Verify Installation

```bash
sudo audit-secureboot
```

## Directory Structure

```
├── README.md
├── LICENSE                     # GPL-3.0
├── .gitignore
├── machine.conf.example        # Template for machine-specific values
├── grub/
│   ├── modules.txt             # Modules embedded in standalone binary
│   ├── initial.cfg.template    # Embedded config template
│   └── grub.d/
│       └── 26_windows          # Windows chainload entry
├── scripts/
│   ├── lib.sh                  # Shared utilities
│   ├── setup.sh                # First-time setup (interactive)
│   ├── install.sh              # Install scripts to system paths
│   ├── build-grub.sh           # Build standalone GRUB binary
│   ├── sign-boot.sh            # GPG sign on-disk boot files
│   ├── update-boot.sh          # Full update: mkconfig + sign
│   └── audit.sh                # Health check / verification
├── hooks/
│   └── 99-update-boot.install  # installkernel hook
└── docs/
    ├── architecture.md         # Technical architecture details
    ├── maintenance.md          # Ongoing maintenance procedures
    └── recovery.md             # Recovery and troubleshooting
```

## Usage

After installation, these commands are available system-wide:

### update-boot

Full update: regenerate GRUB configuration and sign all boot files. Run after:
- Kernel updates (usually automatic via installkernel hook)
- GRUB configuration changes
- Boot parameter modifications

```bash
sudo update-boot
```

### build-grub

Rebuild standalone GRUB binary. Run after:
- GRUB package updates
- Module list changes
- Embedded configuration changes

```bash
sudo build-grub
```

### sign-boot

Re-sign boot files only (no configuration regeneration). Run after:
- Manual file modifications
- Signing key changes

```bash
sudo sign-boot
```

### audit-secureboot

Health check and verification of the boot chain:
- Verifies Secure Boot status
- Checks GPG signatures
- Validates file integrity
- Reports configuration issues

```bash
sudo audit-secureboot
```

## Maintenance

### Kernel Updates

Kernel updates are handled automatically via the installkernel hook. The hook will:
1. Trigger `update-boot` after kernel installation
2. Regenerate GRUB configuration
3. Sign all boot files with GPG

No manual intervention required unless the update fails.

### GRUB Updates

After updating sys-boot/grub:

```bash
sudo build-grub
sudo update-boot
```

### Configuration Changes

After modifying GRUB configuration in `/etc/default/grub` or `/etc/grub.d/`:

```bash
sudo update-boot
```

## Windows Dual-Boot

Windows chainloading is supported via a custom GRUB entry. The setup script automatically:
- Detects Windows EFI partition
- Creates chainloader entry at `/etc/grub.d/26_windows`
- Configures proper boot order

## Architecture

The verified boot chain works as follows:

1. **Firmware**: Verifies GRUB binary signature (Secure Boot Layer 1)
2. **GRUB Standalone**: Contains embedded modules, GPG public key, and minimal config
3. **Embedded Config**: Loads main grub.cfg and verifies its GPG signature
4. **Main Config**: All kernel, initramfs, and microcode references require valid GPG signatures (Layer 2)

For detailed architecture documentation, see [docs/architecture.md](docs/architecture.md).

## Troubleshooting

### Boot Fails with GPG Verification Error

1. Boot from rescue media
2. Mount your system
3. Follow recovery procedures in [docs/recovery.md](docs/recovery.md)

### Secure Boot Violation

1. Check sbctl status: `sbctl status`
2. Verify signatures: `sbctl verify`
3. Re-sign files if needed: `sbctl sign-all`

### Audit Failures

Run the audit tool for detailed diagnostics:

```bash
sudo audit-secureboot
```

## Documentation

- [docs/architecture.md](docs/architecture.md) — Technical architecture and design decisions
- [docs/maintenance.md](docs/maintenance.md) — Detailed maintenance procedures
- [docs/recovery.md](docs/recovery.md) — Recovery and troubleshooting procedures

## Security Considerations

- GPG keys are stored in `/root/.gnupg/`
- Secure Boot keys are managed by sbctl
- The GPG public key is embedded in the GRUB binary
- All boot files are signed with the GPG private key
- Only the GRUB binary is signed with Secure Boot keys
- **GRUB shell access**: Without GRUB password protection, anyone with physical console access can disable GPG verification via the GRUB shell. Consider implementing `set superusers` / `password_pbkdf2` in the embedded config. See: [Gentoo GRUB2 Password Protection](https://wiki.gentoo.org/wiki/GRUB2#Password_protection)

Keep backups of your keys in a secure location.

## License

GPL-3.0 License. See [LICENSE](LICENSE) file for details.

## Contributing

This project follows standard Git workflow practices. Pull requests welcome.

## Support

For issues and questions:
- Check [docs/recovery.md](docs/recovery.md) for common problems
- Review audit output: `sudo audit-secureboot`
- Open an issue on GitHub
