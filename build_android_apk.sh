#!/bin/bash
# ============================================
# RustDesk Android APK 编译脚本
# ============================================
# 用途：编译 RustDesk Android APK
# 前提：已执行 wsl2_android_setup.sh 配置环境
# 执行方式：chmod +x build_android_apk.sh && ./build_android_apk.sh
# ============================================

set -e  # 遇到错误立即退出

echo "========================================="
echo "RustDesk Android APK 编译"
echo "========================================="

# ============================================
# 配置参数
# ============================================
PROJECT_DIR=~/rustdesk
ARCH="arm64-v8a"  # 可选: arm64-v8a, armeabi-v7a
TARGET="aarch64-linux-android"  # 可选: aarch64-linux-android, armv7-linux-androideabi
OUTPUT_DIR=/mnt/d  # 输出到 Windows D 盘

# ============================================
# 检查是否在 Windows 文件系统中运行
# ============================================
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" == /mnt/* ]]; then
    echo "========================================="
    echo "❌ 错误: 不建议在 Windows 文件系统中编译！"
    echo "========================================="
    echo "原因："
    echo "  1. Windows 文件系统的 CRLF 行尾会导致脚本执行失败"
    echo "  2. 编译速度比 WSL 文件系统慢很多"
    echo ""
    echo "建议："
    echo "  1. 将代码克隆到 WSL 文件系统："
    echo "     cd ~"
    echo "     git clone https://github.com/senken123/rustdesk.git"
    echo "     cd rustdesk"
    echo ""
    echo "  2. 然后执行编译："
    echo "     ./build_android_apk.sh"
    echo ""
    echo "  3. 编译完成后，APK 会自动复制到 Windows D 盘"
    echo ""
    echo "如果你确定要在 Windows 文件系统中编译，请按 Ctrl+C 取消，"
    echo "然后手动转换脚本行尾格式："
    echo "  find . -name '*.sh' -exec dos2unix {} \\;"
    echo "========================================="
    echo ""
    read -p "按回车继续，或按 Ctrl+C 取消..." 
fi

# ============================================
# 检查环境变量
# ============================================
echo ""
echo "检查环境变量..."
if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "❌ 错误: ANDROID_NDK_HOME 未设置"
    echo "请先执行: source ~/.bashrc"
    exit 1
fi

echo "✅ 环境变量检查通过"
echo "  ANDROID_NDK_HOME: $ANDROID_NDK_HOME"
echo "  VCPKG_ROOT: $VCPKG_ROOT"

# ============================================
# 步骤 1: 检查项目代码
# ============================================
echo ""
echo "步骤 1/7: 检查项目代码..."
if [ ! -d "$PROJECT_DIR" ]; then
    echo "克隆 RustDesk 代码到 WSL 文件系统..."
    cd ~
    git clone https://github.com/senken123/rustdesk.git
    cd rustdesk
    git submodule update --init --recursive
else
    echo "✅ 项目已存在: $PROJECT_DIR"
    cd $PROJECT_DIR
fi

# ============================================
# 步骤 2: 编译 vcpkg 依赖（首次很慢）
# ============================================
echo ""
echo "步骤 2/7: 编译 vcpkg 依赖..."
echo "⚠️  首次编译需要 60-90 分钟，请耐心等待..."

# 转换脚本行尾格式
dos2unix ./flutter/build_android_deps.sh 2>/dev/null || true
dos2unix ./flutter/ndk_arm64.sh 2>/dev/null || true
dos2unix ./flutter/ndk_arm.sh 2>/dev/null || true

chmod +x ./flutter/build_android_deps.sh
chmod +x ./flutter/ndk_arm64.sh
chmod +x ./flutter/ndk_arm.sh

./flutter/build_android_deps.sh $ARCH

# ============================================
# 步骤 3: 生成 Flutter 桥接代码
# ============================================
echo ""
echo "步骤 3/7: 生成 Flutter 桥接代码..."

# 修改 pubspec.yaml（如果需要）
cd flutter
if grep -q "extended_text: 13.0.0" pubspec.yaml; then
    sed -i 's/extended_text: 13.0.0/extended_text: 14.0.0/g' pubspec.yaml
fi
flutter pub get
cd ..

# 生成桥接代码
~/.cargo/bin/flutter_rust_bridge_codegen \
  --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart \
  --c-output ./flutter/macos/Runner/bridge_generated.h

cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h

# ============================================
# 步骤 4: 编译 Rust 库
# ============================================
echo ""
echo "步骤 4/7: 编译 Rust 库..."
echo "⚠️  预计需要 10-15 分钟..."

if [ "$ARCH" == "arm64-v8a" ]; then
    ./flutter/ndk_arm64.sh
elif [ "$ARCH" == "armeabi-v7a" ]; then
    ./flutter/ndk_arm.sh
fi

# ============================================
# 步骤 5: 复制库文件（重要：重命名）
# ============================================
echo ""
echo "步骤 5/7: 复制库文件..."

rm -rf ./flutter/android/app/src/main/jniLibs/$ARCH
mkdir -p ./flutter/android/app/src/main/jniLibs/$ARCH

# 关键：复制时重命名 liblibrustdesk.so -> librustdesk.so
echo "  复制 Rust 库（重命名）..."
cp ./target/$TARGET/release/liblibrustdesk.so ./flutter/android/app/src/main/jniLibs/$ARCH/librustdesk.so

# 复制 C++ 共享库
echo "  复制 C++ 共享库..."
if [ "$ARCH" == "arm64-v8a" ]; then
    cp $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so \
       ./flutter/android/app/src/main/jniLibs/$ARCH/
elif [ "$ARCH" == "armeabi-v7a" ]; then
    cp $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so \
       ./flutter/android/app/src/main/jniLibs/$ARCH/
fi

# 验证库文件
echo "  验证库文件..."
ls -lh ./flutter/android/app/src/main/jniLibs/$ARCH/

# ============================================
# 步骤 6: 编译 APK
# ============================================
echo ""
echo "步骤 6/7: 编译 APK..."
echo "⚠️  预计需要 5-10 分钟..."

cd flutter

# 使用 debug 签名（避免签名配置问题）
sed -i 's/signingConfig signingConfigs.release/signingConfig signingConfigs.debug/g' android/app/build.gradle

# 清理并编译
flutter clean

if [ "$ARCH" == "arm64-v8a" ]; then
    flutter build apk --release --target-platform android-arm64 --split-per-abi
    APK_FILE="app-arm64-v8a-release.apk"
elif [ "$ARCH" == "armeabi-v7a" ]; then
    flutter build apk --release --target-platform android-arm --split-per-abi
    APK_FILE="app-armeabi-v7a-release.apk"
fi

# ============================================
# 步骤 7: 复制 APK 到 Windows
# ============================================
echo ""
echo "步骤 7/7: 复制 APK 到 Windows..."

APK_PATH="build/app/outputs/flutter-apk/$APK_FILE"
OUTPUT_FILE="$OUTPUT_DIR/rustdesk-$(date +%Y%m%d-%H%M%S)-$ARCH.apk"

if [ -f "$APK_PATH" ]; then
    cp "$APK_PATH" "$OUTPUT_FILE"
    
    # 验证 APK 中的库文件
    echo ""
    echo "验证 APK 中的库文件:"
    unzip -l "$APK_PATH" | grep "\.so$"
    
    echo ""
    echo "========================================="
    echo "✅ 编译成功！"
    echo "========================================="
    echo "APK 文件:"
    echo "  WSL 路径: $APK_PATH"
    echo "  Windows 路径: $OUTPUT_FILE"
    echo ""
    echo "APK 大小: $(du -h "$APK_PATH" | cut -f1)"
    echo ""
    echo "安装命令:"
    echo "  adb install \"$OUTPUT_FILE\""
    echo "========================================="
else
    echo ""
    echo "========================================="
    echo "❌ 编译失败！"
    echo "========================================="
    echo "APK 文件不存在: $APK_PATH"
    exit 1
fi

# ============================================
# 显示编译信息
# ============================================
echo ""
echo "编译信息:"
echo "  架构: $ARCH"
echo "  目标: $TARGET"
echo "  Rust 版本: $(rustc --version)"
echo "  Flutter 版本: $(flutter --version | head -n 1)"
echo "========================================="
