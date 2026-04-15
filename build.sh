#!/bin/bash
# =============================================================================
#  PixelOS 16 (sixteen-qpr2) — Xiaomi Mi 10T (apollo)
#  Crave.io Build Script — NO NTSync, LineageOS kernel
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

set -e  # Stop the whole script if any command fails

echo ""
echo "=========================================="
echo "  PixelOS 16 — apollo — Crave Build"
echo "=========================================="
echo ""

# ─────────────────────────────────────────────
# STEP 1 — Initialize PixelOS 16 source
# ─────────────────────────────────────────────
echo "[1/4] Initializing PixelOS 16 manifest..."

repo init \
  -u https://github.com/PixelOS-AOSP/android_manifest.git \
  -b sixteen-qpr2 \
  --git-lfs \
  --depth=1

# ─────────────────────────────────────────────
# STEP 2 — Set up local manifests (device trees)
# ─────────────────────────────────────────────
echo "[2/4] Setting up local manifests..."

rm -rf .repo/local_manifests

# TODO: Replace YOUR_USERNAME with your actual GitHub username
git clone \
  -b main \
  https://github.com/Ali-Hassan-Butt/local_manifests_apollo \
  .repo/local_manifests

# ─────────────────────────────────────────────
# STEP 3 — Sync all sources (Crave-optimized)
# ─────────────────────────────────────────────
echo "[3/4] Syncing sources via Crave resync..."
/opt/crave/resync.sh

# ─────────────────────────────────────────────
# STEP 4 — Build!
# ─────────────────────────────────────────────
echo "[4/4] Starting build..."

source build/envsetup.sh
breakfast apollo
mka bacon -j$(nproc --all)

echo ""
echo "=========================================="
echo "  BUILD DONE!"
echo "  Your zip is in: out/target/product/apollo/"
echo "=========================================="
