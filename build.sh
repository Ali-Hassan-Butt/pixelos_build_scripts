#!/bin/bash
set -o pipefail

# ================= TIMEZONE =================
sudo rm -f /etc/localtime
sudo ln -s /usr/share/zoneinfo/Asia/Karachi /etc/localtime
echo "🕒 Time: $(date)"

# ================= JQ =================
if ! command -v jq &> /dev/null; then
    mkdir -p ~/bin
    curl -L -o ~/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux64
    chmod +x ~/bin/jq
    export PATH=$HOME/bin:$PATH
fi

# ================= CONFIGS =================
DEVICE="apollon"
OUT_DIR="out/target/product/${DEVICE}"
START_TIME=$(date +%s)
BUILD_LOG="build.log"
ERROR_LOG="out/error.log"

# ================= PIXELDRAIN =================
upload_pixeldrain() {
    local FILE="$1"
    if [ -f "$FILE" ]; then
        RESPONSE=$(curl -s -T "$FILE" -u : "https://pixeldrain.com/api/file/$(basename $FILE)")
        FILE_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$FILE_ID" ]; then
            echo "https://pixeldrain.com/u/$FILE_ID"
        else
            echo "Upload failed: $RESPONSE"
        fi
    fi
}

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

# ================= ON FAIL =================
on_fail() {
    echo "❌ BUILD FAILED"
    echo "Uploading logs..."

    [ -f "$ERROR_LOG" ] && echo "Error log: $(gofile_upload $ERROR_LOG)"
    [ -f "$BUILD_LOG" ] && echo "Build log: $(gofile_upload $BUILD_LOG)"

    exit 1
}

echo "============================================"
echo "  Corvus-AOSP | apollon (Mi 10T) | A13"
echo "  $(date '+%Y-%m-%d %H:%M PKT')"
echo "============================================"

# ================= CLEANUP =================
echo ">>>> [STEP] Cleanup"
rm -rf .repo/local_manifests

rm -rf \
    device/xiaomi/apollon \
    device/xiaomi/sm8250-common \
    kernel/xiaomi/sm8250 \
    vendor/xiaomi/apollon \
    vendor/xiaomi/sm8250-common \
    out/target/product/apollon

# ================= LIBNCURSES =================
sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5
sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6   /usr/lib/x86_64-linux-gnu/libtinfo.so.5

# ================= REPO INIT =================
echo ">>>> [STEP] Repo Init"
repo init --depth=1 --no-repo-verify --git-lfs \
    -u https://github.com/Corvus-AOSP/android_manifest.git \
    -b 13 \
    -g default,-mips,-darwin,-notdefault

# ================= SYNC =================
echo ">>>> [STEP] Sync"
if [ -f /opt/crave/resync.sh ]; then
    /opt/crave/resync.sh
else
    repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all)
fi

# ================= DEVICE TREES =================
echo ">>>> [STEP] Clone Trees"

# Fixed: lineage-20 (not lineage-20.0)
git clone https://github.com/LineageOS/android_device_xiaomi_apollon \
    -b lineage-20 --depth=1 device/xiaomi/apollon

git clone https://github.com/LineageOS/android_device_xiaomi_sm8250-common \
    -b lineage-20 --depth=1 device/xiaomi/sm8250-common

git clone https://github.com/xiaomi-sm8250-devs/proprietary_vendor_xiaomi_apollon \
    -b lineage-20 --depth=1 vendor/xiaomi/apollon

git clone https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common \
    -b lineage-20 --depth=1 vendor/xiaomi/sm8250-common

git clone https://github.com/LineageOS/android_kernel_xiaomi_sm8250 \
    -b lineage-20 --depth=1 kernel/xiaomi/sm8250

echo "Trees cloned successfully"

# ================= FIXES =================
echo ">>>> [STEP] Apply Fixes"

# Display: keep ONLY sm8250, remove all conflicting stacks
rm -rf hardware/qcom-caf/sdm660/display
rm -rf hardware/qcom-caf/sdm845/display
rm -rf hardware/qcom-caf/msm8953/display
rm -rf hardware/qcom-caf/msm8996/display
rm -rf hardware/qcom-caf/msm8998/display
rm -rf hardware/qcom-caf/sm8150/display
rm -rf hardware/qcom-caf/sm8350/display
rm -rf hardware/qcom-caf/sm8450/display
rm -rf hardware/qcom-caf/sm8550/display

# Audio adsprpcd: keep sm8150, remove duplicates
rm -rf hardware/qcom-caf/sm8250/audio/adsprpcd
rm -rf hardware/qcom-caf/sm8350/audio/adsprpcd
rm -rf hardware/qcom-caf/sdm660/audio/adsprpcd
rm -rf hardware/qcom-caf/sdm845/audio/adsprpcd
rm -rf hardware/qcom-caf/msm8953/audio/adsprpcd
rm -rf hardware/qcom-caf/sm8450/audio/primary-hal/adsprpcd
rm -rf hardware/qcom-caf/sm8550/audio/primary-hal/adsprpcd

# Audio PAL/AGM: sm8550 conflicts with sm8450, keep sm8450
rm -rf hardware/qcom-caf/sm8550/audio/pal
rm -rf hardware/qcom-caf/sm8550/audio/agm

# Trebuchet conflicts with Launcher3
rm -rf packages/apps/Trebuchet

# Create Corvus lunch target (mkdir -p ensures dir exists even if clone was slow)
mkdir -p device/xiaomi/apollon
cat > device/xiaomi/apollon/corvus_apollon.mk << 'MKEOF'
$(call inherit-product, device/xiaomi/apollon/lineage_apollon.mk)

PRODUCT_NAME := corvus_apollon
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Xiaomi Mi 10T

CORVUS_BUILD_TYPE := UNOFFICIAL
MKEOF

echo "Created corvus_apollon.mk"

# ================= BUILD =================
echo ">>>> [STEP] Build"

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

if grep -q -E "ninja failed|failed to build some targets" "$BUILD_LOG"; then
    on_fail
fi

# ================= SUCCESS =================
END_TIME=$(date +%s)
DUR=$((END_TIME - START_TIME))

echo "============================================"
echo "✅ BUILD SUCCESSFUL"
echo "Time: $((DUR/3600))h $(((DUR%3600)/60))min"
echo "============================================"

ROM_ZIP=$(ls -t ${OUT_DIR}/*.zip 2>/dev/null | head -n 1)

if [ -n "$ROM_ZIP" ]; then
    BUILD_ID=$(basename "$ROM_ZIP" .zip)
    ROM_SIZE=$(du -h "$ROM_ZIP" | awk '{print $1}')
    echo "ZIP: $BUILD_ID ($ROM_SIZE)"

    # ================= UPLOAD =================
    echo ">>>> [STEP] Upload"

    GO_URL=$(gofile_upload "$ROM_ZIP")
    PD_URL=$(upload_pixeldrain "$ROM_ZIP")

    echo "GoFile:     $GO_URL"
    echo "PixelDrain: $PD_URL"

    # Individual images
    for IMG in boot.img vendor_boot.img init_boot.img recovery.img; do
        FILE="${OUT_DIR}/${IMG}"
        if [ -f "$FILE" ]; then
            URL=$(gofile_upload "$FILE")
            echo "$IMG: $URL"
        fi
    done
fi
