# XP8 unlock findings

Updated: 2026-10-01

Observations from the test unit after a full QFIL flash of the matching AT&T userdebug package, a stable fastboot session, and a QFIL read of `abl_a` and `devinfo`. No serials, IMEI, hostnames, or raw dumps.

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

Measured on a stable USB session:

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

- Size: 4096 bytes
- Contents: all zeros
- Hypothesized DeviceInfo unlock-allow dword at offset `+0x10`: `0`

## Static analysis (summarized)

The AT&T userdebug ABL contains the standard `flashing unlock` / `get_unlock_ability` strings and a policy check on DeviceInfo `+0x10` (nonzero means allow).

A Verizon / Android 10 donor ABL lacks that unlock command surface. Do not flash it as a fix.

A TWRP-pack `abl.elf` is a different size (~151,552 bytes) and is on hold.

## Tension and next experiment

A zero flag at `+0x10` would be expected to print `Flashing Unlock is not allowed`. The phone returned `unknown command` instead.

The next experiment is still to write a patched `devinfo` (little-endian uint32 `1` at offset `0x10`) via QFIL and retest. Local patch helper: [`scripts/xp8-patch-devinfo.ps1`](../scripts/xp8-patch-devinfo.ps1). Keep the original dump and restore it if the device does not boot.

## If unlock stays blocked

Keep using EDL/QFIL to write `boot` and `system`. Classic fastboot unlock is not available on this ABL as observed.

## Background

Community context (no official Sonim unlock program; EDL is the usual modification path; Android 10 unlock commands are often missing) is in [`xp8-bootloader-unlock-research.md`](xp8-bootloader-unlock-research.md).
