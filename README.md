# genesisXP8

Research notes and helper scripts for **Sonim XP8 (XP8800)** bootloader unlock work aimed at custom ROMs / recoveries.

## Status

- **Root:** already achieved on the test path (typically Magisk via Qualcomm EDL, often with a still-locked bootloader).
- **Official unlock:** no Sonim OEM unlock program; stock user builds generally do not unlock via `fastboot oem unlock` / `fastboot flashing unlock`.
- **Practical mod path:** Qualcomm **EDL + Firehose** partition R/W (community `prog_emmc_ufs_firehose_Sdm660_ddr.elf`), not a clean fastboot unlock.
- **True unlock:** inconsistently reported; best community trail is around **AT&T Android 8.1 userdebug / debug ABL+XBL**. Android 10 unlock commands are often `unknown command`.
- **Custom ROMs:** no mature public LineageOS/GSI known to run reliably on XP8.

This repo is **research documentation**, not a turnkey unlock toolkit. No exploit PoCs. Firmware blobs are not included.

## Layout

| Path | Contents |
|------|----------|
| [`docs/xp8-bootloader-unlock-research.md`](docs/xp8-bootloader-unlock-research.md) | XP8 unlock / EDL / carrier landscape |
| [`docs/sdm630-bootloader-exploit-research.md`](docs/sdm630-bootloader-exploit-research.md) | SDM630/6xx public CVE & technique map (high-level) |
| [`docs/sdm660-firehose-edl-research.md`](docs/sdm660-firehose-edl-research.md) | Firehose/EDL auth vs storage R/W mapped to XP8 |
| [`scripts/xp8-adb-inventory.ps1`](scripts/xp8-adb-inventory.ps1) | PowerShell adb/fastboot device inventory |

## Run the inventory script

Requires [platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb` + `fastboot`) and an authorized USB debugging session.

```powershell
cd scripts
.\xp8-adb-inventory.ps1
# or:
.\xp8-adb-inventory.ps1 -ToolsDir C:\platform-tools
.\xp8-adb-inventory.ps1 -SkipFastboot
```

Writes `xp8-inventory-YYYYMMDD-HHMMSS.txt` next to the script (or under `-OutDir`). Those reports can contain **serials / radio identifiers** — do not commit or publish them (see `.gitignore`).

## Safety notes

- Full EDL backup (especially modem/EFS) before abl/xbl/userdebug experiments.
- Cross-flash and userdebug flashes have caused baseband / IMEI loss in community reports.
- Prefer read-only inventory and signed Sonim images over unsigned bootloaders.

## License / intent

Public research notes for device owners. Cite upstream sources in the docs (XDA, Aleph, CVE databases, etc.). Keep secrets, dumps, and personal inventory outputs out of git.
