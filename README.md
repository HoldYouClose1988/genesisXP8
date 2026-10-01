# genesisXP8

Research notes and helper scripts for **Sonim XP8 (XP8800)** bootloader unlock work aimed at custom ROMs / recoveries.

## Current status

ATT XP8812 userdebug `8A.0.5-11-8.1.0-10.54.00` is bootloader-unlocked (`devinfo` `+0x10`) and running Magisk 30.7 on a QFIL-written patched stock `boot_a`. TWRP is deferred. Details: [`docs/findings.md`](docs/findings.md).

## Status

- **Root:** Magisk 30.7 confirmed on this unit (`uid=0`) via patched stock `boot_a` + QFIL; unlock held (`flash.locked=0`, orange).
- **Official unlock:** no Sonim OEM unlock program; stock user builds generally do not unlock via `fastboot oem unlock` / `fastboot flashing unlock`.
- **Practical mod path:** Qualcomm **EDL + Firehose** / QFIL partition R/W (community `prog_emmc_ufs_firehose_Sdm660_ddr.elf`). `fastboot boot` hung sending a large image on this ABL; QFIL writes to `boot_a` work.
- **True unlock:** this unit unlocks with ATT Android 8.1 userdebug ABL after patching `devinfo` `+0x10`. Full package flash rewrites `devinfo` and locks again until the patched image is restored.
- **This unit (XP8812 A8.1 userdebug):** unlocked + Magisk. Treble is off. Kernel config digest: [`docs/xp8-kernel-config-digest.md`](docs/xp8-kernel-config-digest.md). See [`docs/findings.md`](docs/findings.md).
- **Custom ROMs:** no mature public LineageOS/GSI; first aim is LineageOS 15.1 against this 8.1 / 4.4.78 stack, not a GSI.

This repo is **research documentation**, not a turnkey unlock toolkit. No exploit PoCs. Firmware blobs are not included.

## Safety notes

- Full EDL backup (especially modem/EFS) before abl/xbl/userdebug experiments.
- Cross-flash and userdebug flashes have caused baseband / IMEI loss in community reports.
- Prefer read-only inventory and signed Sonim images over unsigned bootloaders.

## License / intent

Public research notes for device owners. Cite upstream sources in the docs (XDA, Aleph, CVE databases, etc.).
