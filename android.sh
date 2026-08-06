#!/bin/bash
set -euo pipefail

##############################################################################
# FFmpeg Android 交叉编译脚本
# 目标平台：Android API 24, arm64-v8a
# 编译环境：Linux x86_64 (GitHub Actions)
# 输出：共享库 (.so)
##############################################################################


##############################################################################
# 目标 Android 配置信息
##############################################################################
# 目标 Android API 级别
ANDROID_API_LEVEL="24"
# 需编译的架构列表（仅 arm64-v8a）
ARCH_LIST=("armv8a")


##############################################################################
# FFmpeg 编译模块配置
##############################################################################
# 启用的 FFmpeg 模块/功能（使用 --disable-everything 后显式启用所需组件）
ENABLED_CONFIG="\
  --enable-gpl \
  --enable-version3 \
  --enable-jni \
  --enable-mediacodec \
  --enable-encoder=h264_mediacodec \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swscale \
  --enable-swresample \
  --enable-avfilter \
  --enable-libass \
  --enable-libdav1d \
  --enable-libfreetype \
  --enable-libmp3lame \
  --enable-shared \
  --enable-pic \
  --enable-protocol=file \
  --enable-muxer=mp4 \
  --enable-muxer=mp3 \
  --enable-muxer=matroska \
  --enable-muxer=wav \
  --enable-muxer=adts \
  --enable-muxer=ipod \
  --enable-demuxer=mov \
  --enable-demuxer=mp3 \
  --enable-demuxer=matroska \
  --enable-demuxer=wav \
  --enable-demuxer=aac \
  --enable-demuxer=flac \
  --enable-demuxer=ogg \
  --enable-demuxer=image2 \
  --enable-demuxer=image2pipe \
  --enable-demuxer=png_pipe \
  --enable-demuxer=mjpeg \
  --enable-decoder=aac \
  --enable-decoder=mp3 \
  --enable-decoder=flac \
  --enable-decoder=opus \
  --enable-decoder=vorbis \
  --enable-decoder=pcm_s16le \
  --enable-decoder=pcm_s24le \
  --enable-decoder=pcm_f32le \
  --enable-decoder=h264 \
  --enable-decoder=hevc \
  --enable-decoder=av1 \
  --enable-decoder=libdav1d \
  --enable-decoder=mpeg4 \
  --enable-decoder=vp9 \
  --enable-decoder=png \
  --enable-decoder=mjpeg \
  --enable-encoder=aac \
  --enable-encoder=libmp3lame \
  --enable-encoder=pcm_s16le \
  --enable-libx264 \
  --enable-encoder=libx264 \
  --enable-filter=setpts \
  --enable-filter=atempo \
  --enable-filter=aresample \
  --enable-filter=volume \
  --enable-filter=afade \
  --enable-filter=amix \
  --enable-filter=aformat \
  --enable-filter=anull \
  --enable-filter=subtitles \
  --enable-filter=ass \
  --enable-filter=overlay \
  --enable-filter=scale \
  --enable-filter=pad \
  --enable-filter=rotate \
  --enable-filter=crop \
  --enable-filter=color \
  --enable-filter=nullsink \
  --enable-parser=aac \
  --enable-parser=h264 \
  --enable-parser=hevc \
  --enable-parser=mpeg4video \
  --enable-parser=vp9 \
  --enable-parser=mpegaudio \
  --enable-parser=png \
  --enable-parser=mjpeg \
  --enable-bsf=aac_adtstoasc \
  --enable-bsf=h264_mp4toannexb \
  --enable-bsf=hevc_mp4toannexb \
  --enable-bsf=extract_extradata \
  --enable-bsf=h264_metadata \
  --enable-bsf=hevc_metadata"

# 禁用的 FFmpeg 模块/功能（不在此处重复 --disable-everything，configure_ffmpeg 已显式传入）
DISABLED_CONFIG="\
  --disable-small \
  --disable-static \
  --disable-debug \
  --disable-symver \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-doc \
  --disable-v4l2-m2m \
  --disable-cuda-llvm \
  --disable-indevs \
  --disable-avdevice \
  --disable-network \
  --disable-libxml2"


##############################################################################
# 编译工具链路径配置（请勿修改）
##############################################################################
# Android NDK 系统根路径
SYSROOT="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
# LLVM 工具链组件路径
LLVM_AR="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
LLVM_NM="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
LLVM_RANLIB="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ranlib"
LLVM_STRIP="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
LLVM_STRINGS="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strings"

# 导出汇编器 flags（Position-Independent Code）
export ASFLAGS="-fPIC"


##############################################################################
# 通用辅助函数：生成 Meson 交叉编译配置文件
# 参数说明：
# $1: 输出文件路径
# $2: C 编译器路径
# $3: C++ 编译器路径
# $4: 目标架构（cpu_family）
# $5: 目标 CPU
# $6: 额外 c_args（可选）
# $7: 额外 c_link_args（可选）
##############################################################################
generate_meson_cross_file() {
    local OUTPUT_FILE=$1
    local CC_PATH=$2
    local CXX_PATH=$3
    local CPU_FAMILY=$4
    local CPU=$5
    local EXTRA_C_ARGS=${6:-}
    local EXTRA_C_LINK_ARGS=${7:-}

    local C_ARGS="'-fpic'"
    if [ -n "$EXTRA_C_ARGS" ]; then
        C_ARGS="'-fpic', $EXTRA_C_ARGS"
    fi

    local C_LINK_ARGS=""
    if [ -n "$EXTRA_C_LINK_ARGS" ]; then
        C_LINK_ARGS="c_link_args = [$EXTRA_C_LINK_ARGS]"
    fi

    cat > "$OUTPUT_FILE" <<EOF
[binaries]
c = '$CC_PATH'
cpp = '$CXX_PATH'
ar = '$LLVM_AR'
strip = '$LLVM_STRIP'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = [$C_ARGS]
cpp_args = ['-fpic']
${C_LINK_ARGS}

[host_machine]
system = 'android'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'
EOF
}


##############################################################################
# 编译 libdav1d（AV1 视频解码库）
# 参数说明：
# $1: 目标架构（TARGET_ARCH）
# $2: 目标 CPU（TARGET_CPU）
# $3: 安装路径（PREFIX）
# $4: 交叉编译前缀（CROSS_PREFIX）
# $5: 额外 C 编译器 flags（EXTRA_CFLAGS）
# $6: 额外 C++ 编译器 flags（EXTRA_CXXFLAGS）
# $7: 额外配置参数（EXTRA_CONFIG）
##############################################################################
buildLibdav1d() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libdav1d for $TARGET_ARCH ..."

    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    if [ ! -d "dav1d" ]; then
        echo "Cloning libdav1d..."
        git clone https://code.videolan.org/videolan/dav1d.git
    else
        echo "Updating libdav1d..."
        cd dav1d || exit 1
        git pull
        cd ..
    fi

    cd dav1d || exit 1

    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    generate_meson_cross_file "$CROSS_FILE" "$CLANG" "$CLANGXX" "$TARGET_ARCH" "$TARGET_CPU" \
        "" "'-Wl,-z,max-page-size=16384'"

    echo "Meson cross file created: $CROSS_FILE"
    rm -rf build

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype release \
        --cross-file="$CROSS_FILE"
    if [ $? -ne 0 ]; then echo "Error: meson setup failed for libdav1d"; return 1; fi

    ninja -C build
    if [ $? -ne 0 ]; then echo "Error: ninja build failed for libdav1d"; return 1; fi

    ninja -C build install
    if [ $? -ne 0 ]; then echo "Error: ninja install failed for libdav1d"; return 1; fi

    cd "$ORIG_PWD" || exit 1
    echo ">>> libdav1d build completed."
}


##############################################################################
# 编译 FreeType（字体渲染库，FFmpeg drawtext 滤镜依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildFreetype() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building FreeType for $TARGET_ARCH ..."

    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    if [ ! -d "freetype2" ]; then
        echo "Cloning FreeType..."
        git clone https://git.savannah.gnu.org/git/freetype/freetype2.git
    else
        echo "Updating FreeType..."
        cd freetype2 || exit 1
        git pull
        cd ..
    fi

    cd freetype2 || exit 1

    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    generate_meson_cross_file "$CROSS_FILE" "$CLANG" "$CLANGXX" "$TARGET_ARCH" "$TARGET_CPU"

    echo "Meson cross file created for freetype: $CROSS_FILE"
    rm -rf build

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype release \
        --cross-file="$CROSS_FILE" \
        -Dzlib=disabled \
        -Dpng=disabled
    if [ $? -ne 0 ]; then echo "Error: meson setup failed for freetype"; return 1; fi

    ninja -C build
    if [ $? -ne 0 ]; then echo "Error: ninja build failed for freetype"; return 1; fi

    ninja -C build install
    if [ $? -ne 0 ]; then echo "Error: ninja install failed for freetype"; return 1; fi

    if [ ! -f "$PREFIX/lib/pkgconfig/freetype2.pc" ]; then
        echo "Error: freetype2.pc not found in $PREFIX/lib/pkgconfig"
        return 1
    fi

    cd "$ORIG_PWD" || exit 1
    echo ">>> FreeType build completed."
}


##############################################################################
# 编译 HarfBuzz（文字排版引擎，FFmpeg drawtext 滤镜依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildHarfBuzz() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building HarfBuzz for $TARGET_ARCH ..."

    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    if [ ! -d "harfbuzz" ]; then
        echo "Cloning HarfBuzz..."
        git clone https://github.com/harfbuzz/harfbuzz.git
    else
        echo "Updating HarfBuzz..."
        cd harfbuzz || exit 1
        git pull
        cd ..
    fi

    cd harfbuzz || exit 1

    # localeconv_l 在 Android Bionic API < 26 中不可用，替换为 localeconv()
    # SVG 路径解析始终使用 '.' 作为小数点，C locale 语义等效
    local SVG_UTILS="src/hb-vector-svg-utils.cc"
    if [ -f "$SVG_UTILS" ]; then
        echo "Patching $SVG_UTILS for Android API $ANDROID_API_LEVEL (localeconv_l unavailable in Bionic)..."
        sed -i 's/localeconv_l ([^)]*)/localeconv ()/g' "$SVG_UTILS"
    fi

    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    generate_meson_cross_file "$CROSS_FILE" "$CLANG" "$CLANGXX" "$TARGET_ARCH" "$TARGET_CPU"

    echo "Meson cross file created for harfbuzz: $CROSS_FILE"
    rm -rf build

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype release \
        --cross-file="$CROSS_FILE" \
        -Dicu=disabled \
        -Dgraphite2=disabled \
        -Dglib=disabled \
        -Dgobject=disabled \
        -Dcairo=disabled \
        -Dtests=disabled \
        -Dintrospection=disabled
    if [ $? -ne 0 ]; then echo "Error: meson setup failed for harfbuzz"; return 1; fi

    ninja -C build
    if [ $? -ne 0 ]; then echo "Error: ninja build failed for harfbuzz"; return 1; fi

    ninja -C build install
    if [ $? -ne 0 ]; then echo "Error: ninja install failed for harfbuzz"; return 1; fi

    if [ ! -f "$PREFIX/lib/pkgconfig/harfbuzz.pc" ]; then
        echo "Error: harfbuzz.pc not found in $PREFIX/lib/pkgconfig"
        return 1
    fi

    cd "$ORIG_PWD" || exit 1
    echo ">>> HarfBuzz build completed."
}


##############################################################################
# 编译 FriBidi（双向文本渲染库，libass 依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildFriBiDi() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building FriBiDi for $TARGET_ARCH ..."

    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    if [ ! -d "fribidi" ]; then
        echo "Cloning FriBidi..."
        git clone https://github.com/fribidi/fribidi.git
    else
        echo "Updating FriBidi..."
        cd fribidi || exit 1
        git pull
        cd ..
    fi

    cd fribidi || exit 1

    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    generate_meson_cross_file "$CROSS_FILE" "$CLANG" "$CLANGXX" "$TARGET_ARCH" "$TARGET_CPU" \
        "" "'-Wl,-z,max-page-size=16384'"

    echo "Meson cross file created for fribidi: $CROSS_FILE"

    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    rm -rf build

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype release \
        --cross-file="$CROSS_FILE" \
        -Ddocs=false \
        -Dtests=false \
        -Ddeprecated=false
    if [ $? -ne 0 ]; then echo "Error: meson setup failed for fribidi"; return 1; fi

    ninja -C build
    if [ $? -ne 0 ]; then echo "Error: ninja build failed for fribidi"; return 1; fi

    ninja -C build install
    if [ $? -ne 0 ]; then echo "Error: ninja install failed for fribidi"; return 1; fi

    if [ ! -f "$PREFIX/lib/pkgconfig/fribidi.pc" ]; then
        echo "Error: fribidi.pc not found in $PREFIX/lib/pkgconfig"
        return 1
    fi

    cd "$ORIG_PWD" || exit 1
    echo ">>> FriBiDi build completed."
}


##############################################################################
# 编译 LAME（libmp3lame，FFmpeg MP3 编码依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildLibmp3lame() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libmp3lame for $TARGET_ARCH ..."

    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    if [ ! -d "lame" ]; then
        echo "Cloning LAME (libmp3lame)..."
        git clone https://github.com/rbrito/lame.git lame
    else
        echo "Updating LAME (libmp3lame)..."
        cd lame || exit 1
        git pull
        cd ..
    fi

    cd lame || exit 1

    export CC="$CLANG"
    export AR="$LLVM_AR"
    export RANLIB="$LLVM_RANLIB"
    export STRIP="$LLVM_STRIP"
    export CFLAGS="-fPIC -DANDROID $EXTRA_CFLAGS --sysroot=$SYSROOT"
    export LDFLAGS="-fPIC -Wl,-z,max-page-size=16384 -L$PREFIX/lib"

    make distclean >/dev/null 2>&1 || true

    local HOST_TRIPLE
    case "$TARGET_ARCH" in
        aarch64) HOST_TRIPLE="aarch64-linux-android" ;;
        arm)     HOST_TRIPLE="arm-linux-androideabi" ;;
        x86_64)  HOST_TRIPLE="x86_64-linux-android" ;;
        x86)     HOST_TRIPLE="i686-linux-android" ;;
        *)       HOST_TRIPLE="${TARGET_ARCH}-linux-android" ;;
    esac

    ./configure \
        --host="$HOST_TRIPLE" \
        --disable-frontend \
        --enable-nasm=no \
        --enable-static \
        --disable-shared \
        --prefix="$PREFIX"
    if [ $? -ne 0 ]; then echo "Error: configure failed for libmp3lame"; return 1; fi

    make -j"$(nproc)"
    if [ $? -ne 0 ]; then echo "Error: make failed for libmp3lame"; return 1; fi

    make install -j"$(nproc)"
    if [ $? -ne 0 ]; then echo "Error: make install failed for libmp3lame"; return 1; fi

    mkdir -p "$PREFIX/lib/pkgconfig"
    cat > "$PREFIX/lib/pkgconfig/lame.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: lame
Description: LAME MP3 encoder library
Version: 3.100
Libs: -L\${libdir} -lmp3lame
Cflags: -I\${includedir}
EOF

    cd "$ORIG_PWD" || exit 1
    echo ">>> libmp3lame build completed."
}


##############################################################################
# 编译 libx264（H.264 视频编码库，GPLv2+）
# 参数说明：同 buildLibdav1d
##############################################################################
buildLibx264() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libx264 for $TARGET_ARCH ..."

    if [ ! -d "x264" ]; then
        echo "Cloning x264..."
        git clone https://code.videolan.org/videolan/x264.git
    else
        echo "Updating x264..."
        cd x264 || exit 1
        git pull
        cd ..
    fi

    cd x264 || exit 1

    export CC="$CLANG"
    export AR="$LLVM_AR"
    export RANLIB="$LLVM_RANLIB"
    export STRIP="$LLVM_STRIP"
    # NDK r23+ 移除了 binutils 的 strings 工具，x264 configure 依赖 $STRINGS 检测字节序
    export STRINGS="$LLVM_STRINGS"
    export CFLAGS="-fPIC -DANDROID $EXTRA_CFLAGS --sysroot=$SYSROOT"
    export LDFLAGS="-fPIC -Wl,-z,max-page-size=16384 -L$PREFIX/lib"

    local HOST_TRIPLE
    case "$TARGET_ARCH" in
        aarch64) HOST_TRIPLE="aarch64-linux-android" ;;
        arm)     HOST_TRIPLE="arm-linux-androideabi" ;;
        x86_64)  HOST_TRIPLE="x86_64-linux-android" ;;
        i686)    HOST_TRIPLE="i686-linux-android" ;;
        *)       HOST_TRIPLE="${TARGET_ARCH}-linux-android" ;;
    esac

    ./configure \
        --host="$HOST_TRIPLE" \
        --cross-prefix="$CROSS_PREFIX" \
        --sysroot="$SYSROOT" \
        --prefix="$PREFIX" \
        --enable-static \
        --disable-shared \
        --disable-cli \
        --disable-opencl \
        --enable-pic
    if [ $? -ne 0 ]; then echo "Error: configure failed for libx264"; return 1; fi

    make -j"$(nproc)"
    if [ $? -ne 0 ]; then echo "Error: make failed for libx264"; return 1; fi

    make install -j"$(nproc)"
    if [ $? -ne 0 ]; then echo "Error: make install failed for libx264"; return 1; fi

    cd "$ORIG_PWD" || exit 1
    echo ">>> libx264 build completed."
}


##############################################################################
# 编译 libass（字幕渲染库，FFmpeg subtitles 滤镜依赖）
# 参数说明：同 buildLibdav1d
##############################################################################
buildLibass() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"
    local ORIG_PWD
    ORIG_PWD="$(pwd)"

    echo ">>> Building libass for $TARGET_ARCH ..."

    if [ "$TARGET_ARCH" = "i686" ]; then
        TARGET_ARCH="x86"
    fi

    if [ ! -d "libass" ]; then
        echo "Cloning libass..."
        git clone https://github.com/libass/libass.git
    else
        echo "Updating libass..."
        cd libass || exit 1
        git pull
        cd ..
    fi

    cd libass || exit 1

    local CROSS_FILE="android-$TARGET_ARCH-$ANDROID_API_LEVEL-cross.meson"
    generate_meson_cross_file "$CROSS_FILE" "$CLANG" "$CLANGXX" "$TARGET_ARCH" "$TARGET_CPU" \
        "'-I$PREFIX/include', '-I$PREFIX/include/freetype2', '-I$PREFIX/include/harfbuzz', '-I$PREFIX/include/fribidi'" \
        "'-Wl,-z,max-page-size=16384'"

    echo "Meson cross file created for libass: $CROSS_FILE"

    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

    rm -rf build

    meson setup build \
        --default-library=static \
        --prefix="$PREFIX" \
        --buildtype release \
        --cross-file="$CROSS_FILE" \
        -Dfontconfig=disabled \
        -Drequire-system-font-provider=false
    if [ $? -ne 0 ]; then echo "Error: meson setup failed for libass"; return 1; fi

    ninja -C build
    if [ $? -ne 0 ]; then echo "Error: ninja build failed for libass"; return 1; fi

    ninja -C build install
    if [ $? -ne 0 ]; then echo "Error: ninja install failed for libass"; return 1; fi

    if [ ! -f "$PREFIX/lib/pkgconfig/libass.pc" ]; then
        echo "Error: libass.pc not found in $PREFIX/lib/pkgconfig"
        return 1
    fi

    cd "$ORIG_PWD" || exit 1
    echo ">>> libass build completed."
}


##############################################################################
# 配置并编译 FFmpeg（核心逻辑）
# 参数说明：同 buildLibdav1d
##############################################################################
configure_ffmpeg() {
    local TARGET_ARCH=$1
    local TARGET_CPU=$2
    local PREFIX=$3
    local CROSS_PREFIX=$4
    local EXTRA_CFLAGS=$5
    local EXTRA_CXXFLAGS=$6
    local EXTRA_CONFIG=$7

    export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
    local CLANG="${CROSS_PREFIX}clang"
    local CLANGXX="${CROSS_PREFIX}clang++"

    local SYSROOT_LIB_DIR=""
    case "$TARGET_ARCH" in
        aarch64) SYSROOT_LIB_DIR="$SYSROOT/usr/lib/aarch64-linux-android/$ANDROID_API_LEVEL" ;;
        arm)     SYSROOT_LIB_DIR="$SYSROOT/usr/lib/arm-linux-androideabi/$ANDROID_API_LEVEL" ;;
        i686)    SYSROOT_LIB_DIR="$SYSROOT/usr/lib/i686-linux-android/$ANDROID_API_LEVEL" ;;
        x86_64)  SYSROOT_LIB_DIR="$SYSROOT/usr/lib/x86_64-linux-android/$ANDROID_API_LEVEL" ;;
        *)       SYSROOT_LIB_DIR="$SYSROOT/usr/lib/$TARGET_ARCH-linux-android/$ANDROID_API_LEVEL" ;;
    esac

    echo "=== Dependency versions ==="
    echo "freetype2: $(pkg-config --modversion freetype2 2>/dev/null || echo not found)"
    echo "harfbuzz:  $(pkg-config --modversion harfbuzz 2>/dev/null || echo not found)"
    echo "fribidi:   $(pkg-config --modversion fribidi 2>/dev/null || echo not found)"
    echo "libass:    $(pkg-config --modversion libass 2>/dev/null || echo not found)"
    echo "lame:      $(pkg-config --modversion lame 2>/dev/null || echo not found)"
    echo "dav1d:     $(pkg-config --modversion dav1d 2>/dev/null || echo not found)"
    echo "x264:      $(pkg-config --modversion x264 2>/dev/null || echo not found)"

    cd "$FFMPEG_SOURCE_DIR" || exit 1

    local CONFIG_SUMMARY_FILE="configure.summary.$TARGET_ARCH.txt"

    ./configure \
        --disable-everything \
        --target-os=android \
        --arch="$TARGET_ARCH" \
        --cpu="$TARGET_CPU" \
        --pkg-config=pkg-config \
        --enable-cross-compile \
        --cross-prefix="$CROSS_PREFIX" \
        --cc="$CLANG" \
        --cxx="$CLANGXX" \
        --sysroot="$SYSROOT" \
        --prefix="$PREFIX" \
        --extra-cflags="-fpic -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D__BIONIC_NO_PAGE_SIZE_MACRO -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security $EXTRA_CFLAGS -I$PREFIX/include -I$PREFIX/include/freetype2 -I$PREFIX/include/harfbuzz -I$PREFIX/include/fribidi -I$PREFIX/include/libass" \
        --extra-cxxflags="-fpic -DANDROID -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -D__BIONIC_NO_PAGE_SIZE_MACRO -D_FORTIFY_SOURCE=2 -Wformat -Werror=format-security -std=c++17 -fexceptions -frtti $EXTRA_CXXFLAGS -I$PREFIX/include" \
        --extra-ldflags="-Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 -Wl,--no-rosegment -Wl,--no-undefined-version -Wl,--fatal-warnings -Wl,--no-undefined -Qunused-arguments -L$SYSROOT_LIB_DIR -L$PREFIX/lib" \
        --enable-pic \
        ${ENABLED_CONFIG} \
        ${DISABLED_CONFIG} \
        --ar="$LLVM_AR" \
        --nm="$LLVM_NM" \
        --ranlib="$LLVM_RANLIB" \
        --strip="$LLVM_STRIP" \
        ${EXTRA_CONFIG} 2>&1 | tee "$CONFIG_SUMMARY_FILE"

    # 验证 libass 是否成功启用（关键依赖检查）
    if ! (
        grep -Eq '#define[[:space:]]+CONFIG_LIBASS[[:space:]]+1' config.h 2>/dev/null || \
        grep -Eq '(^|[[:space:]])CONFIG_LIBASS[[:space:]]*=[[:space:]]*yes([[:space:]]|$)' config.mak 2>/dev/null
    ); then
        echo "Error: libass is NOT enabled. Check libass/fribidi detection and flags. See config.log for details."
        echo "Diagnostics:"
        echo "- fribidi: $(pkg-config --modversion fribidi 2>/dev/null || echo not found)"
        echo "- libass:  $(pkg-config --modversion libass 2>/dev/null || echo not found)"
        grep -E 'CONFIG_(LIBASS|LIBFRIBIDI)' -n config.h config.mak 2>/dev/null || true
        exit 1
    fi

    # 检查 libmp3lame 是否启用
    if ! (
        grep -Eq '#define[[:space:]]+CONFIG_LIBMP3LAME[[:space:]]+1' config.h 2>/dev/null || \
        grep -Eq '(^|[[:space:]])CONFIG_LIBMP3LAME[[:space:]]*=[[:space:]]*yes([[:space:]]|$)' config.mak 2>/dev/null
    ); then
        echo "Warning: libmp3lame is NOT enabled. Check lame detection and config.log for details."
        grep -E 'CONFIG_LIBMP3LAME' -n config.h config.mak 2>/dev/null || true
    fi

    # 检查 libx264 是否启用（视频编码核心依赖）
    if ! (
        grep -Eq '#define[[:space:]]+CONFIG_LIBX264[[:space:]]+1' config.h 2>/dev/null || \
        grep -Eq '(^|[[:space:]])CONFIG_LIBX264[[:space:]]*=[[:space:]]*yes([[:space:]]|$)' config.mak 2>/dev/null
    ); then
        echo "Error: libx264 is NOT enabled. PipelineB (MV Creator) requires H.264 encoding."
        echo "Diagnostics:"
        echo "- x264: $(pkg-config --modversion x264 2>/dev/null || echo not found)"
        grep -E 'CONFIG_LIBX264' -n config.h config.mak 2>/dev/null || true
        exit 1
    fi

    make clean
    make -j"$(nproc)"
    make install -j"$(nproc)"

    echo ">>> FFmpeg build completed for $TARGET_ARCH."
}


##############################################################################
# 主执行逻辑
##############################################################################
echo -e "\e[1;32mCompiling FFmpeg for Android...\e[0m"

# 检查必要环境变量
if [ -z "$FFMPEG_SOURCE_DIR" ]; then
    echo "Error: FFMPEG_SOURCE_DIR is not set"
    exit 1
fi

if [ -z "$ANDROID_NDK_PATH" ]; then
    echo "Error: ANDROID_NDK_PATH is not set"
    exit 1
fi

# 设置默认编译输出目录
if [ -z "${FFMPEG_BUILD_DIR:-}" ]; then
    FFMPEG_BUILD_DIR="$(pwd)"
    export FFMPEG_BUILD_DIR
    echo "FFMPEG_BUILD_DIR not set; defaulting to $(pwd)"
fi

# 遍历架构列表，逐架构编译依赖库 + FFmpeg
for ARCH in "${ARCH_LIST[@]}"; do
    case "$ARCH" in
        "armv8-a"|"aarch64"|"arm64-v8a"|"armv8a")
            echo -e "\e[1;32m=== Building for $ARCH ===\e[0m"
            TARGET_ARCH="aarch64"
            TARGET_CPU="armv8-a"
            TARGET_ABI="aarch64"
            PREFIX="${FFMPEG_BUILD_DIR}/$ANDROID_API_LEVEL/arm64-v8a"
            CROSS_PREFIX="$ANDROID_NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/$TARGET_ABI-linux-android${ANDROID_API_LEVEL}-"
            EXTRA_CFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CXXFLAGS="-O2 -march=$TARGET_CPU -fomit-frame-pointer"
            EXTRA_CONFIG="--enable-asm --enable-neon"
            ;;

        *)
            echo "Error: Unknown or unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    # 按依赖顺序编译库 + FFmpeg
    buildLibdav1d "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling libdav1d for $ARCH"; exit 1; fi

    buildFreetype "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling freetype for $ARCH"; exit 1; fi

    buildHarfBuzz "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling harfbuzz for $ARCH"; exit 1; fi

    buildFriBiDi "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling fribidi for $ARCH"; exit 1; fi

    buildLibass "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling libass for $ARCH"; exit 1; fi

    buildLibmp3lame "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling libmp3lame for $ARCH"; exit 1; fi

    buildLibx264 "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling libx264 for $ARCH"; exit 1; fi

    configure_ffmpeg "$TARGET_ARCH" "$TARGET_CPU" "$PREFIX" "$CROSS_PREFIX" "$EXTRA_CFLAGS" "$EXTRA_CXXFLAGS" "$EXTRA_CONFIG"
    if [ $? -ne 0 ]; then echo "Error compiling ffmpeg for $ARCH"; exit 1; fi

done

echo -e "\e[1;32mFFmpeg build for all architectures completed successfully!\e[0m"
