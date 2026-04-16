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

# Helper: send a Telegram message
tg() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d parse_mode="HTML" \
        -d text="$1" > /dev/null
}

# Helper: upload zip to Pixeldrain, return download URL
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

# ── Start ────────────────────────────────────────────────────────────────────
tg "🚀 <b>Build Started</b>
Device: apollo (Xiaomi Mi 10T)
ROM: PixelOS 16
Time: $(date '+%Y-%m-%d %H:%M UTC')"

echo ""
echo "=========================================="
echo "  PixelOS 16 — apollo — Crave Build"
echo "=========================================="

# STEP 1 — Repo init
tg "📦 <b>[1/4]</b> Running repo init..."
rm -rf .repo/local_manifests
repo init -u https://github.com/PixelOS-AOSP/android_manifest.git -b sixteen-qpr2 --git-lfs --depth=1
tg "✅ <b>[1/4]</b> Repo init done"

# STEP 2 — Local manifests
tg "📋 <b>[2/4]</b> Cloning local manifests..."
git clone -b main https://github.com/Ali-Hassan-Butt/local_manifests_apollo .repo/local_manifests
tg "✅ <b>[2/4]</b> Local manifests cloned"

# STEP 3 — Sync
tg "🔄 <b>[3/4]</b> Syncing sources (this takes a while)..."
/opt/crave/resync.sh
tg "✅ <b>[3/4]</b> Sync complete"

# STEP 4 — Build
tg "🔨 <b>[4/4]</b> Build started — go touch some grass 🌿"

export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave

source build/envsetup.sh
lunch pixelos_apollo-bp4a-user
make installclean
m bacon

# ── Upload & notify ──────────────────────────────────────────────────────────
ZIP=$(find out/target/product/apollo/ -maxdepth 1 -name "*.zip" | head -1)

if [ -n "$ZIP" ]; then
    tg "✅ <b>Build Successful!</b>
📁 File: $(basename $ZIP)
⬆️ Uploading to Pixeldrain..."

    LINK=$(upload_pixeldrain "$ZIP")

    tg "📥 <b>Download Ready!</b>
🔗 $LINK

Device: apollo (Mi 10T)
ROM: PixelOS 16
Built by: basit @ crave"
else
    tg "❌ <b>Build failed</b> — no zip found in output. Check Crave logs."
    exit 1
fi

echo ""
echo "=========================================="
echo "  BUILD DONE! Check Telegram for link."
echo "=========================================="
