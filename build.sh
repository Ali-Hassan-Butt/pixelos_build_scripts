#!/bin/bash

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
ROM: XdroidCAF 12
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

# ── libncurses symlink (required for Android 12) ──────────────────────────────
sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6   /usr/lib/x86_64-linux-gnu/libtinfo.so.5

# ── Repo init ─────────────────────────────────────────────────────────────────
tg "📦 <b>[1/4]</b> Repo init..."
repo init --depth=1 --no-repo-verify --git-lfs \
    -u https://github.com/xdroid-CAF/xd_manifest \
    -b twelve \
    -g default,-mips,-darwin,-notdefault
tg "✅ <b>[1/4]</b> Repo init done"

# ── Sync ──────────────────────────────────────────────────────────────────────
tg "🔄 <b>[2/4]</b> Syncing sources..."
/opt/crave/resync.sh
tg "✅ <b>[2/4]</b> Sync complete"

# ── Clone device trees ────────────────────────────────────────────────────────
tg "📋 <b>[3/4]</b> Cloning device trees..."

# Device — xiaomi-sm8250-devs, lineage-19.1 (Android 12)
git clone https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_apollon \
    -b lineage-19.1 device/xiaomi/apollon

git clone https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_sm8250-common \
    -b lineage-19.1 device/xiaomi/sm8250-common

# Vendor blobs — apollon uses lineage-20 (no 19.1 exists upstream)
# Note: device.mk expects vendor/xiaomi/apollon — path MUST match
git clone https://github.com/xiaomi-sm8250-devs/proprietary_vendor_xiaomi_apollon \
    -b lineage-20 vendor/xiaomi/apollon

git clone https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common \
    -b lineage-19.1 vendor/xiaomi/sm8250-common

# Kernel — LineageOS stable, lineage-19.1
git clone https://github.com/LineageOS/android_kernel_xiaomi_sm8250 \
    -b lineage-19.1 kernel/xiaomi/sm8250

tg "✅ <b>[3/4]</b> Trees cloned"

# ── Create xdroid lunch target ────────────────────────────────────────────────
# Device tree has lineage_apollon.mk — we wrap it for xdroid
cat > device/xiaomi/apollon/xdroid_apollon.mk << 'MKEOF'
$(call inherit-product, device/xiaomi/apollon/lineage_apollon.mk)

PRODUCT_NAME := xdroid_apollon
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Mi 10T

XDROID_BOOT := 1080
MKEOF

echo "Created xdroid_apollon.mk"

# ── Build ─────────────────────────────────────────────────────────────────────
tg "🔨 <b>[4/4]</b> Build started — go touch some grass 🌿"

export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave
export TZ="Asia/Karachi"

source build/envsetup.sh
lunch xdroid_apollon-userdebug
mka bacon

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
ROM: XdroidCAF 12
Built by: basit @ crave"

    mv "$ZIP" ./
else
    tg "❌ <b>Build failed</b> — no zip found. Check Crave logs."
    exit 1
fi
