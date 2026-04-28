#!/bin/bash
set -o pipefail

# ============================================================
#  Corvus-AOSP 13 — Xiaomi Mi 10T (apollon)
#  Optimized for Corvus 13 & SM8250
# ============================================================

DEVICE="apollon"
OUT_DIR="out/target/product/${DEVICE}"
START_TIME=$(date +%s)
BUILD_LOG="build.log"
ERROR_LOG="out/error.log"

# ================= JQ =================
if ! command -v jq &> /dev/null; then
    mkdir -p ~/bin
    curl -L -o ~/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux64
    chmod +x ~/bin/jq
    export PATH=$HOME/bin:$PATH
fi

# ================= UPLOAD FUNCTIONS =================
gofile_upload() {
    local FILE="$1"
    mapfile -t SERVERS < <(curl -s https://api.gofile.io/servers | jq -r '.data.servers[].name')
    for S in $(printf "%s\n" "${SERVERS[@]}" | shuf); do
        RESP=$(curl -s -F "file=@${FILE}" "https://${S}.gofile.io/uploadFile")
        LINK=$(echo "$RESP" | jq -r '.data.downloadPage // empty')
        if [ -n "$LINK" ]; then
            echo "$LINK"
            return
        fi
    done
    echo ""
}

pixeldrain_upload() {
    local FILE="$1"
    if [ -f "$FILE" ]; then
        RESPONSE=$(curl -s -T "$FILE" -u : "https://pixeldrain.com/api/file/$(basename $FILE)")
        FILE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
        [ -n "$FILE_ID" ] && echo "https://pixeldrain.com/u/$FILE_ID" || echo ""
    fi
}

on_fail() {
    echo ""
    echo "❌ BUILD FAILED — uploading logs..."
    [ -f "$ERROR_LOG" ] && echo "  error.log → $(gofile_upload $ERROR_LOG)"
    [ -f "$BUILD_LOG" ] && echo "  build.log → $(gofile_upload $BUILD_LOG)"
    exit 1
}

echo "============================================"
echo "  Corvus-AOSP 13 | apollon | $(date '+%d %b %Y %H:%M PKT')"
echo "============================================"

# ================= SETUP =================
sudo rm -f /etc/localtime
sudo ln -s /usr/share/zoneinfo/Asia/Karachi /etc/localtime
sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6   /usr/lib/x86_64-linux-gnu/libtinfo.so.5

# ================= CLEANUP =================
echo ">>>> [1] Cleanup"
rm -rf .repo/local_manifests \
    device/xiaomi/apollon \
    device/xiaomi/sm8250-common \
    kernel/xiaomi/sm8250 \
    vendor/xiaomi/apollon \
    vendor/xiaomi/sm8250-common \
    hardware/xiaomi \
    hardware/qcom-caf/bootctrl \
    out/target/product/apollon

# ================= REPO INIT =================
echo ">>>> [2] Repo Init"
repo init --depth=1 --no-repo-verify --git-lfs \
    -u https://github.com/Corvus-AOSP/android_manifest.git \
    -b 13 \
    -g default,-mips,-darwin,-notdefault

# ================= SYNC =================
echo ">>>> [3] Sync"
if [ -f /opt/crave/resync.sh ]; then
    repo forall -c 'git reset --hard ; git clean -fdx'
    /opt/crave/resync.sh
else
    repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all)
fi

# ================= DEVICE TREES =================
echo ">>>> [4] Clone Trees"

git clone https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_apollon \
    -b lineage-20 --depth=1 device/xiaomi/apollon
git clone https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_sm8250-common \
    -b lineage-20 --depth=1 device/xiaomi/sm8250-common
git clone https://github.com/xiaomi-sm8250-devs/proprietary_vendor_xiaomi_apollon \
    -b lineage-20 --depth=1 vendor/xiaomi/apollon
git clone https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common \
    -b lineage-20 --depth=1 vendor/xiaomi/sm8250-common
git clone https://github.com/LineageOS/android_kernel_xiaomi_sm8250 \
    -b lineage-20 --depth=1 kernel/xiaomi/sm8250

# Dependencies
git clone https://github.com/LineageOS/android_hardware_xiaomi \
    -b lineage-20 --depth=1 hardware/xiaomi

# FIX 1: lineage-20 branch doesn't exist in this repo; use lineage-20.0
git clone https://github.com/LineageOS/android_hardware_qcom_bootctrl \
    -b lineage-20.0 --depth=1 hardware/qcom-caf/bootctrl \
    || echo "⚠ WARNING: bootctrl clone failed — Corvus manifest may already provide it, continuing..."

echo "Trees cloned."

# ================= CORVUS PRODUCT SETUP =================
echo ">>>> [5] Setup Corvus product"

cat > device/xiaomi/apollon/corvus_apollon.mk << 'MKEOF'
$(call inherit-product, device/xiaomi/apollon/device.mk)
$(call inherit-product, vendor/corvus/config/corvus.mk)

PRODUCT_NAME := corvus_apollon
PRODUCT_DEVICE := apollon
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Xiaomi Mi 10T
PRODUCT_MANUFACTURER := Xiaomi

PRODUCT_SOONG_NAMESPACES += \
    hardware/qcom-caf/bootctrl \
    hardware/xiaomi

CORVUS_BUILD_TYPE := UNOFFICIAL
MKEOF

cat > device/xiaomi/apollon/AndroidProducts.mk << 'MKEOF'
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/corvus_apollon.mk

COMMON_LUNCH_CHOICES := \
    corvus_apollon-userdebug
MKEOF

# FIX 2: Stub common.mk if Corvus vendor tree references it but didn't ship it.
# corvus.mk calls inherit-product on common.mk; create it if missing so lunch doesn't abort.
if [ -d vendor/corvus/config ] && [ ! -f vendor/corvus/config/common.mk ]; then
    echo "⚠ WARNING: vendor/corvus/config/common.mk missing — creating stub"
    touch vendor/corvus/config/common.mk
fi

echo "Product files written and patched."

# ================= CONFLICT FIXES =================
echo ">>>> [6] Remove conflicting CAF modules"
for CHIP in sdm660 sdm845 msm8953 msm8996 msm8998 sm8150 sm8350 sm8450 sm8550; do
    rm -rf hardware/qcom-caf/${CHIP}/display
done
for CHIP in sm8250 sm8350 sdm660 sdm845 msm8953; do
    rm -rf hardware/qcom-caf/${CHIP}/audio/adsprpcd
done
rm -rf hardware/qcom-caf/sm8450/audio/primary-hal/adsprpcd
rm -rf hardware/qcom-caf/sm8550/audio/primary-hal/adsprpcd
rm -rf hardware/qcom-caf/sm8550/audio/pal
rm -rf hardware/qcom-caf/sm8550/audio/agm
rm -rf packages/apps/Trebuchet
echo "Conflicts resolved."

# ================= BUILD =================
echo ">>>> [7] Build"
export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave
export TZ="Asia/Karachi"

source build/envsetup.sh

# FIX 3: lunch failure isn't always caught by ||; use explicit exit code check
lunch corvus_apollon-userdebug
if [ $? -ne 0 ]; then
    echo "❌ lunch failed"
    on_fail
fi

m installclean

# FIX 4: mka is a LineageOS extension not present in Corvus's AOSP build/make.
# Use plain `m` with an explicit -j flag instead.
m -j$(nproc --all) corvus 2>&1 | tee "$BUILD_LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    on_fail
fi

# ================= SUCCESS =================
END_TIME=$(date +%s)
DUR=$((END_TIME - START_TIME))

echo "============================================"
echo "✅ BUILD SUCCESSFUL"
echo "    Time: $((DUR/3600))h $(((DUR%3600)/60))min $((DUR%60))sec"
echo "============================================"

ROM_ZIP=$(ls -t ${OUT_DIR}/*.zip 2>/dev/null | head -n 1)
if [ -n "$ROM_ZIP" ]; then
    echo ">>>> [8] Uploading $(basename $ROM_ZIP)"
    echo "  GoFile:     $(gofile_upload "$ROM_ZIP")"
    echo "  PixelDrain: $(pixeldrain_upload "$ROM_ZIP")"
fi
