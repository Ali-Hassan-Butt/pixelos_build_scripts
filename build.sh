#!/bin/bash

# ============================================================
#  Corvus-AOSP (Android 13) — Xiaomi Mi 10T (apollon)
#  Crave build script
# ============================================================

BOT_TOKEN="6341925197:AAGwB5iiwpPBYs38deeswPQ78Obo1Lit9Is"
CHAT_ID="1417234061"

tg() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d parse_mode="HTML" \
        -d text="$1" > /dev/null
}

upload_pixeldrain() {
    local FILE="$1"
    local FILENAME=$(basename "$FILE")
    RESPONSE=$(curl -s -T "$FILE" -u : "https://pixeldrain.com/api/file/${FILENAME}")
    FILE_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$FILE_ID" ]; then
        echo "https://pixeldrain.com/u/${FILE_ID}"
    else
        echo "Upload failed: $RESPONSE"
    fi
}

tg "🚀 <b>Build Started</b>
Device: apollon (Xiaomi Mi 10T)
ROM: Corvus-AOSP 13 (Android 13)
Time: $(date '+%Y-%m-%d %H:%M UTC')"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf .repo/local_manifests

rm -rf \
    device/xiaomi/apollon \
    device/xiaomi/sm8250-common \
    kernel/xiaomi/sm8250 \
    vendor/xiaomi/apollon \
    vendor/xiaomi/sm8250-common \
    out/target/product/apollon

# ── Repo init ─────────────────────────────────────────────────────────────────
# Branch 13 README uses GitLab SSH — use GitHub HTTPS instead (same repo)
tg "📦 <b>[1/4]</b> Repo init..."
repo init --depth=1 --no-repo-verify --git-lfs \
    -u https://github.com/Corvus-AOSP/android_manifest.git \
    -b 13 \
    -g default,-mips,-darwin,-notdefault
tg "✅ <b>[1/4]</b> Repo init done"

# ── Sync ──────────────────────────────────────────────────────────────────────
tg "🔄 <b>[2/4]</b> Syncing..."
/opt/crave/resync.sh

# Fix 1: Remove Trebuchet (conflicts with Launcher3)
rm -rf packages/apps/Trebuchet

# Fix 2: Remove conflicting CAF display HALs
rm -rf hardware/qcom-caf/sm8350/display
rm -rf hardware/qcom-caf/sm8450/display
rm -rf hardware/qcom-caf/sm8550/display
tg "✅ <b>[2/4]</b> Sync done"

# ── Clone device trees ────────────────────────────────────────────────────────
tg "📋 <b>[3/4]</b> Cloning trees..."

# Android 13 = lineage-20
# Using LineageOS official apollon tree (same one confirmed for LOS 20 builds)
git clone https://github.com/LineageOS/android_device_xiaomi_apollon \
    -b lineage-20.0 --depth=1 device/xiaomi/apollon

git clone https://github.com/LineageOS/android_device_xiaomi_sm8250-common \
    -b lineage-20.0 --depth=1 device/xiaomi/sm8250-common

# Vendor blobs — xiaomi-sm8250-devs (only org with apollon blobs on lineage-20)
git clone https://github.com/xiaomi-sm8250-devs/proprietary_vendor_xiaomi_apollon \
    -b lineage-20 --depth=1 vendor/xiaomi/apollon

git clone https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common \
    -b lineage-20.0 --depth=1 vendor/xiaomi/sm8250-common

# Kernel
git clone https://github.com/LineageOS/android_kernel_xiaomi_sm8250 \
    -b lineage-20.0 --depth=1 kernel/xiaomi/sm8250

tg "✅ <b>[3/4]</b> Trees cloned"

# ── Create Corvus lunch target ────────────────────────────────────────────────
cat > device/xiaomi/apollon/corvus_apollon.mk << 'MKEOF'
$(call inherit-product, device/xiaomi/apollon/lineage_apollon.mk)

PRODUCT_NAME := corvus_apollon
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Xiaomi Mi 10T

# Corvus flags
CORVUS_BUILD_TYPE := UNOFFICIAL
MKEOF

echo "Created corvus_apollon.mk"

# ── Build ─────────────────────────────────────────────────────────────────────
tg "🔨 <b>[4/4]</b> Build started — go touch some grass 🌿"

export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave
export TZ="Asia/Karachi"

source build/envsetup.sh
lunch corvus_apollon-userdebug
make corvus

# ── Upload & notify ───────────────────────────────────────────────────────────
ZIP=$(find out/target/product/apollon/ -maxdepth 1 -name "*.zip" 2>/dev/null | head -1)

if [ -n "$ZIP" ]; then
    tg "✅ <b>Build Successful!</b>
📁 $(basename $ZIP)
⬆️ Uploading to Pixeldrain..."

    LINK=$(upload_pixeldrain "$ZIP")

    tg "📥 <b>Download Ready!</b>
🔗 ${LINK}

Device: apollon (Mi 10T)
ROM: Corvus-AOSP 13 (Android 13)
Built by: basit @ crave"

    mv "$ZIP" ./
else
    tg "❌ <b>Build failed</b> — no zip found. Check Crave logs."
    exit 1
fi
