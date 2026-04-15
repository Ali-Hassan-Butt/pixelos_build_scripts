#!/bin/bash
# =============================================================================
#  PixelOS 16 (sixteen-qpr2) — Xiaomi Mi 10T (apollo)
#  Crave.io Build Script — With NTSync SELinux rules
#
#  HOW TO RUN THIS ON CRAVE (from your devspace terminal):
#
#    crave run --no-patch --clean "bash build.sh"
#
#  Or if you store this script in a GitHub repo:
#
#    crave run --no-patch --clean \
#      "wget -q -O build.sh <YOUR_RAW_GITHUB_LINK> && bash build.sh"
# =============================================================================

set -e  # Stop the whole script if any command fails (no silent errors!)

echo ""
echo "=========================================="
echo "  PixelOS 16 — apollo — Crave Build"
echo "=========================================="
echo ""

# ─────────────────────────────────────────────
# STEP 1 — Initialize PixelOS 16 source
# ─────────────────────────────────────────────
echo "[1/5] Initializing PixelOS 16 manifest..."

repo init \
  -u https://github.com/PixelOS-AOSP/android_manifest.git \
  -b sixteen-qpr2 \
  --git-lfs \
  --depth=1

# ─────────────────────────────────────────────
# STEP 2 — Set up local manifests (device trees)
# ─────────────────────────────────────────────
echo "[2/5] Setting up local manifests..."

# Remove any old local manifests to start fresh
rm -rf .repo/local_manifests

# Clone YOUR local_manifests repo from GitHub.
# TODO: Replace this URL with your own GitHub repo containing roomservice.xml
git clone \
  -b main \
  https://github.com/Ali-Hassan-Butt/local_manifests_apollo \
  .repo/local_manifests

# ─────────────────────────────────────────────
# STEP 3 — Sync all sources (Crave-optimized)
# ─────────────────────────────────────────────
echo "[3/5] Syncing sources via Crave resync..."
# /opt/crave/resync.sh is a special Crave script — use this instead of repo sync
# It is MUCH faster because Crave caches the base ROM for you
/opt/crave/resync.sh

# ─────────────────────────────────────────────
# STEP 4 — Apply NTSync SELinux rules
# This patches the sm8250-common device tree's sepolicy
# to allow /dev/ntsync access (needed for NTSync kernel driver)
# Reference: https://github.com/Meow-prjkt/android_device_xiaomi_sm8250-common/commit/f83809468e7d982888bb6cbb7e7a2f83c4bccb2d
# ─────────────────────────────────────────────
echo "[4/5] Applying NTSync SELinux rules..."

SEPOLICY_DIR="device/xiaomi/sm8250-common/sepolicy/vendor"

# --- 4a. device.te — declare the ntsync device type ---
# Only add if it's not already there (safe to run multiple times)
if ! grep -q "ntsync_device" "${SEPOLICY_DIR}/device.te"; then
  echo "" >> "${SEPOLICY_DIR}/device.te"
  echo "# NTSync device" >> "${SEPOLICY_DIR}/device.te"
  echo "type ntsync_device, dev_type;" >> "${SEPOLICY_DIR}/device.te"
  echo "  [NTSync] Added type declaration to device.te"
else
  echo "  [NTSync] device.te already patched, skipping."
fi

# --- 4b. file_contexts — label /dev/ntsync ---
if ! grep -q "ntsync" "${SEPOLICY_DIR}/file_contexts"; then
  echo "" >> "${SEPOLICY_DIR}/file_contexts"
  echo "# Ntsync" >> "${SEPOLICY_DIR}/file_contexts"
  echo "/dev/ntsync  u:object_r:ntsync_device:s0" >> "${SEPOLICY_DIR}/file_contexts"
  echo "  [NTSync] Labeled /dev/ntsync in file_contexts"
else
  echo "  [NTSync] file_contexts already patched, skipping."
fi

# --- 4c. system_server.te — allow system_server to use ntsync ---
if ! grep -q "ntsync_device" "${SEPOLICY_DIR}/system_server.te"; then
  echo "" >> "${SEPOLICY_DIR}/system_server.te"
  echo "# NTSync - allow system_server access" >> "${SEPOLICY_DIR}/system_server.te"
  echo "allow system_server ntsync_device:chr_file { getattr open read write ioctl };" >> "${SEPOLICY_DIR}/system_server.te"
  echo "  [NTSync] Added system_server rule"
else
  echo "  [NTSync] system_server.te already patched, skipping."
fi

# --- 4d. untrusted_app.te — allow apps to use ntsync (for Wine/Proton) ---
if ! grep -q "ntsync_device" "${SEPOLICY_DIR}/untrusted_app.te"; then
  echo "" >> "${SEPOLICY_DIR}/untrusted_app.te"
  echo "# NTSync - allow untrusted apps to use ntsync device" >> "${SEPOLICY_DIR}/untrusted_app.te"
  echo "allow { untrusted_app untrusted_app_25 untrusted_app_27 } ntsync_device:chr_file { getattr open read write ioctl };" >> "${SEPOLICY_DIR}/untrusted_app.te"
  echo "allowxperm { untrusted_app untrusted_app_25 untrusted_app_27 } ntsync_device:chr_file ioctl { 0x4e80-0x4e8d };" >> "${SEPOLICY_DIR}/untrusted_app.te"
  echo "  [NTSync] Added untrusted_app rules"
else
  echo "  [NTSync] untrusted_app.te already patched, skipping."
fi

echo ""
echo "  NTSync SELinux patching done!"
echo ""

# ─────────────────────────────────────────────
# STEP 5 — Build!
# ─────────────────────────────────────────────
echo "[5/5] Starting build..."

source build/envsetup.sh

# 'breakfast' sets up the build environment for your device
breakfast apollo

# 'mka bacon' is the standard way to build a flashable zip
mka bacon -j$(nproc --all)

echo ""
echo "=========================================="
echo "  BUILD DONE!"
echo "  Your zip is in: out/target/product/apollo/"
echo "=========================================="
