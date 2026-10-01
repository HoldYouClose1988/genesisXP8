# XP8 unlock findings

Updated: 2026-10-01

Bootloader unlock succeeded on 2026-10-01 on the ATT XP8812 Android 8.1.0 userdebug test phone, build `8A.0.5-11-8.1.0-10.54.00`.

The sections below keep the earlier observations from that unit: a full QFIL flash of the matching AT&T userdebug package, a stable fastboot session, and a QFIL read of `abl_a` and `devinfo`, plus the `devinfo` patch that unlocked the bootloader. No serials, IMEI, hostnames, or raw dumps.

## Confirmed unlock

Method: the original `devinfo` partition was 4096 bytes and all zeros. [`scripts/xp8-patch-devinfo.ps1`](../scripts/xp8-patch-devinfo.ps1) built a patched image with a little-endian uint32 `1` at offset `0x10` (DeviceInfo unlock-allow flag from the ABL teardown). That image was written with QFIL. Then `fastboot flashing unlock` returned `OKAY`.

Proof after reboot:

| Check | Result |
|-------|--------|
| `fastboot getvar unlocked` | `yes` |
| `ro.boot.flash.locked` | `0` |
| `ro.boot.verifiedbootstate` | `orange` |
| `sys.oem_unlock_allowed` | `1` |

`fastboot getvar all` still returns `unknown command`. That is an ABL limitation, not a failed unlock. Unlock state is reported by `getvar unlocked`.

Do not flash the Verizon donor ABL. Do not run `fastboot flashing lock` casually. Keep the original all-zero `devinfo` dump and write it back with QFIL if a later experiment needs the locked state.

## Device

- Class: Sonim XP8
- Product: XP8812
- Model: XP8800
- Image: AT&T userdebug
- Android: 8.1.0
- Build: `8A.0.5-11-8.1.0-10.54.00`
- Keys: test-keys
- Board platform: sdm660
- Storage: eMMC
- Slots: A/B

## OEM unlocking toggle

OEM unlocking can be toggled in Developer options. After a fresh QFIL flash, `settings get global oem_unlock_allowed` was null until the toggle was turned on again. The toggle alone does not unlock the bootloader.

## Fastboot on the reflashed userdebug image

Measured on a stable USB session before the `devinfo` patch:

| Command | Result |
|---------|--------|
| `getvar unlocked` | `no` |
| `flashing unlock` | remote `unknown command` |
| `oem unlock` | remote `unknown command` |
| `flashing get_unlock_ability` | remote `unknown command` |

## What the full QFIL flash already wrote

`rawprogram0.xml` from that userdebug package programs `xbl.elf` to `xbl_a` / `xbl_b` and `abl.elf` to `abl_a` / `abl_b`. A full QFIL flash therefore already wrote those bootloaders. Re-flashing the same ABL and XBL is a no-op for unlock.

## On-device `abl_a` vs package `abl.elf`

| Image | Size | SHA256 |
|-------|------|--------|
| Package `abl.elf` | 110,592 | `7e6145d80b9fb46b7a9fdc326bd00d9593c21e3bd7929490abeb967bd9272648` |
| QFIL dump of `abl_a` | 1,048,576 | `e2fa7b0e8254ca4c9621658d232caba7ca21e1ae846ce5979a27dbea9679a35a` |

The first 110,592 bytes match. The rest of the partition dump is `0x00` padding. The bootloader on the device is the AT&T userdebug package ABL.

## On-device `devinfo`

Pre-patch QFIL read, before the unlock write:

- Size: 4096 bytes
- Contents: all zeros
- DeviceInfo unlock-allow dword at offset `+0x10`: `0`

The successful unlock wrote the patched image (little-endian uint32 `1` at `0x10`) over this partition. The pre-patch contents really were all zeros.

## Static analysis (summarized)

The AT&T userdebug ABL contains the standard `flashing unlock` / `get_unlock_ability` strings and a policy check on DeviceInfo `+0x10` (nonzero means allow).

A Verizon / Android 10 donor ABL lacks that unlock command surface. Do not flash it as a fix.

A TWRP-pack `abl.elf` is a different size (~151,552 bytes) and is on hold.

## Tension, then the experiment

A zero flag at `+0x10` would be expected to print `Flashing Unlock is not allowed`. Before the patch, the phone returned `unknown command` instead.

That experiment was run on 2026-10-01: a patched `devinfo` (little-endian uint32 `1` at offset `0x10`), built with [`scripts/xp8-patch-devinfo.ps1`](../scripts/xp8-patch-devinfo.ps1) and written via QFIL. `fastboot flashing unlock` then returned `OKAY`. The earlier `unknown command` was the pre-patch state. Keep the original all-zero dump and restore it with QFIL if a later experiment needs the locked state. Do not run `fastboot flashing lock` casually.

## What did not unlock the bootloader

- OEM unlocking toggle alone
- `fastboot oem unlock` / `flashing unlock` before the devinfo patch (`unknown command`)
- Re-flashing the same userdebug `abl` / `xbl` (already on the device)
- Verizon / Android 10 donor ABL (missing the unlock command surface; not flashed)

## If unlock had stayed blocked

The fallback, had the patch failed, was to keep using EDL/QFIL to write `boot` and `system`. Classic fastboot unlock was not available on this ABL as observed before the patch. That fallback is not the current state: unlock succeeded.

## Background

Community context (no official Sonim unlock program; EDL is the usual modification path; Android 10 unlock commands are often missing) is in [`xp8-bootloader-unlock-research.md`](xp8-bootloader-unlock-research.md).
