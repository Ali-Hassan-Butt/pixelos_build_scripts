#!/bin/bash

# 1. Update and install dependencies
sudo apt update
sudo apt install patchelf -y

# 2. Clean up old SM8250/apollo trees
echo "🧹 Cleaning up old directories..."
rm -rf .repo/local_manifests/
rm -rf device/xiaomi/apollo
rm -rf device/xiaomi/sm8250-common
rm -rf vendor/xiaomi/apollo
rm -rf vendor/xiaomi/sm8250-common
rm -rf kernel/xiaomi/sm8250
rm -rf hardware/xiaomi
rm -rf hardware/qcom-caf/sm8250

# 3. Initialize CorvusOS 13 manifest
echo "📦 Initializing CorvusOS 13 manifest..."
repo init -u https://github.com/Corvus-ROM/android_manifest.git -b 13.0 --depth=1 --git-lfs

# 4. Generate local_manifests for apollo
echo "📝 Writing apollo local_manifest.xml..."
mkdir -p .repo/local_manifests

cat << 'EOF' > .repo/local_manifests/apollo.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project path="device/xiaomi/apollo" name="your-username/android_device_xiaomi_apollo" remote="github" revision="corvus-13" />
    <project path="device/xiaomi/sm8250-common" name="your-username/android_device_xiaomi_sm8250-common" remote="github" revision="corvus-13" />

    <project path="vendor/xiaomi/apollo" name="your-username/android_vendor_xiaomi_apollo" remote="github" revision="corvus-13" />
    <project path="vendor/xiaomi/sm8250-common" name="your-username/android_vendor_xiaomi_sm8250-common" remote="github" revision="corvus-13" />

    <project path="kernel/xiaomi/sm8250" name="your-username/android_kernel_xiaomi_sm8250_e404_clo" remote="github" revision="main" />

    <project path="hardware/xiaomi" name="LineageOS/android_hardware_xiaomi" remote="github" revision="lineage-20" />
    
    </manifest>
EOF

# 5. Sync sources using Crave
echo "🔄 Syncing sources via Crave..."
/opt/crave/resync.sh

# 6. Set up build environment
echo "🛠️ Setting up environment..."
source build/envsetup.sh

# 7. Apply ADB/Debugging props to the apollo makefile
FILE="device/xiaomi/apollo/apollo.mk"

if [ -f "$FILE" ]; then
    grep -q "ro.adb.secure=0" "$FILE" || cat >> "$FILE" <<'EOF'

# Auto-added ADB debug props
PRODUCT_SYSTEM_PROPERTIES += \
    ro.adb.secure=0 \
    ro.secure=0 \
    ro.debuggable=1 \
    persist.sys.usb.config=mtp,adb
EOF
    echo "✅ Injected ADB debug props into $FILE"
fi

# 8. Set build environment variables
export BUILD_USERNAME=basit
export TARGET_ENABLE_BLUR=true 
export WITH_ADB_INSECURE=true
export SELINUX_IGNORE_NEVERALLOWS=true

# 9. Lunch and Build
echo "🚀 Lunching apollo..."
lunch corvus_apollo-userdebug

echo "🏗️ Starting CorvusOS build..."
mka bacon 2>&1 | tee build1.log && curl -F "file=@build1.log" https://temp.sh/upload
