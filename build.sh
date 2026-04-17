#!/bin/bash
set -e

# =============================================================================
#  PixelOS 16 — Xiaomi Mi 10T (apollo) — Crave Build Script
#  With Telegram notifications + Pixeldrain upload
# =============================================================================

# ── Telegram config ──────────────────────────────────────────────────────────
# 1. Talk to @BotFather on Telegram → /newbot → copy your token
# 2. Send a message to your bot, then visit:
#    https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
#    to find your chat_id
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
    echo "Uploading to Pixeldrain..."
    RESPONSE=$(curl -s -T "$FILE" -u : "https://pixeldrain.com/api/file/${FILENAME}")
    FILE_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$FILE_ID" ]; then
        echo "https://pixeldrain.com/u/${FILE_ID}"
    else
        echo "Upload failed: $RESPONSE"
    fi
}
 
tg "🚀 <b>Build Started</b>
Device: apollo (Xiaomi Mi 10T)
ROM: XdroidCAF 12
Time: $(date '+%Y-%m-%d %H:%M UTC')"
 
# STEP 1 — Repo init
tg "📦 <b>[1/4]</b> Repo init..."
rm -rf .repo/local_manifests
repo init -u https://github.com/xdroid-CAF/xd_manifest -b twelve --git-lfs --depth=1
tg "✅ <b>[1/4]</b> Repo init done"
 
# STEP 2 — Local manifests
tg "📋 <b>[2/4]</b> Cloning local manifests..."
git clone -b main https://github.com/Ali-Hassan-Butt/local_manifests_apollo .repo/local_manifests
tg "✅ <b>[2/4]</b> Local manifests cloned"
 
# STEP 3 — Sync
tg "🔄 <b>[3/4]</b> Syncing sources..."
/opt/crave/resync.sh
tg "✅ <b>[3/4]</b> Sync complete"
 
# STEP 4 — Create xdroid lunch target
tg "⚙️ <b>[4/4]</b> Setting up device makefiles..."

if [ ! -f "device/xiaomi/apollo/xdroid_apollo.mk" ]; then
    # Copy the lineage makefile
    cp device/xiaomi/apollo/lineage_apollo.mk device/xiaomi/apollo/xdroid_apollo.mk
    
    # Swap lineage branding and vendor paths for xdroid
    sed -i 's/lineage_apollo/xdroid_apollo/g' device/xiaomi/apollo/xdroid_apollo.mk
    sed -i 's/vendor\/lineage/vendor\/xdroid/g' device/xiaomi/apollo/xdroid_apollo.mk
    
    # Append Xdroid specific variables
    echo "XDROID_BOOT := 1080" >> device/xiaomi/apollo/xdroid_apollo.mk
    echo "Created xdroid_apollo.mk"
fi

# STEP 5 — Build
tg "🔨 <b>[4/4]</b> Build started — go touch some grass 🌿"
 
export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave
export TZ="Asia/Karachi"
 
source build/envsetup.sh
lunch xdroid_apollo-userdebug
make installclean
make xd -j$(nproc --all)
 
# Upload & notify
ZIP=$(find out/target/product/apollo/ -maxdepth 1 -name "*.zip" | head -1)
 
if [ -n "$ZIP" ]; then
    tg "✅ <b>Build Successful!</b>
📁 $(basename $ZIP)
⬆️ Uploading to Pixeldrain..."
 
    LINK=$(upload_pixeldrain "$ZIP")
 
    tg "📥 <b>Download Ready!</b>
🔗 $LINK
 
Device: apollo (Mi 10T)
ROM: XdroidCAF 12
Built by: basit @ crave"
else
    tg "❌ <b>Build failed</b> — no zip found. Check Crave logs."
    exit 1
fi
