#!/bin/bash
# ============================================
# RustDesk Android 编译环境配置脚本 (WSL2)
# ============================================
# 用途：在 WSL2 Ubuntu 24.04 中配置 Android 编译环境
# 执行方式：chmod +x wsl2_android_setup.sh && ./wsl2_android_setup.sh
# ============================================

set -e  # 遇到错误立即退出

echo "========================================="
echo "RustDesk Android 编译环境配置"
echo "========================================="

# ============================================
# 1. 更换国内镜像源（阿里云）
# ============================================
echo ""
echo "步骤 1/8: 更换 APT 镜像源..."
sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
sudo tee /etc/apt/sources.list > /dev/null <<'EOF'
deb http://mirrors.aliyun.com/ubuntu/ noble main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-security main restricted universe multiverse
EOF

sudo apt update

# ============================================
# 2. 安装系统依赖
# ============================================
echo ""
echo "步骤 2/8: 安装系统依赖..."
sudo apt install -y \
    clang cmake curl gcc-multilib git g++ g++-multilib \
    libasound2-dev libc6-dev libclang-dev libunwind-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    libgtk-3-dev libpam0g-dev libpulse-dev libva-dev \
    libxcb-randr0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    libxdo-dev libxfixes-dev llvm-dev nasm ninja-build \
    pkg-config tree wget unzip zip openjdk-17-jdk libssl-dev \
    dos2unix

# ============================================
# 3. 安装 Rust 1.75
# ============================================
echo ""
echo "步骤 3/8: 安装 Rust 1.75..."
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
fi

rustup install 1.75
rustup default 1.75

# 添加 Android 编译目标
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi

# 安装 cargo-ndk
cargo install cargo-ndk --version 3.1.2 --locked

# ============================================
# 4. 安装 Flutter 3.24.5
# ============================================
echo ""
echo "步骤 4/8: 安装 Flutter 3.24.5..."
cd ~
if [ ! -d "flutter" ]; then
    wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz
    tar xf flutter_linux_3.24.5-stable.tar.xz
    rm flutter_linux_3.24.5-stable.tar.xz
fi

# 添加到 PATH
if ! grep -q 'export PATH="$HOME/flutter/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
fi
export PATH="$HOME/flutter/bin:$PATH"

flutter config --enable-android

# ============================================
# 5. 配置 Java 17
# ============================================
echo ""
echo "步骤 5/8: 配置 Java 17..."
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

if ! grep -q 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' ~/.bashrc; then
    echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> ~/.bashrc
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
fi

# ============================================
# 6. 安装 Android SDK 和 NDK
# ============================================
echo ""
echo "步骤 6/8: 安装 Android SDK 和 NDK..."
mkdir -p ~/android-sdk/cmdline-tools
cd ~/android-sdk/cmdline-tools

if [ ! -d "latest" ]; then
    wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
    unzip commandlinetools-linux-11076708_latest.zip
    mv cmdline-tools latest
    rm commandlinetools-linux-11076708_latest.zip
fi

# 添加环境变量
export ANDROID_HOME=$HOME/android-sdk
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
export PATH=$ANDROID_HOME/platform-tools:$PATH

if ! grep -q 'export ANDROID_HOME=$HOME/android-sdk' ~/.bashrc; then
    echo 'export ANDROID_HOME=$HOME/android-sdk' >> ~/.bashrc
    echo 'export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH' >> ~/.bashrc
    echo 'export PATH=$ANDROID_HOME/platform-tools:$PATH' >> ~/.bashrc
fi

# 接受许可协议并安装组件
yes | sdkmanager --licenses || true
sdkmanager "platform-tools" "platforms;android-33" "build-tools;34.0.0"
sdkmanager "ndk;27.2.12479018"

# 设置 NDK 环境变量
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018
export ANDROID_NDK_ROOT=$ANDROID_NDK_HOME

if ! grep -q 'export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018' ~/.bashrc; then
    echo 'export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018' >> ~/.bashrc
    echo 'export ANDROID_NDK_ROOT=$ANDROID_NDK_HOME' >> ~/.bashrc
fi

# ============================================
# 7. 安装 vcpkg
# ============================================
echo ""
echo "步骤 7/8: 安装 vcpkg..."
cd ~
if [ ! -d "vcpkg" ]; then
    git clone https://github.com/microsoft/vcpkg
    cd vcpkg
    git checkout 120deac3062162151622ca4860575a33844ba10b
    ./bootstrap-vcpkg.sh
else
    cd vcpkg
fi

export VCPKG_ROOT=$HOME/vcpkg
if ! grep -q 'export VCPKG_ROOT=$HOME/vcpkg' ~/.bashrc; then
    echo 'export VCPKG_ROOT=$HOME/vcpkg' >> ~/.bashrc
fi

# ============================================
# 8. 安装 Flutter Rust Bridge 工具
# ============================================
echo ""
echo "步骤 8/8: 安装 Flutter Rust Bridge 工具..."
cargo install cargo-expand --version 1.0.95 --locked
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked

# ============================================
# 完成
# ============================================
echo ""
echo "========================================="
echo "✅ 环境配置完成！"
echo "========================================="
echo "项目路径: ~/rustdesk"
echo "Rust 版本: $(rustc --version)"
echo "Flutter 版本: $(flutter --version | head -n 1)"
echo "Java 版本: $(java -version 2>&1 | head -n 1)"
echo "Android SDK: $ANDROID_HOME"
echo "Android NDK: $ANDROID_NDK_HOME"
echo "vcpkg: $VCPKG_ROOT"
echo "========================================="
echo ""
echo "请执行以下命令使环境变量生效："
echo "source ~/.bashrc"
echo ""
echo "然后可以使用 build_android_apk.sh 编译 APK"
echo "========================================="
