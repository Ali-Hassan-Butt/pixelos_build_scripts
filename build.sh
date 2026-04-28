#!/bin/bash
set -o pipefail

# ============================================================
#  Corvus-AOSP 13 — Xiaomi Mi 10T (apollon)
#  Written by the book — verified sources only
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

# ================= GOFILE =================
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

# ================= PIXELDRAIN =================
pixeldrain_upload() {
    local FILE="$1"
    if [ -f "$FILE" ]; then
        RESPONSE=$(curl -s -T "$FILE" -u : "https://pixeldrain.com/api/file/$(basename $FILE)")
        FILE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
        [ -n "$FILE_ID" ] && echo "https://pixeldrain.com/u/$FILE_ID" || echo ""
    fi
}

# ================= ON FAIL =================
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

# ================= TIMEZONE =================
sudo rm -f /etc/localtime
sudo ln -s /usr/share/zoneinfo/Asia/Karachi /etc/localtime

# ================= LIBNCURSES =================
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
    out/target/product/apollon

# ================= REPO INIT =================
# Branch 13 README uses GitLab SSH — use GitHub HTTPS equivalent
echo ">>>> [2] Repo Init"
repo init --depth=1 --no-repo-verify --git-lfs \
    -u https://github.com/Corvus-AOSP/android_manifest.git \
    -b 13 \
    -g default,-mips,-darwin,-notdefault

# ================= SYNC =================
echo ">>>> [3] Sync"
if [ -f /opt/crave/resync.sh ]; then
    /opt/crave/resync.sh
else
    repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all)
fi

# ================= DEVICE TREES =================
# Source: lineage.dependencies confirms only sm8250-common is needed
# Org: xiaomi-sm8250-devs (confirmed branch: lineage-20)
echo ">>>> [4] Clone Trees"

git clone https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_apollon \
    -b lineage-20 --depth=1 device/xiaomi/apollon

git clone https://github.com/xiaomi-sm8250-devs/android_device_xiaomi_sm8250-common \
    -b lineage-20 --depth=1 device/xiaomi/sm8250-common

# Vendor blobs
git clone https://github.com/xiaomi-sm8250-devs/proprietary_vendor_xiaomi_apollon \
    -b lineage-20 --depth=1 vendor/xiaomi/apollon

git clone https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common \
    -b lineage-20 --depth=1 vendor/xiaomi/sm8250-common

# Kernel
git clone https://github.com/LineageOS/android_kernel_xiaomi_sm8250 \
    -b lineage-20 --depth=1 kernel/xiaomi/sm8250

# Required by sm8250-common (confirmed in lineage.dependencies)
git clone https://github.com/LineageOS/android_hardware_xiaomi \
    -b lineage-20 --depth=1 hardware/xiaomi

echo "Trees cloned."

# ================= CORVUS PRODUCT SETUP =================
echo ">>>> [5] Setup Corvus product"

# Create corvus_apollon.mk inheriting from the lineage tree
cat > device/xiaomi/apollon/corvus_apollon.mk << 'MKEOF'
$(call inherit-product, device/xiaomi/apollon/lineage_apollon.mk)

PRODUCT_NAME := corvus_apollon
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Xiaomi Mi 10T

CORVUS_BUILD_TYPE := UNOFFICIAL
MKEOF

# Rewrite AndroidProducts.mk properly to register corvus_apollon.mk
# The original only has lineage_apollon.mk — we add corvus alongside it
cat > device/xiaomi/apollon/AndroidProducts.mk << 'MKEOF'
#
# Copyright (C) 2021 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/lineage_apollon.mk \
    $(LOCAL_DIR)/corvus_apollon.mk

COMMON_LUNCH_CHOICES := \
    lineage_apollon-user \
    lineage_apollon-userdebug \
    lineage_apollon-eng \
    corvus_apollon-user \
    corvus_apollon-userdebug \
    corvus_apollon-eng
MKEOF

echo "Product files written."

# ================= CONFLICT FIXES =================
# Corvus manifest pulls ALL CAF chipset display/audio stacks — they conflict
# SM8250 only needs its own stack
echo ">>>> [6] Remove conflicting CAF modules"

# Display — keep sm8250 only
for CHIP in sdm660 sdm845 msm8953 msm8996 msm8998 sm8150 sm8350 sm8450 sm8550; do
    rm -rf hardware/qcom-caf/${CHIP}/display
done

# Audio adsprpcd — keep sm8150 baseline, remove all duplicates
for CHIP in sm8250 sm8350 sdm660 sdm845 msm8953; do
    rm -rf hardware/qcom-caf/${CHIP}/audio/adsprpcd
done
rm -rf hardware/qcom-caf/sm8450/audio/primary-hal/adsprpcd
rm -rf hardware/qcom-caf/sm8550/audio/primary-hal/adsprpcd

# Audio PAL/AGM — sm8550 conflicts with sm8450
rm -rf hardware/qcom-caf/sm8550/audio/pal
rm -rf hardware/qcom-caf/sm8550/audio/agm

# Launcher conflict
rm -rf packages/apps/Trebuchet

echo "Conflicts resolved."

# ================= BUILD =================
echo ">>>> [7] Build"

export BUILD_USERNAME=basit
export BUILD_HOSTNAME=crave
export TZ="Asia/Karachi"

source build/envsetup.sh
lunch corvus_apollon-userdebug
make installclean

make corvus -j$(nproc --all) 2>&1 | tee "$BUILD_LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    on_fail
fi

if grep -qE "ninja failed|failed to build some targets" "$BUILD_LOG"; then
    on_fail
fi

# ================= SUCCESS =================
END_TIME=$(date +%s)
DUR=$((END_TIME - START_TIME))

echo ""
echo "============================================"
echo "✅ BUILD SUCCESSFUL"
echo "   Time: $((DUR/3600))h $(((DUR%3600)/60))min $((DUR%60))sec"
echo "============================================"

ROM_ZIP=$(ls -t ${OUT_DIR}/*.zip 2>/dev/null | head -n 1)

if [ -n "$ROM_ZIP" ]; then
    ROM_SIZE=$(du -h "$ROM_ZIP" | awk '{print $1}')
    echo "ZIP: $(basename $ROM_ZIP) (${ROM_SIZE})"
    echo ""
    echo ">>>> [8] Upload"

    GO_URL=$(gofile_upload "$ROM_ZIP")
    PD_URL=$(pixeldrain_upload "$ROM_ZIP")

    echo "  GoFile:     ${GO_URL}"
    echo "  PixelDrain: ${PD_URL}"

    for IMG in boot.img vendor_boot.img init_boot.img recovery.img; do
        FILE="${OUT_DIR}/${IMG}"
        if [ -f "$FILE" ]; then
            URL=$(gofile_upload "$FILE")
            echo "  ${IMG}: ${URL}"
        fi
    done
fi
