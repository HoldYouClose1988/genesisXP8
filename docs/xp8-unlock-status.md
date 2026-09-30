# XP8 unlock status

Short status for the test XP8812 (Android 8.1 userdebug, sdm660 eMMC). No serials.

## Current

- **OEM unlocking** in Developer options: **enabled**
- Bootloader still reports **`unlocked: no`**
- Fastboot unlock attempts both failed with `FAILED (remote: 'unknown command')`:
  - `./fastboot.exe flashing unlock`
  - `./fastboot.exe oem unlock`
- Working Firehose programmer already available: `prog_emmc_ufs_firehose_Sdm660_ddr.elf`

## Verdict

Current ABL does not expose a usable fastboot unlock command path. OEM toggle alone is not enough on this build.

## Next

1. Enter EDL (manual confirm; typically `./adb.exe reboot edl`)
2. **READ-ONLY** dump of GPT + abl/xbl (+ config) + devinfo + vbmeta slots if present
3. Flash **Sonim-signed debug abl/xbl** from the matching userdebug package (manual confirm; user-supplied images only)
4. Reboot to bootloader and retry unlock commands

Helper: [`scripts/xp8-edl-abl-prep.ps1`](../scripts/xp8-edl-abl-prep.ps1). Default mode is dump-only; write requires `-AllowWrite` plus typed `CONFIRM`.
