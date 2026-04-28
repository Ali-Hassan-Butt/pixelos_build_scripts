#!/bin/bash
set -o pipefail

# ============================================================
#  Corvus-AOSP 13 — Xiaomi Mi 10T (apollon)
#  Hardened build script for Crave cloud builds
#  Set CLEAN_MODE=clobber to force full rebuild (default: installclean)
# ============================================================

DEVICE="apollon"
OUT_DIR="out/target/product/${DEVICE}"
START_TIME=$(date +%s)
BUILD_LOG="build.log"
ERROR_LOG="out/error.log"
CLEAN_MODE="${CLEAN_MODE:-installclean}"

# ============================================================
#  UTILITIES
# ============================================================

# ---------- jq ----------
if ! command -v jq &>/dev/null; then
    mkdir -p ~/bin
    curl -fsSL -o ~/bin/jq \
        https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux64
    chmod +x ~/bin/jq
    export PATH=$HOME/bin:$PATH
fi

# ---------- upload helpers ----------
gofile_upload() {
    local FILE="$1"
    [ -f "$FILE" ] || return
    local SERVERS
    mapfile -t SERVERS < <(
        curl -fsSL https://api.gofile.io/servers \
            | jq -r '.data.servers[].name' 2>/dev/null
    )
    for S in $(printf "%s\n" "${SERVERS[@]}" | shuf); do
        local RESP LINK
        RESP=$(curl -fsSL -F "file=@${FILE}" "https://${S}.gofile.io/uploadFile")
        LINK=$(echo "$RESP" | jq -r '.data.downloadPage // empty' 2>/dev/null)
        [ -n "$LINK" ] && echo "$LINK" && return
    done
    echo "(gofile upload failed)"
}

pixeldrain_upload() {
    local FILE="$1"
    [ -f "$FILE" ] || return
    local RESP ID
    RESP=$(curl -fsSL -T "$FILE" -u : \
        "https://pixeldrain.com/api/file/$(basename "$FILE")")
    ID=$(echo "$RESP" | jq -r '.id // empty' 2>/dev/null)
    [ -n "$ID" ] && echo "https://pixeldrain.com/u/$ID" \
                 || echo "(pixeldrain upload failed)"
}

# ---------- fatal exit ----------
on_fail() {
    local MSG="${1:-}"
    echo ""
    [ -n "$MSG" ] && echo "❌ FATAL: $MSG"
    echo "❌ BUILD FAILED — uploading logs..."
    [ -f "$ERROR_LOG" ] && echo "  error.log → $(gofile_upload "$ERROR_LOG")"
    [ -f "$BUILD_LOG" ] && echo "  build.log → $(gofile_upload "$BUILD_LOG")"
    exit 1
}

# ---------- safe git clone with retry ----------
# Usage: safe_clone <url> <branch> <dest> [fatal: true|false]
safe_clone() {
    local URL="$1" BRANCH="$2" DEST="$3" FATAL="${4:-true}"
    local MAX=3 i
    for i in $(seq 1 $MAX); do
        echo "  Cloning $(basename "$DEST") @ $BRANCH (attempt $i/$MAX)"
        rm -rf "$DEST"
        if git clone "$URL" -b "$BRANCH" --depth=1 "$DEST" 2>&1; then
            echo "  ✅ $(basename "$DEST") done"
            return 0
        fi
        sleep 3
    done
    if [ "$FATAL" = "true" ]; then
        on_fail "Failed to clone $URL after $MAX attempts"
    else
        echo "  ⚠ $(basename "$DEST") clone failed (non-fatal)"
        return 1
    fi
}

# ---------- safe clone with multiple branch fallbacks ----------
# Usage: safe_clone_fallback <url> <dest> <branch1> [branch2 ...]
safe_clone_fallback() {
    local URL="$1" DEST="$2"; shift 2
    local BRANCH
    for BRANCH in "$@"; do
        rm -rf "$DEST"
        if git clone "$URL" -b "$BRANCH" --depth=1 "$DEST" 2>/dev/null; then
            echo "  ✅ $(basename "$DEST") cloned from branch: $BRANCH"
            return 0
        fi
    done
    echo "  ⚠ $(basename "$DEST") — all branches failed (non-fatal)"
    return 1
}

# ============================================================
echo "============================================"
echo "  Corvus-AOSP 13 | apollon | $(date '+%d %b %Y %H:%M PKT')"
echo "  CLEAN_MODE: $CLEAN_MODE"
echo "============================================"

# ============================================================
#  [0] SYSTEM SETUP
# ============================================================
sudo rm -f /etc/localtime
sudo ln -sf /usr/share/zoneinfo/Asia/Karachi /etc/localtime
sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 \
            /usr/lib/x86_64-linux-gnu/libncurses.so.5
sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6 \
            /usr/lib/x86_64-linux-gnu/libtinfo.so.5

# ============================================================
#  [1] CLEANUP
# ============================================================
echo ">>>> [1] Cleanup"

rm -rf \
    .repo/local_manifests \
    device/xiaomi/apollon \
    device/xiaomi/sm8250-common \
    kernel/xiaomi/sm8250 \
    vendor/corvus \
    vendor/xiaomi/apollon \
    vendor/xiaomi/sm8250-common \
    hardware/xiaomi \
    hardware/qcom-caf/bootctrl \
    out/target/product/apollon

# Force-remove GCC prebuilts that Crave caches with dirty state.
# repo forall doesn't reliably clean them, causing resync to abort with
# "Cannot remove project: uncommitted changes are present".
rm -rf \
    prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 \
    prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9

echo "Cleanup done."

# ============================================================
#  [2] REPO INIT
# ============================================================
echo ">>>> [2] Repo Init"
repo init \
    --depth=1 \
    --no-repo-verify \
    --git-lfs \
    -u https://github.com/Corvus-AOSP/android_manifest.git \
    -b 13 \
    -g default,-mips,-darwin,-notdefault \
    || on_fail "repo init failed"

# ============================================================
#  [2b] LOCAL MANIFEST — vendor/corvus
# ============================================================
# vendor/corvus is not in Crave's AOSP base cache. Declaring it
# here causes resync.sh to pull it as a normal manifest project,
# which is far more reliable than a manual git clone after sync.
echo ">>>> [2b] Injecting local manifest"
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/corvus_extras.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="corvus-gh" fetch="https://github.com/Corvus-AOSP/" />
  <project name="vendor_corvus"
           path="vendor/corvus"
           remote="corvus-gh"
           revision="13"
           clone-depth="1" />
</manifest>
XMLEOF

# ============================================================
#  [3] SYNC — with retry on failure
# ============================================================
echo ">>>> [3] Sync"

do_sync() {
    if [ -f /opt/crave/resync.sh ]; then
        repo forall -c 'git reset --hard HEAD; git clean -fdx' 2>/dev/null || true
        /opt/crave/resync.sh
    else
        repo sync \
            -c \
            --force-sync \
            --no-tags \
            --no-clone-bundle \
            -j"$(nproc --all)"
    fi
}

SYNC_OK=false
for ATTEMPT in 1 2 3; do
    echo "  Sync attempt $ATTEMPT/3..."
    if do_sync; then
        SYNC_OK=true
        break
    fi
    echo "  ⚠ Sync attempt $ATTEMPT failed — resetting dirty state..."
    repo forall -c 'git reset --hard HEAD; git clean -fdx' 2>/dev/null || true
    rm -rf \
        prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 \
        prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9
    sleep 5
done

[ "$SYNC_OK" = true ] || on_fail "Sync failed after 3 attempts"

# Verify vendor/corvus came through — dump what's there if not,
# so we never have to guess the file structure again.
if [ ! -f vendor/corvus/config/common_full_phone.mk ]; then
    echo "❌ vendor/corvus/config/common_full_phone.mk missing after sync"
    echo "   .mk files present in vendor/corvus:"
    find vendor/corvus -maxdepth 4 -name "*.mk" 2>/dev/null | head -30 \
        || echo "   (vendor/corvus does not exist at all)"
    on_fail "vendor/corvus sync incomplete"
fi
echo "✅ vendor/corvus confirmed"

# ============================================================
#  [4] CLONE DEVICE TREES
# ============================================================
echo ">>>> [4] Clone Trees"

safe_clone \
    https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_apollon \
    lineage-20 device/xiaomi/apollon

safe_clone \
    https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_sm8250-common \
    lineage-20 device/xiaomi/sm8250-common

safe_clone \
    https://github.com/xiaomi-sm8250-devs/proprietary_vendor_xiaomi_apollon \
    lineage-20 vendor/xiaomi/apollon

safe_clone \
    https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common \
    lineage-20 vendor/xiaomi/sm8250-common

safe_clone \
    https://github.com/LineageOS/android_kernel_xiaomi_sm8250 \
    lineage-20 kernel/xiaomi/sm8250

safe_clone \
    https://github.com/LineageOS/android_hardware_xiaomi \
    lineage-20 hardware/xiaomi

# bootctrl — non-fatal, try multiple branches in order
safe_clone_fallback \
    https://github.com/LineageOS/android_hardware_qcom_bootctrl \
    hardware/qcom-caf/bootctrl \
    lineage-20 lineage-20.0 lineage-21 master

# Final sanity check — all fatal clones must exist
for DIR in \
    device/xiaomi/apollon \
    device/xiaomi/sm8250-common \
    vendor/xiaomi/apollon \
    vendor/xiaomi/sm8250-common \
    kernel/xiaomi/sm8250 \
    hardware/xiaomi; do
    [ -d "$DIR" ] || on_fail "Required directory missing after clone: $DIR"
done

echo "All trees verified."

# ============================================================
#  [5] CORVUS PRODUCT SETUP
# ============================================================
echo ">>>> [5] Setup Corvus product"

cat > device/xiaomi/apollon/corvus_apollon.mk << 'MKEOF'
$(call inherit-product, device/xiaomi/apollon/device.mk)
$(call inherit-product, vendor/corvus/config/common_full_phone.mk)

PRODUCT_NAME         := corvus_apollon
PRODUCT_DEVICE       := apollon
PRODUCT_BRAND        := Xiaomi
PRODUCT_MODEL        := Xiaomi Mi 10T
PRODUCT_MANUFACTURER := Xiaomi

PRODUCT_SOONG_NAMESPACES += hardware/xiaomi

CORVUS_BUILD_TYPE := UNOFFICIAL
MKEOF

# Only add bootctrl namespace if the directory actually exists —
# Soong will error if a declared namespace path doesn't exist on disk.
if [ -d hardware/qcom-caf/bootctrl ]; then
    echo 'PRODUCT_SOONG_NAMESPACES += hardware/qcom-caf/bootctrl' \
        >> device/xiaomi/apollon/corvus_apollon.mk
    echo "  ✅ bootctrl namespace added"
fi

cat > device/xiaomi/apollon/AndroidProducts.mk << 'MKEOF'
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/corvus_apollon.mk

COMMON_LUNCH_CHOICES := \
    corvus_apollon-userdebug
MKEOF

echo "Product files written."

# ============================================================
#  [6] REMOVE CONFLICTING CAF MODULES
# ============================================================
echo ">>>> [6] Remove conflicting CAF modules"

for CHIP in sdm660 sdm845 msm8953 msm8996 msm8998 sm8150 sm8350 sm8450 sm8550; do
    rm -rf hardware/qcom-caf/${CHIP}/display
done
for CHIP in sm8250 sm8350 sdm660 sdm845 msm8953; do
    rm -rf hardware/qcom-caf/${CHIP}/audio/adsprpcd
done
rm -rf \
    hardware/qcom-caf/sm8450/audio/primary-hal/adsprpcd \
    hardware/qcom-caf/sm8550/audio/primary-hal/adsprpcd \
    hardware/qcom-caf/sm8550/audio/pal \
    hardware/qcom-caf/sm8550/audio/agm \
    packages/apps/Trebuchet

echo "Conflicts resolved."

# ============================================================
#  [7] BUILD
# ============================================================
echo ">>>> [7] Build"

export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave
export TZ="Asia/Karachi"

source build/envsetup.sh || on_fail "build/envsetup.sh failed to source"

lunch corvus_apollon-userdebug
[ $? -eq 0 ] || on_fail "lunch corvus_apollon-userdebug failed"

m "$CLEAN_MODE" || on_fail "$CLEAN_MODE failed"

m -j"$(nproc --all)" corvus 2>&1 | tee "$BUILD_LOG"
[ "${PIPESTATUS[0]}" -eq 0 ] || on_fail "Compilation failed — check build.log"

# ============================================================
#  [8] SUCCESS + UPLOAD
# ============================================================
END_TIME=$(date +%s)
DUR=$((END_TIME - START_TIME))

echo ""
echo "============================================"
echo "✅ BUILD SUCCESSFUL"
echo "   Time: $((DUR/3600))h $(((DUR%3600)/60))m $((DUR%60))s"
echo "============================================"

ROM_ZIP=$(ls -t "${OUT_DIR}"/*.zip 2>/dev/null | head -n 1)
if [ -n "$ROM_ZIP" ]; then
    echo ">>>> [9] Uploading $(basename "$ROM_ZIP")"
    echo "  GoFile:     $(gofile_upload "$ROM_ZIP")"
    echo "  PixelDrain: $(pixeldrain_upload "$ROM_ZIP")"
else
    echo "⚠ No zip found in $OUT_DIR"
fi
