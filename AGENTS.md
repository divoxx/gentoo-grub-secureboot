# AGENTS.md — Gentoo Secure Boot + GRUB GPG Verification Repository

## Project Goal

Build a Git repository that automates setting up and maintaining a two-layer
verified boot chain on Gentoo Linux with Windows dual-boot:

- **Layer 1 — UEFI Secure Boot** via `sbctl` (validates PE/EFI binaries)
- **Layer 2 — GRUB GPG verification** (validates grub.cfg, kernels, initramfs,
  microcode, and any file GRUB loads from disk)

The repo must:

1. Automate initial setup on a new machine (interactive, guided)
2. Automate routine maintenance (kernel updates, GRUB updates, config changes)
3. Install itself by symlinking or copying scripts into system paths
4. Never contain private keys, secrets, or machine-specific hardcoded values
5. Target Gentoo Linux exclusively (systemd init, dist-kernel, GRUB 2.12+)

The owner's username is `divoxx` and the repo currently lives at
`/home/divoxx/code/own/gentoo-grub-secureboot`. Scripts that get linked
into system paths should use this location as the canonical source.

---

## Architecture

```
UEFI Firmware (sbctl custom key + Microsoft keys in db)
  │
  ├─▶ Validates: grubx64.efi (PE/Authenticode via sbctl)
  │
  └─▶ GRUB starts (standalone binary)
        │
        │  Embedded: GPG public key + core modules + initial config
        │  Initial config sets: check_signatures=enforce
        │
        ├─▶ GPG verifies: /boot/grub/grub.cfg + .sig
        ├─▶ GPG verifies: /boot/kernel-* + .sig
        ├─▶ GPG verifies: /boot/initramfs-* + .sig
        ├─▶ GPG verifies: /boot/amd-uc.img + .sig  (microcode)
        │
        ├─▶ Windows entry: set check_signatures=no → chainload bootmgfw.efi
        │   (UEFI firmware still validates Microsoft PE signature)
        │
        └─▶ Linux boots
```

### Critical Design Decision: `grub-mkstandalone` vs `grub-install`

The current system uses `grub-install --pubkey` which installs ~300 `.mod`
files to `/boot/grub/x86_64-efi/`, each requiring an individual GPG
signature (360 `.sig` files total).

**This repository should switch to `grub-mkstandalone`**, which is:

- The approach recommended by the Gentoo Security Handbook and Gentoo wiki
  (https://wiki.gentoo.org/wiki/Security_Handbook/Boot_Path_Security)
- More reliable for signature enforcement (documented issues with
  `grub-install --pubkey` not enforcing on some configurations)
- Dramatically simpler: modules are embedded in the EFI binary itself,
  so only ~5 files need GPG signatures instead of 360+
- The Gentoo wiki, ACRN project, and multiple community guides all
  converge on `grub-mkstandalone` as the correct approach

**How `grub-mkstandalone` works:**

1. All specified modules are bundled INTO the EFI binary (on a memdisk
   and/or pre-loaded into core)
2. An initial embedded config is included that sets
   `check_signatures=enforce` and loads the on-disk `grub.cfg`
3. The embedded initial config + its `.sig` are packaged into the binary
4. The resulting EFI binary is then PE-signed by sbctl
5. On-disk files (grub.cfg, kernels, initramfs, microcode) are GPG-signed
   separately

**The `grub-mkstandalone` command pattern (from Gentoo wiki):**

```bash
grub-mkstandalone \
    --pubkey /root/grub.pub \
    --directory /usr/lib/grub/x86_64-efi \
    --format x86_64-efi \
    --modules "$MODULES" \
    --disable-shim-lock \
    --output /boot/EFI/gentoo/grubx64.efi \
    "boot/grub/grub.cfg=$INITIAL_CFG" \
    "boot/grub/grub.cfg.sig=$INITIAL_CFG_SIG"
```

The `--pubkey` flag causes `grub-mkimage` (called internally) to
implicitly set `check_signatures=enforce` in core.img before any config
files are processed (per the GRUB 2.12 manual, section 19.2). The embedded
initial config provides a fallback and explicit enforcement.

**Impact on the repository:**

- No more signing `.mod` files, fonts, themes, or locale files
- The `/boot/grub/x86_64-efi/` directory of loose modules is no longer
  needed (though `grub-mkconfig` may still reference it for probing)
- The signing script becomes much simpler
- After GRUB package updates, the standalone binary must be rebuilt (not
  just `grub-install`)

### Files That Need GPG Signatures (with standalone approach)

| File                              | GPG Signed | PE Signed (sbctl) |
|-----------------------------------|:----------:|:-----------------:|
| `/boot/EFI/gentoo/grubx64.efi`   | No*        | Yes               |
| `/boot/grub/grub.cfg`            | Yes        | No                |
| `/boot/kernel-*`                 | Yes        | Yes               |
| `/boot/initramfs-*.img`          | Yes        | No                |
| `/boot/amd-uc.img` (microcode)   | Yes        | No                |

\* The standalone binary contains signed components internally. Its
integrity is verified by UEFI Secure Boot (PE signature), not GPG.

### Files That Do NOT Need Signatures

- `System.map-*` — not loaded by GRUB
- `config-*` — not loaded by GRUB
- `shellx64.efi` — PE-signed by sbctl, not loaded through GRUB config
- Anything in `/boot/EFI/` — verified by UEFI firmware, not GRUB

---

## Current System State (from audit, February 2026)

### Hardware & Software

- **Hostname:** s0rc3r3r
- **CPU:** AMD Ryzen 9 7950X3D
- **Kernel:** 6.12.47-gentoo-dist (dist-kernel via installkernel)
- **GRUB:** 2.12
- **Init:** systemd
- **Filesystems:** XFS root on LVM on LUKS; FAT32 ESP

### Disk Layout

| Partition    | UUID/PARTUUID                          | Mount     | Purpose      |
|-------------|----------------------------------------|-----------|--------------|
| nvme1n1p1   | D728-8DD1 / c12a7328-f81f-11d2-...    | /boot     | Linux ESP    |
| nvme2n1p1   | 90B1-2A22 / 8ae6f044-fd9d-...         | /mnt/windows-esp | Windows ESP |
| (nvme1n1p?) | 4c53311c-c455-4952-969b-5324e2c1576c | (LUKS)    | Encrypted root |

### Secure Boot State

- Secure Boot: **Enabled**
- Vendor keys: **microsoft**
- Owner GUID: 58dc0b3e-15f2-4e81-b849-653add9e8ec5
- **Firmware quirk FQ0001**: Firmware may execute binaries even when SB
  validation fails. This makes the GPG layer the *real* security layer.

### GPG Key

- Key ID: `2D7B8CF6202C4A6D`
- Full fingerprint: `8E5473FD77D5EB77B036C7F02D7B8CF6202C4A6D`
- UID: `grub (This key is used to sign files for GRUB.)`
- Algorithm: RSA 4096, no expiry
- Trust level: ultimate
- Stored in root's GPG keyring

### Existing Script

Located at `/home/divoxx/code/own/gentoo-grub-secureboot/sign-grub-files.sh`
(845 bytes). This is the only script that currently exists.

### Audit Findings (issues to fix)

1. **Stale GPG signatures** on `core.efi` and `grub.efi` — sbctl modified
   binaries after GPG signing. Moot with standalone approach (these files
   won't exist).
2. **Missing `/root/grub.pub`** — public key not exported. Setup script
   must create this.
3. **Missing `/root/grub-modules.txt`** — no record of embedded modules.
   Repo should be the source of truth.
4. **Missing `update-boot.sh`** — no combined maintenance script.
5. **`GRUB_DISABLE_OS_PROBER=false`** — should be `true` since a custom
   `26_windows` entry handles Windows. os-prober is unnecessary and is a
   slight security concern (probes all disks). Note: Gentoo does NOT
   install os-prober by default, so if it's not installed, this setting
   is a no-op anyway, but being explicit is better.
6. **No GRUB password protection** — without this, an attacker with
   console access can type `set check_signatures=no` at the GRUB shell.
   The GRUB manual and Gentoo wiki both recommend setting a superuser
   password. This is optional but should be documented and supported.

---

## Repository Design

### Directory Structure

```
gentoo-secureboot/
├── AGENTS.md                           # This file (Claude Code context)
├── README.md                           # User documentation
├── LICENSE                             # MIT or similar
├── .gitignore                          # Exclude secrets and generated files
│
├── machine.conf.example                # Template for machine-specific values
│
├── grub/
│   ├── modules.txt                     # Modules to embed in standalone binary
│   ├── initial.cfg.template            # Embedded config template
│   └── grub.d/
│       └── 26_windows                  # Windows chainload entry (templated)
│
├── scripts/
│   ├── setup.sh                        # First-time setup (interactive)
│   ├── install.sh                      # Install/symlink scripts to system
│   ├── build-grub.sh                   # Build standalone GRUB binary
│   ├── sign-boot.sh                    # GPG sign on-disk boot files
│   ├── update-boot.sh                  # Full update: build + mkconfig + sign
│   └── audit.sh                        # Health check / verification
│
├── hooks/
│   └── 99-update-boot.install          # installkernel hook for auto-update
│
└── docs/
    ├── architecture.md                 # Detailed architecture explanation
    ├── maintenance.md                  # Routine maintenance procedures
    └── recovery.md                     # Emergency recovery procedures
```

### Configuration: `machine.conf`

Machine-specific values live in `machine.conf` (gitignored). The repo
ships `machine.conf.example` as a template. Scripts source this file and
refuse to run if it's missing or incomplete.

Required variables:

```bash
# Disk identifiers
LINUX_ESP_UUID=""              # UUID of Linux ESP (FAT32 fs UUID)
LINUX_ESP_PARTUUID=""          # PARTUUID for fstab
WINDOWS_ESP_UUID=""            # UUID of Windows ESP (for 26_windows)

# LUKS / LVM (for GRUB_CMDLINE_LINUX generation)
LUKS_UUID=""                   # LUKS container UUID
LVM_VG=""                      # LVM volume group name
LVM_LV_ROOT=""                 # Root logical volume
LVM_LV_SWAP=""                 # Swap logical volume (optional, can be empty)

# Root filesystem
ROOT_FSTYPE="xfs"              # Root filesystem type
ROOT_MOUNT_OPTIONS=""          # Mount options for rootflags=

# Extra kernel command line parameters
EXTRA_CMDLINE=""               # e.g., "amdgpu.dcdebugmask=0x410"

# GRUB
BOOTLOADER_ID="gentoo"         # UEFI boot menu entry name
ESP_MOUNT="/boot"              # Where ESP is mounted

# GPG
GPG_KEY_NAME="grub"            # GPG key UID for signing
```

### Key Files Specification

#### `grub/modules.txt`

One module per line, comments with `#`. These modules are embedded in the
standalone GRUB binary via `--modules`. Include everything that might be
needed since they're bundled, not loaded from disk.

Based on the current system and Gentoo wiki recommendations:

```
# Core boot
normal
configfile
linux
echo
reboot
sleep
test
true

# Search
search
search_fs_uuid
search_fs_file

# Filesystem & partition
ext2
fat
part_gpt
part_msdos

# Cryptography for GPG verification
pgp
gcry_sha512
gcry_rsa
gcry_dsa

# LUKS / encrypted boot support
cryptodisk
luks
luks2
pbkdf2
gcry_rijndael
gcry_sha256

# Display
all_video
gfxterm
gfxmenu
font
png
jpeg

# Chainloading (Windows)
chain

# Other
loadenv
minicmd
```

**Note:** Compare with the GRUB modules actually needed by `grub-mkconfig`
output. The `insmod` statements in `grub.cfg` reference modules by name;
all referenced modules must be in this list. Run
`grep -h 'insmod ' /boot/grub/grub.cfg | sort -u` to find them.

#### `grub/initial.cfg.template`

This is the embedded initial config. It runs before the on-disk `grub.cfg`.

```bash
# Enforce GPG signature verification for all loaded files
set check_signatures=enforce
export check_signatures

# Find the ESP by UUID and load the real config
search --no-floppy --fs-uuid --set=root %%LINUX_ESP_UUID%%
set prefix=($root)/grub
configfile $prefix/grub.cfg

# Fallback if grub.cfg fails
echo "grub.cfg failed to boot. Rebooting in 10 seconds."
sleep 10
reboot
```

The `%%LINUX_ESP_UUID%%` placeholder is replaced by `build-grub.sh`
at build time using the value from `machine.conf`.

**Regarding GRUB password protection:** The Gentoo wiki and GRUB manual
recommend adding superuser password protection to prevent GRUB shell
access. If the user wants this, the initial config would also include:

```bash
set superusers="root"
export superusers
password_pbkdf2 root <hash>
```

This is optional. If implemented, store the hash in `machine.conf`
(gitignored) since it's machine-specific. Mark all menu entries as
`--unrestricted` so normal boot doesn't require a password — only
GRUB shell/editing access is restricted.

#### `grub/grub.d/26_windows`

```bash
#!/bin/bash
# Custom Windows Boot Entry
# Bypasses GRUB GPG verification (UEFI Secure Boot still validates)

# Source machine config for UUID
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -f "$REPO_ROOT/machine.conf" ]]; then
    source "$REPO_ROOT/machine.conf"
fi

# Fall back to hardcoded value if machine.conf not available
# (the install script copies this with the UUID baked in)
WINDOWS_UUID="${WINDOWS_ESP_UUID:-}"

if [[ -z "$WINDOWS_UUID" ]]; then
    echo "Warning: WINDOWS_ESP_UUID not set" >&2
    exit 0
fi

cat << GRUB
menuentry "Windows Boot Manager" --class windows --class os {
    set check_signatures=no
    insmod chain
    insmod fat
    insmod part_gpt
    search --fs-uuid --set=root ${WINDOWS_UUID}
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    set check_signatures=enforce
}
GRUB
```

**Important:** When this file is installed to `/etc/grub.d/26_windows`,
the `install.sh` script should generate a self-contained version with
the UUID baked in (not sourcing from the repo), because `grub-mkconfig`
runs as a system tool and shouldn't depend on the repo path at runtime.

#### `scripts/build-grub.sh`

Builds the standalone GRUB EFI binary. Must be run:
- After GRUB package update (`emerge sys-boot/grub`)
- If `grub/modules.txt` or `grub/initial.cfg.template` change

Steps:
1. Source `machine.conf`, validate required values
2. Export GPG public key to temp file (if `/root/grub.pub` is stale)
3. Generate initial config from template (replace `%%PLACEHOLDERS%%`)
4. GPG-sign the initial config
5. Run `grub-mkstandalone` with all parameters
6. PE-sign the resulting binary with `sbctl sign -s`
7. Optionally register with `efibootmgr` if not already present

#### `scripts/sign-boot.sh`

GPG-signs on-disk boot files. With the standalone approach, this is
MUCH simpler than the current script:

1. Remove existing `.sig` files from `/boot` (only top-level + grub.cfg)
2. Sign `grub.cfg`
3. Sign all `kernel-*` files
4. Sign all `initramfs-*` files
5. Sign all `*.img` files (microcode)
6. Verify signatures

**Do NOT sign:**
- Anything in `/boot/EFI/` (PE-signed, not GPG-verified)
- `System.map-*`, `config-*` (not loaded by GRUB)
- `shellx64.efi` (PE-signed, not loaded by GRUB)
- Files in `/boot/grub/x86_64-efi/` (if directory still exists from
  old approach, modules should be embedded now)

Uses `parallel` if available for speed, falls back to sequential.

#### `scripts/update-boot.sh`

The primary maintenance command. Combines all steps in correct order:

1. `sbctl sign-all` — ensure all PE files are signed
2. `grub-mkconfig -o /boot/grub/grub.cfg` — regenerate GRUB config
3. `sign-boot.sh` — GPG-sign everything
4. Print summary and verification status

Does NOT rebuild the standalone GRUB binary (that's `build-grub.sh`,
needed only after GRUB package updates or module list changes).

#### `scripts/setup.sh`

Interactive first-time setup:

1. Check prerequisites: required packages installed, USE flags correct
2. Prompt for or detect machine-specific values → write `machine.conf`
3. Generate GPG key if not present (or import existing)
4. Export public key to `/root/grub.pub`
5. Create sbctl keys if not present (`sbctl create-keys`)
6. Enroll keys with `sbctl enroll-keys --microsoft`
7. Run `install.sh` to set up system files
8. Build standalone GRUB binary (`build-grub.sh`)
9. Generate and sign grub.cfg (`update-boot.sh`)
10. Print instructions for enabling Secure Boot in firmware

**Required Gentoo packages:**
- `sys-boot/grub` (USE: `grub_platforms_efi-64 device-mapper`)
- `app-crypt/sbctl`
- `app-crypt/gnupg`
- `sys-process/parallel` (optional)
- `sys-boot/efibootmgr`
- `sys-boot/os-prober` is NOT required (we use custom 26_windows)

#### `scripts/install.sh`

Installs/links repo files into system locations:

1. Validate `machine.conf` exists and is complete
2. Generate `26_windows` with baked-in UUID → copy to `/etc/grub.d/`
3. Symlink `update-boot.sh` → `/usr/local/sbin/update-boot`
4. Symlink `build-grub.sh` → `/usr/local/sbin/build-grub`
5. Symlink `sign-boot.sh` → `/usr/local/sbin/sign-boot`
6. Symlink `audit.sh` → `/usr/local/sbin/audit-secureboot`
7. Install kernel hook if using installkernel
8. Ensure `/etc/default/grub` has required settings (append/modify,
   don't overwrite):
   - `GRUB_ENABLE_CRYPTODISK=y` (if LUKS is configured)
   - `GRUB_DISABLE_OS_PROBER=true`
   - `GRUB_DISABLE_LINUX_UUID=true`
   - `GRUB_DISABLE_LINUX_PARTUUID=true`
   - `GRUB_CMDLINE_LINUX=<generated from machine.conf>`
   - `GRUB_GFXPAYLOAD_LINUX=keep`
9. Remove `GRUB_OS_PROBER_SKIP_LIST` if present (unnecessary with
   os-prober disabled)

**Symlink vs copy strategy:**
- Scripts → symlink (changes to repo immediately take effect)
- `26_windows` → copy with generated content (must be self-contained
  for `grub-mkconfig`)
- Kernel hooks → copy (must work independently of repo location)

#### `scripts/audit.sh`

Read-only health check script (based on the audit script already
created in this conversation). Verifies:
- Secure Boot status
- PE signature validity
- GPG signature validity and freshness
- Embedded modules in GRUB binary
- Key availability
- Configuration consistency

#### `hooks/99-update-boot.install`

An installkernel hook that runs after kernel installation. Placed in
`/etc/kernel/install.d/`. Runs AFTER the existing `91-sbctl.install`
(which PE-signs the kernel).

```bash
#!/bin/bash
# Auto-update GRUB config and GPG signatures after kernel install
COMMAND="$1"
case "$COMMAND" in
    add)
        /usr/local/sbin/update-boot
        ;;
esac
exit 0
```

**Consideration:** This hook runs during `emerge`, which means the GPG
passphrase prompt will appear during package installation. If the GPG
key has no passphrase (as the Gentoo wiki suggests for root-only keys
on encrypted root), this works seamlessly. If the key has a passphrase,
the gpg-agent must be running. Document both approaches.

---

## Security Constraints

### MUST NOT be in the repository

- GPG private keys
- sbctl private keys (under `/usr/share/secureboot/`)
- GRUB password hashes
- `machine.conf` (contains machine-specific config; template only)
- `/root/grub.pub` (machine-specific; generated during setup)
- Any generated `.sig` files

### Safe to include in the repository

- GPG public key export instructions
- Module lists
- Config templates with placeholders
- Shell scripts
- Documentation

### `.gitignore` must exclude

```
machine.conf
*.sig
*.pub
*.gpg
*.key
*.pem
*.crt
```

---

## Findings from External Documentation Review

### 1. `grub-install --pubkey` is unreliable

The GRUB manual states that `--pubkey` to `grub-mkimage` "implicitly
defines check_signatures equal to enforce in core.img." However:

- The straysheep-dev/grub-security project documented that
  `grub-install --pubkey` does NOT enforce on Ubuntu
- The Gentoo wiki Security Handbook uses `grub-mkstandalone` exclusively
- The Gentoo wiki Secure Boot/GRUB page uses `grub-mkstandalone`
- Multiple independent guides converge on `grub-mkstandalone`

The current system works with `grub-install --pubkey`, but switching to
`grub-mkstandalone` is more robust and is the community-recommended path.

### 2. The `grub-embed.cfg` was created but never used

The user's guide describes creating `/root/grub-embed.cfg` but the
`grub-install` command never references it (no `--config` flag, which
doesn't exist for `grub-install` anyway). With `grub-mkstandalone`, the
initial config IS properly embedded via positional arguments.

### 3. os-prober is unnecessary and counterproductive

With a custom `26_windows` entry:
- `GRUB_DISABLE_OS_PROBER=true` is the correct setting
- `GRUB_OS_PROBER_SKIP_LIST` becomes unnecessary
- os-prober package itself is optional
- Gentoo doesn't install os-prober by default

### 4. GRUB console password is recommended but missing

Without password protection, an attacker with console access can run
`set check_signatures=no` in the GRUB shell, bypassing all GPG
verification. The Gentoo wiki and GRUB manual both recommend:

```
set superusers="root"
password_pbkdf2 root grub.pbkdf2.sha512.10000.<hash>
```

This should be documented and optionally supported. The hash goes in
`machine.conf` (gitignored). Menu entries should use `--unrestricted`
so normal boot doesn't require a password.

### 5. `91-sbctl.install` ships with the sbctl package

The current hook at `/etc/kernel/install.d/91-sbctl.install` is the
stock sbctl-provided hook. The repo does NOT need to manage it.

### 6. Signing order matters

The correct order is:
1. PE-sign with sbctl (modifies binary in-place)
2. GPG-sign (must happen after any binary modification)

The `build-grub.sh` and `update-boot.sh` scripts must enforce this.

### 7. FAT32 ESP does not support symlinks

All files placed in `/boot` must be copied, not symlinked.
Scripts linked from `/usr/local/sbin/` are fine since that's on the
root filesystem (XFS).

---

## `/etc/default/grub` Management

The repo should NOT ship a complete `/etc/default/grub`. Instead,
`install.sh` should ensure specific settings exist. Settings that are
Gentoo defaults and don't need to be managed:

| Setting                    | Gentoo Default | Action          |
|---------------------------|----------------|-----------------|
| `GRUB_DISTRIBUTOR`        | `"Gentoo"`     | Don't touch     |
| `GRUB_TIMEOUT`            | `5`            | Don't touch     |
| `GRUB_DEFAULT`            | `0`            | Don't touch     |

Settings the repo MUST ensure:

| Setting                        | Value      | Why                          |
|-------------------------------|------------|------------------------------|
| `GRUB_ENABLE_CRYPTODISK`      | `y`        | LUKS support                 |
| `GRUB_DISABLE_OS_PROBER`      | `true`     | Custom 26_windows handles it |
| `GRUB_CMDLINE_LINUX`          | (generated)| Machine-specific boot params |
| `GRUB_DISABLE_LINUX_UUID`     | `true`     | Use device path, not UUID    |
| `GRUB_DISABLE_LINUX_PARTUUID` | `true`     | Use device path, not PARTUUID|
| `GRUB_GFXPAYLOAD_LINUX`      | `keep`     | Preserve graphics mode       |

---

## Maintenance Workflows (what the scripts automate)

### After Kernel Update

```
emerge @module-rebuild  # if needed
# 91-sbctl.install auto-PE-signs
# 99-update-boot.install auto-runs update-boot
#   which does: sbctl sign-all → grub-mkconfig → sign-boot.sh
```

Fully automatic if GPG key has no passphrase.

### After GRUB Package Update

```
build-grub    # rebuild standalone binary + PE sign
update-boot   # regenerate config + GPG sign
```

### After Config Change (e.g., kernel cmdline)

```
update-boot   # regenerate config + GPG sign
```

### After Changing Modules List

```
build-grub    # rebuild standalone binary
update-boot   # regenerate config + GPG sign
```

---

## Testing & Verification

After any change, verify with `audit-secureboot`. Key checks:

1. `sbctl status` shows Secure Boot enabled
2. `sbctl verify` shows all PE files signed
3. `gpg --verify /boot/grub/grub.cfg.sig /boot/grub/grub.cfg` succeeds
4. `gpg --verify /boot/kernel-*.sig /boot/kernel-*` succeeds
5. No stale signatures (target newer than .sig)
6. No missing signatures for GRUB-loaded files
7. `strings /boot/EFI/gentoo/grubx64.efi | grep check_signatures` shows
   the enforcement
8. `grep check_signatures /boot/grub/grub.cfg` shows expected lines

### Testing boot

After changes, verify the system boots correctly:
1. Reboot and select Linux — should boot normally
2. Select Windows — should chainload successfully
3. If GRUB password is set, verify shell access requires password

---

## Open Questions to Resolve During Implementation

1. **Module completeness**: Run `grep 'insmod ' /boot/grub/grub.cfg | sort -u`
   on the current system to ensure all modules referenced by grub-mkconfig
   output are in `grub/modules.txt`. The `grub-mkstandalone` binary must
   include everything grub.cfg needs.

2. **Memdisk module loading with check_signatures**: Verify that modules
   included via `--modules` to `grub-mkstandalone` are available without
   triggering signature checks (they should be, since they're pre-loaded
   into core). Modules on the memdisk (if any) might need `.sig` files.
   To avoid this, put ALL needed modules in the `--modules` list.

3. **GPG key passphrase vs no-passphrase**: The Gentoo wiki recommends
   no passphrase for the GRUB signing key when stored on encrypted root
   (since root access is already protected by LUKS). The current system
   uses a passphrase. Document both approaches but note the automation
   implications.

4. **Cleanup of old approach artifacts**: After switching to standalone,
   the `/boot/grub/x86_64-efi/*.mod` files and their `.sig` files may
   still exist. The migration path should clean these up.

5. **GRUB password protection**: Decide if this should be implemented
   in v1 or deferred. If implemented, needs:
   - `grub-mkpasswd-pbkdf2` to generate hash
   - Hash stored in `machine.conf`
   - Embedded in initial config
   - `--unrestricted` added to menu entries in `10_linux`

6. **`/boot/grub/` directory**: With standalone approach, does
   `grub-mkconfig` still need the module directory to exist for probing?
   Test whether `grub-mkconfig` works without `/boot/grub/x86_64-efi/`.

---

## Reference: Current System Commands

```bash
# Kernel cmdline (from /etc/default/grub)
GRUB_CMDLINE_LINUX="amdgpu.dcdebugmask=0x410 \
  rd.luks.name=4c53311c-c455-4952-969b-5324e2c1576c=gentoo-lvm \
  rd.luks.allow-discards \
  rd.lvm.vg=gentoo-vg0 \
  rd.lvm.lv=gentoo-vg0/root \
  rd.lvm.lv=gentoo-vg0/swap \
  root=/dev/mapper/gentoo--vg0-root \
  rootfstype=xfs \
  rootflags=rw,relatime,attr2,inode64,logbufs=8,logbsize=32k,noquota"

GRUB_CMDLINE_LINUX_DEFAULT="quiet systemd.show_status=y"

# GRUB USE flags (current)
# USE="device-mapper fonts mount nls sdl themes truetype"
# GRUB_PLATFORMS="efi-64 pc"

# sbctl managed files
# /boot/kernel-6.12.47-gentoo-dist
# /boot/shellx64.efi
# /boot/EFI/gentoo/grubx64.efi
# /boot/grub/x86_64-efi/core.efi
# /boot/grub/x86_64-efi/grub.efi

# EFI boot order
# Boot0001 (gentoo) → \EFI\gentoo\grubx64.efi  [active]
# Boot0000 (Windows) → \EFI\Microsoft\Boot\bootmgfw.efi
```

---

## Style and Code Conventions

- All scripts: `#!/usr/bin/env bash` with `set -euo pipefail`
- Use color output for user-facing messages (info=green, warn=yellow,
  error=red), with detection for non-tty to suppress colors
- Source `machine.conf` with validation (check required vars are set)
- All scripts should be idempotent (safe to run multiple times)
- Use `readonly` for constants
- Functions for reusable logic
- Descriptive error messages that tell the user what to do
- Root check at script entry (exit with clear message if not root,
  except for audit.sh which should work with degraded output)
