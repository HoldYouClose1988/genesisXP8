# XP8 kernel config digest

Source: on-device `/proc/config.gz` from ATT XP8812 userdebug `8A.0.5-11-8.1.0-10.54.00` after Magisk root (2026-10-01). Binary `config.gz` is not kept in this repo. No serials.

Header: `Linux/arm64 4.4.78 Kernel Configuration` (matches `uname` / inventory).

## Platform

| Option | Value |
|--------|--------|
| `CONFIG_ARM64` | y |
| `CONFIG_ARCH_QCOM` | y |
| `CONFIG_ARCH_SDM660` | y |
| `CONFIG_ARCH_SDM630` | y |
| `CONFIG_ARCH_MSM8998` | not set |
| `CONFIG_SMP` / `CONFIG_PREEMPT` | y |
| `CONFIG_HZ` | 100 |
| `CONFIG_MODULES` | y |
| `CONFIG_IKCONFIG` / `_PROC` | y |
| Appended DTB | `CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y` (`Image.gz-dtb`) |

Kernel is a Qualcomm SDM660/630 4.4.78 Android tree, not MSM8998-named.

## Android / security

| Option | Value |
|--------|--------|
| `CONFIG_ANDROID` | y |
| `CONFIG_ANDROID_BINDER_IPC` | y |
| binder devices | `binder,hwbinder,vndbinder` |
| `CONFIG_ANDROID_BINDERFS` | absent |
| `CONFIG_SECURITY_SELINUX` | y (develop) |
| `CONFIG_DM_VERITY` | y (+ FEC) |

## Filesystems

| Option | Value |
|--------|--------|
| `CONFIG_EXT4_FS` | y |
| `CONFIG_F2FS_FS` | not set |
| `CONFIG_OVERLAY_FS` | not set |
| `CONFIG_ZRAM` | y |

Stock userdata path is ext4-oriented. No F2FS/overlay in this defconfig.

## Display / GPU

| Option | Value |
|--------|--------|
| `CONFIG_FB` / `CONFIG_FB_MSM_MDSS` | y |
| `CONFIG_DRM_MSM` | absent |
| `CONFIG_QCOM_KGSL` | y |

MDSS framebuffer stack, not mainline DRM/MSM. Port trees that assume DRM-only need an older display path.

## Audio

`CONFIG_SND_SOC_660`, QDSP6v2, WCD934X / WCD9XXX family, plus `CONFIG_SND_SOC_TFA98XX` (amplifiers).

## Touch / biometrics / keys

| Option | Value |
|--------|--------|
| Synaptics DSX v21 | y (I2C) |
| Cypress CYTTSP5 | y (I2C, MT_B, button, proximity, FW loader) |
| Goodix touchscreen | not set |
| `CONFIG_GOODIX_FINGERPRINT` | y |
| `CONFIG_KEYBOARD_GPIO` | y |

Expect XP8-specific DT for whichever touch controller the ATT unit uses; fingerprint is Goodix.

## Power / USB / NFC / video

- Charger/FG: `CONFIG_QPNP_SMB2`, `CONFIG_QPNP_FG_GEN3`
- USB: `CONFIG_USB_DWC3_QCOM`, configfs gadgets (MTP/ADB/diag/rmnet/...)
- NFC: `CONFIG_NFC_NQ`
- Video: `CONFIG_MSM_VIDC_V4L2`
- Wi-Fi stack markers: WCNSS/CNSS core options mostly unset; `CONFIG_CFG80211`, `CONFIG_CNSS_UTILS` / `CNSS_GENL` present (vendor modules likely out-of-tree)

## Port implications

1. Target LineageOS **15.1** (Android 8.1) against this 4.4.78 SDM660 tree; do not assume Treble/GSI (`ro.treble.enabled=false` on device).
2. Prefer CAF/QCOM 4.4 SDM660 references over newer DRM-first trees.
3. Device tree must cover Synaptics and/or Cypress touch, Goodix FP, TFA98XX, QPNP SMB2/FG Gen3, NQ NFC.
4. Keep a local `/proc/config.gz` pull as the baseline `arch/arm64/configs` comparison when a Sonim/GPL tree appears.
