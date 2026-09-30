---
title: SDM660 Firehose / EDL Techniques Mapped to XP8
date: 2026-09-30
status: research
device: Sonim XP8 (XP8800) / SDM630 family (Sdm660 programmer naming)
goal: Map public Firehose auth-bypass vs storage R/W techniques; no PoCs
prior:
  - docs/xp8-bootloader-unlock-research.md
  - docs/sdm630-bootloader-exploit-research.md
constraints: public sources only; high-level technique classes; no XML/peek/poke recipes
---

# SDM660 Firehose / EDL Research (XP8 mapping)

**Bottom line:** XP8 already has the hard gate that Aleph and bkerler treat as “getting Firehose” — Sahara accepted a matching signed programmer (`prog_emmc_ufs_firehose_Sdm660_ddr.elf`). The Xiaomi-style **Firehose `sig` auth bypass** that people chase on SDM660 is **not the missing piece** here. What remains is **storage R/W of OEM-signed images and OEM policy bits** (`abl`/`xbl`/`devinfo`/`vbmeta`), plus an inventory of whether *this* programmer also exposes **peek** or **VIP**. There is **no public XP8-specific Firehose exploit** and no reason to import foreign 660 “no-auth” loaders.

Chipset CVEs and ABL overflow work stay in the prior report: [sdm630-bootloader-exploit-research.md](./sdm630-bootloader-exploit-research.md). Device/unlock community context: [xp8-bootloader-unlock-research.md](./xp8-bootloader-unlock-research.md).

---

## 1. What the Aleph Security series actually established

Five posts (22 Jan 2018), plus advisory **ALEPH-2017028** / Qualcomm **QPSIIR-909**. Authors: Roee Hay & Noam Hadad.

| Part | URL | What it established (high-level) |
|------|-----|----------------------------------|
| **1** | https://alephsecurity.com/2018/01/22/qualcomm-edl-1/ | PBL implements EDL; Sahara loads an **OEM-signed** programmer (ELF/MBN) that then speaks **Firehose XML-over-USB**. Firehose is essentially an SBL with a `firehose_main` loop. Documented tags include `configure`, `program`, `read`, `getstorageinfo`, `erase`, `peek`, `poke`. Leaked programmers exist because OEMs ship/repair with them. Table includes **Xiaomi Note 3 (jason) / SDM660** `prog_emmc_firehose_Sdm660_ddr.elf` (**untested** by Aleph). |
| **2** | https://alephsecurity.com/2018/01/22/qualcomm-edl-2/ | **Storage class:** `program`/`patch` write flash; `read` dumps it. Signed-image **rollback** when OEM did not fuse anti-rollback. On **some Xiaomi** devices, unlock state lives in `devinfo` and flipping it via Firehose made ABL treat the device as unlocked. Storage write does **not** by itself load **unsigned** XBL/ABL on a fused chain of trust. |
| **3** | https://alephsecurity.com/2018/01/22/qualcomm-edl-3/ | **Memory class:** `peek`/`poke` are OEM **build customizations** (Qualcomm said so), not a guaranteed SoC feature. Used as primitives toward code execution **inside the programmer**, then PBL dumps on **select** chips (MSM8994/8917/8937/8953/8974 in their work — **not** an SDM660 PBL dump). |
| **4** | https://alephsecurity.com/2018/01/22/qualcomm-edl-4/ | **firehorse** runtime debugger for Firehose programmers (relocatable, 32- and 64-bit). Research tooling, not a generic unlock. |
| **5** | https://alephsecurity.com/2018/01/22/qualcomm-edl-5/ | End-to-end **Nokia 6 MSM8937** secure-boot research using peek/poke + debugger (PBL clone / MMU remap class). Aleph argued similar *might* apply to other MSM8937; **not demonstrated on SDM630/660 or Sonim**. |

Advisory (peek/poke as arbitrary memory R/W in the programmer context; Qualcomm: OEM customization; remediation: **anti-rollback of leaked programmers**):

- https://alephsecurity.com/vulns/aleph-2017028
- Framework: https://github.com/alephsecurity/firehorse

**XP8 takeaway from Aleph:** the series is two stacked classes — (A) **storage** once a matching programmer is loaded, (B) **memory/PBL** only if **that** programmer still has peek/poke and the SoC/PBL layout cooperates. XP8 already has (A) in community practice. (B) is **unproven** on Sonim and is not required for partition R/W.

---

## 2. What bkerler/edl implements (capability level)

Repo: https://github.com/bkerler/edl  
Loader collection: https://github.com/bkerler/Loaders  
Companion write-up (Sahara HWID/PK hash, unfused vs fused): https://bkerler.github.io/2020/08/03/bring-light-to-the-darkness-p3/

| Capability | What it is | XP8 relevance |
|------------|------------|---------------|
| **Loader DB + `fhloaderparse`** | Index/rename programmers as `msmid_pkhash[8 bytes].bin` (and OEM folders). Autodetect by Sahara HWID + PK hash. | Matches how the public Sonim peek file is named. Working XP8 ELF can be ingested the same way. |
| **Sahara client** | Handshake, read HWID / OEM PK hash / serial (Sahara v1/v2). Sahara **v3** often **stops** exposing PK hash (`OEM_PK_HASH_READ`); `--loader` then required. SDM630-era phones are typically **pre-v3**. | Inventory: dump PK hash on the test unit. |
| **Firehose XML** | `configure`, GPT print, partition/LUN read/write/erase, QFIL-style `rawprogram`/`patch` replay, generic XML send. eMMC vs UFS (`--memory=ufs`). | XP8 is **eMMC** (community QFIL/fh_loader usage). This is the storage class Aleph Part 2 describes, packaged as a client. |
| **Peek loaders** | If the **loaded programmer** implements peek/poke, the client can request memory R/W, and on **EL3** programmers optionally dump PBL / show secure-boot fuse summaries. | Only if *this* XP8 programmer advertises peek. Filename `_fhprg_peek.bin` is a **hint**, not proof for the community ELF. |
| **PK-hash matching** | Fused devices accept a programmer iff its **root-cert hash** matches the fused OEM PK hash. Wrong OEM 660 ELF is rejected at Sahara, even if the SoC string is SDM660. | Cross-OEM “auth-bypass” 660 loaders are a **dead end**. |
| **Vendor `sig` / Xiaomi auth** | Some Xiaomi programmers refuse `program`/`read` until a custom Firehose **`sig`** blob is accepted. README still lists **“Secure loader with SDM660 on Xiaomi not yet supported (EDL authentification)”** as an issue; VIP programming is also **unsupported**. | Xiaomi SDM660 problem, **not** documented on Sonim. |
| **`modules oemunlock`** | Tool hook that toggles an OEM **`config`** partition **if that layout exists**, then still needs fastboot unlock. | **Not** shown on XP8; do not assume Motorola-style `config`. |

Public Windows counterpart with the same PK-hash lookup model: https://www.temblast.com/edl.htm and the loader index https://www.temblast.com/ref/loaders.htm.

This report does **not** reproduce client command lines or Firehose XML.

---

## 3. SDM660-specific public findings vs generic 6xx

SDM630 / 636 / 660 share the mid-2017 6xx Firehose *software* surface (PBL → Sahara → signed ELF → XML). Tooling often labels **MSM ID `0x0008c0e1` as “SDM660”** even when the phone is an SDM630. That is a **filename/HWID convention**, not proof the die is 660.

| Finding | 6xx-generic? | SDM660-specific public trail | XP8 |
|---------|--------------|------------------------------|------|
| Sahara PK-hash gate | Yes | Same HWID family; **different OEM hashes**. Foxconn/Sony, Xiaomi, Motorola, Sunmi, CAT all need *their* hash. Example: bkerler [issue #78](https://github.com/bkerler/edl/issues/78) (`0008c0e1` + Xiaomi/Foxconn hashes). Sunmi T2S loaders missing: [#536](https://github.com/bkerler/edl/issues/536), [#537](https://github.com/bkerler/edl/issues/537). CAT S62 rejects foreign Sdm660 ELFs: [XDA](https://xdaforums.com/t/help-cat-s62-sdm660-stuck-in-fastboot-loop-need-signed-firehose-oem-id-0180.4779639/). | Working ELF already proves **Sonim-matching** hash. |
| Xiaomi Firehose **`sig`** before storage | OEM policy | Very visible on Xiaomi **660/636** programmers: after Sahara success, Firehose logs *“Only nop and sig tag can be received before authentication.”* Community “bypass” = **older/no-`sig` programmer for that same Xiaomi PK hash**, not a Sahara break. [XDA fireHose thread](https://xdaforums.com/t/firehose.3802143/); bkerler [issue #10](https://github.com/bkerler/edl/issues/10). | **No public Sonim `sig` gate.** QFIL/fh_loader already programs partitions. |
| Qualcomm **VIP** (signed digest table of allowed packets) | Optional OEM/QC feature | Official: [VIP flashing](https://docs.qualcomm.com/doc/80-80020-11/topic/vip-flashing.html). Each XML/data packet must match the next signed digest or the programmer **halts**. bkerler: VIP **not implemented** in edl. More often discussed on **newer** SoCs than leaked 6xx ELFs. | Community full-partition R/W implies VIP is **off or not enforced** on the XP8 programmer. Confirm via absence of “VIP is enabled” / digest-auth failures. |
| Peek/poke | Programmer build flag | Aleph: Qualcomm called it OEM customization. Android bulletin **CVE-2018-3591** (2018-04-01) lists **SDM630/636/660** for default `SKIP_SECBOOT_CHECK_NOT_RECOMMENDED_BY_QUALCOMM` peek/poke: https://source.android.com/docs/security/bulletin/2018-04-01 | May or may not be compiled into the **Sonim** ELF. Indexed peek file suggests *a* Sonim 6xx peek programmer exists in the wild. |
| `devinfo` unlock bit | OEM ABL | Aleph Part 2 demonstrated on **Xiaomi**, not as a Qualcomm fuse. | **Unverified** on XP8 (prior report: at least one Verizon owner saw no simple flag). |
| Aleph SDM660 programmer | Table row | jason `Sdm660` ELF listed, **not tested**. Memory/PBL work in the series is **other SoCs**. | Do not treat Aleph Part 5 as an XP8 cookbook. |

**Loader identification (Renate / XDA):** a single ELF can list many 6xx models (`SDA630`/`SDM636`/`SDM660`, …). Compatibility is still **root-CA fingerprint / EDL Hash**, not the SoC string. https://xdaforums.com/t/identifying-edl-firehose-loaders.4525079/

---

## 4. Does XP8 still need an “auth bypass”?

**No — not in the Sahara / Xiaomi-`sig` / VIP sense.**

Three different “auth” layers get conflated in 660 threads:

| Layer | What it blocks | XP8 public status |
|-------|----------------|-------------------|
| **Sahara / PK hash** | Loading any programmer | **Passed.** Community `prog_emmc_ufs_firehose_Sdm660_ddr.elf` loads (eleotk / smokeyou era). XDA: [Carrier Firmware](https://xdaforums.com/t/carrier-firmware-sonim-xp8.3907876/), [Root thread](https://xdaforums.com/t/sonim-xp8-root.3851187/). |
| **Firehose VIP digest** | Which XML packets run | **Not reported** on XP8. Arbitrary partition backup/restore via QFIL/fh_loader is the opposite of a locked digest table. |
| **OEM `sig` (Xiaomi-class)** | Storage R/W after Firehose starts | **Not reported** on Sonim. That is the “SDM660 auth bypass” folklore. |

What XP8 **does** still need for a **true bootloader unlock** is not a Firehose auth break. It is **OEM policy**: ABL/XBL that implement `fastboot flashing unlock`, and/or whatever storage ABL consults (`devinfo`, FRP, RPMB/TEE). Firehose is already the **transport** to read/write those partitions with **OEM-signed** images. That is Aleph Part 2’s storage class, which XP8 owners have been using for Magisk/`boot` and firmware restore for years — it **bypasses the need for unlock to modify many images**, but it is **not** itself an unlocked bootloader.

Writing **unsigned** `abl`/`xbl` remains blocked by fused secure boot unless a separate bypass exists (none public for XP8). See prior SDM630 report.

---

## 5. Public Sonim peek loader and PK-hash matching

Temblast index (signer **Sonim**, ELF64, source **B** = bkerler/Loaders):

https://www.temblast.com/ref/loaders.htm

| Field | Public value |
|-------|----------------|
| Path | `sonim/0008c0e100010000_1b55c83cc1c00f4f_fhprg_peek.bin` |
| Collection | https://github.com/bkerler/Loaders/tree/master/sonim (same filename in that tree) |
| HWID in name | `0008c0e100010000` → MSM `0008c0e1` (tooling: SDM660-class), **OEM `0001`**, model `0000` |
| PK-hash prefix | `1b55c83cc1c00f4f` (first 16 hexits of SHA-256 root CA / EDL Hash) |
| Extra hashes listed | SHA384 prefix `cae935acd79034e7`; file MD5 prefix `d42c955805de4e92` |

**What PK-hash matching means:** on a fused phone, Sahara will only execute a programmer whose **certificate chain hashes to the fused OEM root**. Filename `msmid_pkhash` is an index key. Matching the first 16 hexits is how you know a random `Sdm660` ELF is even a candidate. Mismatch → Sahara reject; **not** a Firehose problem.

**What `_fhprg_peek` means:** bkerler/Loaders naming for programmers believed to expose **peek** (and usually poke). It does **not** mean:

- it is confirmed to be the same binary as XP8’s `prog_emmc_ufs_firehose_Sdm660_ddr.elf`;
- peek is enabled on the ELF the community actually uses;
- EL3 / PBL-dump / Nokia-6-class research will work.

**No public write-up** was found that says “XP8 uses `1b55c83cc1c00f4f`” or that the peek bin and the XP8 ELF are identical. That is an **on-device measurement**.

---

## 6. Owner-actionable vs OEM/lab-only

Assumptions: test XP8, firehose already works, root, Android 8 userdebug images exist, baseband already dead, OK to brick the test unit.

| Action class | Owner with working Firehose | OEM / lab keys |
|--------------|-----------------------------|----------------|
| Sahara PK hash / HWID dump; GPT / partition list | **Yes** (read-only) | — |
| Dump `abl`/`xbl`/`devinfo`/`vbmeta`/`frp`/`misc`/`sec` | **Yes** | — |
| Flash **Sonim-signed** userdebug or debug ABL+XBL (community claim toward unlock) | **Yes if images are public and ARB allows** | Signing a *new* ABL: **OEM keys** |
| Inspect whether Firehose lists peek / errors on VIP or `sig` | **Yes** | — |
| Xiaomi no-auth 660 ELF / “patched” foreign programmer | **No** (wrong PK hash) | — |
| Build/sign a custom Firehose, VIP digest table, or unsigned XBL | **No** | **OEM keys + (for VIP) signed digest table** — https://docs.qualcomm.com/doc/80-80020-11/topic/vip-flashing.html |
| Aleph memory/PBL class | Only if **this** programmer has peek/poke **and** further RE — **not** a documented XP8 unlock | Turning peek into a secure-boot break is research-grade (Aleph Part 5 was Nokia 6) |
| `devinfo` bit-flip like Xiaomi | Only if dumps show that layout **and** this ABL honors it | — |
| firehorse / EL3 debugger | Research optional; **not** required for storage unlock path | — |

**Highest-likelihood owner path to true unlock** remains the prior reports’ **signed debug ABL/XBL / userdebug** experiment — storage write of **already-signed** images — not a Firehose authentication exploit.

---

## 7. Recommended probes (inventory first, writes later)

Do **not** start with peek/poke memory experiments or unsigned images.

### Phase A — read-only / inventory (do this next)

1. **Sahara identity:** HWID, full **OEM PK hash**, serial, Sahara version. Compare prefix to `1b55c83cc1c00f4f`. Compare HWID OEM field to `0001` (indexed Sonim file) vs other OEM IDs.
2. **Programmer identity:** root-CA fingerprint of the working `prog_emmc_ufs_firehose_Sdm660_ddr.elf` vs the peek bin vs the device Hash (qcomview-class / `fhloaderparse` class tools — https://xdaforums.com/t/identifying-edl-firehose-loaders.4525079/).
3. **Firehose feature list:** from the programmer’s own “supported functions” / configure logs: presence of `read`/`program` (expected), `peek`/`poke`, `sig`, and any VIP / digest-auth errors.
4. **GPT / partition names and sizes** (eMMC): confirm `abl_a/b`, `xbl_a/b`, `devinfo`, `vbmeta_a/b`, `frp`, `misc`, `sec`, slots.
5. **Read-only dumps** of those small partitions plus current `abl`/`xbl` (hashes/strings only needed for unlock-policy RE). Look for `ANDROID-BOOT!` vs empty/other `devinfo`; presence of unlock command strings in ABL. **Do not** treat Xiaomi offsets as applicable.
6. **ARB / version strings** in dumped ABL/XBL vs public ATT userdebug images (can a signed older/debug image still load?).

### Phase B — later write experiments (only after A)

- Smallest signed change first: **debug/userdebug ABL+XBL** from matching Android 8 / closest carrier, then re-check `fastboot oem device-info` / unlock commands (prior XP8 report). Keep a full EDL backup first.
- Only if dumps show a **simple, ABL-honored** unlock flag: consider a **storage** experiment on that partition — still OEM-layout-specific, not a published XP8 recipe.
- Peek/memory class: optional research **after** feature inventory; it does not replace signed ABL work for unlock.

Public clients that already implement Phase A without inventing protocol: **bkerler/edl**, **QFIL/fh_loader** (as XP8 community used), **temblast edl.exe**.

---

## 8. Uncertainty log

- Device PK hash vs `1b55c83cc1c00f4f` vs community ELF: **unmeasured** on this unit.
- Whether the working ELF exposes **peek**: **unknown** until the supported-function list is captured.
- Whether VIP or a Sonim `sig` gate exists on some SKUs/OTAs: **no public reports**; community R/W argues against it on the known programmer.
- Whether Sonim ABL stores unlock in `devinfo` / FRP / RPMB: **unknown**; Xiaomi Part 2 does not transfer by default.
- Whether debug ABL+XBL still enables unlock in 2026: **aging ATT anecdote** (prior report).
- Aleph Part 5 / firehorse: **Nokia 6 MSM8937**; applicability to SDM630 PBL **not shown**.
- Indexed Sonim peek bin’s exact device coverage (XP8 vs other Sonim 6xx): **not documented** beyond HWID/hash.
- Qualcomm Firehose spec **80-NG319-1** circulates as a protocol definition (VIP = ordered SHA-256 digest table). Prefer Qualcomm’s current VIP docs + Aleph for public citation; do not treat leaked PDFs as XP8 device facts.

**Not found:** any public XP8 Firehose authentication bypass, unsigned programmer, or storage unlock cookbook.

---

## Key source index

| Resource | URL |
|----------|-----|
| Aleph EDL 1 (Sahara/Firehose) | https://alephsecurity.com/2018/01/22/qualcomm-edl-1/ |
| Aleph EDL 2 (storage / rollback / Xiaomi `devinfo`) | https://alephsecurity.com/2018/01/22/qualcomm-edl-2/ |
| Aleph EDL 3 (peek/poke / memory) | https://alephsecurity.com/2018/01/22/qualcomm-edl-3/ |
| Aleph EDL 4 (debugger) | https://alephsecurity.com/2018/01/22/qualcomm-edl-4/ |
| Aleph EDL 5 (Nokia 6 SB research) | https://alephsecurity.com/2018/01/22/qualcomm-edl-5/ |
| ALEPH-2017028 | https://alephsecurity.com/vulns/aleph-2017028 |
| firehorse | https://github.com/alephsecurity/firehorse |
| bkerler/edl | https://github.com/bkerler/edl |
| bkerler/Loaders | https://github.com/bkerler/Loaders |
| bkerler Sahara/PK-hash notes | https://bkerler.github.io/2020/08/03/bring-light-to-the-darkness-p3/ |
| Qualcomm VIP flashing | https://docs.qualcomm.com/doc/80-80020-11/topic/vip-flashing.html |
| CVE-2018-3591 (SDM630/660 peek class) | https://source.android.com/docs/security/bulletin/2018-04-01 |
| Temblast loader index (Sonim peek) | https://www.temblast.com/ref/loaders.htm |
| XDA identifying loaders / PK hash | https://xdaforums.com/t/identifying-edl-firehose-loaders.4525079/ |
| XDA Xiaomi 660 `sig` auth | https://xdaforums.com/t/firehose.3802143/ |
| XDA XP8 EDL firmware / firehose | https://xdaforums.com/t/carrier-firmware-sonim-xp8.3907876/ |
| Prior XP8 unlock research | ./xp8-bootloader-unlock-research.md |
| Prior SDM630 exploit map | ./sdm630-bootloader-exploit-research.md |
