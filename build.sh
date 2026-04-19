#!/bin/bash
set -e


BOT_TOKEN="6341925197:AAGwB5iiwpPBYs38deeswPQ78Obo1Lit9Is"
CHAT_ID="1417234061"
# ─────────────────────────────────────────────────────────────────────────────

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
echo "-- Cleaning up..."
rm -rf \
    .repo/local_manifests \
    device/xiaomi/apollon \
    device/xiaomi/apollo \
    device/xiaomi/sm8250-common \
    device/qcom/sepolicy \
    device/qcom/sepolicy-legacy-um \
    device/qcom/sepolicy_vndr/legacy-um \
    kernel/xiaomi/sm8250 \
    out/target/product/apollon \
    out/target/product/apollo \
    vendor/xiaomi/apollo \
    vendor/xiaomi/sm8250-common
 
# ── libncurses symlink (required for Android 12) ──────────────────────────────
sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6   /usr/lib/x86_64-linux-gnu/libtinfo.so.5
echo "lib6 >> lib5 symlinks done"
 
# ── Repo init ─────────────────────────────────────────────────────────────────
tg "📦 <b>[1/4]</b> Repo init..."
repo init --depth=1 --no-repo-verify --git-lfs \
    -u https://github.com/xdroid-CAF/xd_manifest \
    -b twelve \
    -g default,-mips,-darwin,-notdefault
echo "Repo init success"
tg "✅ <b>[1/4]</b> Repo init done"
 
# ── Local manifests ───────────────────────────────────────────────────────────
tg "📋 <b>[2/4]</b> Cloning local manifests..."
git clone --depth=1 \
    -b main \
    https://github.com/Ali-Hassan-Butt/local_manifests_apollo \
    .repo/local_manifests
echo "Local manifest clone success"
tg "✅ <b>[2/4]</b> Local manifests cloned"
 
# ── Sync ──────────────────────────────────────────────────────────────────────
tg "🔄 <b>[3/4]</b> Syncing sources..."
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags --prune
echo "Sync success"
tg "✅ <b>[3/4]</b> Sync complete"
 
# ── Create xdroid lunch target ────────────────────────────────────────────────
if [ ! -f "device/xiaomi/apollon/xdroid_apollon.mk" ]; then
    cat > device/xiaomi/apollon/xdroid_apollon.mk << 'MKEOF'
$(call inherit-product, device/xiaomi/apollon/lineage_apollon.mk)
PRODUCT_NAME := xdroid_apollon
XDROID_BOOT := 1080
MKEOF
    echo "Created xdroid_apollon.mk"
fi
 
# ── Build ─────────────────────────────────────────────────────────────────────
tg "🔨 <b>[4/4]</b> Build started — go touch some grass 🌿"
 
export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave
export TZ="Asia/Karachi"
 
source build/envsetup.sh
lunch xdroid_apollon-userdebug
make installclean
make xd -j$(nproc --all)
 
# ── Upload & notify ───────────────────────────────────────────────────────────
ZIP=$(find out/target/product/apollon/ out/target/product/apollo/ \
    -maxdepth 1 -name "*.zip" 2>/dev/null | head -1)
 
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
