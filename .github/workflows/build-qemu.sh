#!/usr/bin/env bash
# Cross-compiles QEMU (system emulation) for 32-bit ARM Android (armeabi-v7a).
# Usage: bash build-qemu.sh [deps|qemu|all]
set -euxo pipefail

STAGE="${1:-all}"

API=28
TRIPLE=armv7a-linux-androideabi
NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_ROOT:?Android NDK not found}}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
ROOT="$(pwd)"
SRC="$ROOT/src"
PREFIX="$ROOT/prefix"
OUT="$ROOT/out"
JOBS="$(nproc)"
mkdir -p "$SRC" "$PREFIX" "$OUT" "$ROOT/bin"

export PATH="$TC/bin:$PATH"
export CC="$TRIPLE$API-clang"
export CXX="$TRIPLE$API-clang++"
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export LD=ld.lld
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=""
export CFLAGS="-O2 -fPIC -I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"

fetch() {
  local url="$1" dir="$2" file
  file="$SRC/$(basename "$url")"
  if [ -d "$SRC/$dir" ]; then return 0; fi
  curl -fL -o "$file" "$url"
  mkdir -p "$SRC/$dir"
  tar -xf "$file" --strip-components=1 -C "$SRC/$dir"
}

write_cross_file() {
  cat > "$ROOT/android-arm.cross" <<EOF
[binaries]
c = '$TC/bin/$TRIPLE$API-clang'
cpp = '$TC/bin/$TRIPLE$API-clang++'
ar = '$TC/bin/llvm-ar'
strip = '$TC/bin/llvm-strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'

[built-in options]
c_args = ['-O2', '-fPIC', '-I$PREFIX/include']
c_link_args = ['-L$PREFIX/lib']

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$PREFIX/lib/pkgconfig']
EOF
}

build_deps() {
  echo "=== zlib ==="
  fetch https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz zlib
  (cd "$SRC/zlib" && ./configure --prefix="$PREFIX" --static && make -j"$JOBS" && make install)

  echo "=== libffi ==="
  fetch https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz libffi
  (cd "$SRC/libffi" && ./configure --host=arm-linux-androideabi --prefix="$PREFIX" --disable-shared --enable-static --disable-docs && make -j"$JOBS" && make install)

  echo "=== pcre2 ==="
  fetch https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz pcre2
  (cd "$SRC/pcre2" && ./configure --host=arm-linux-androideabi --prefix="$PREFIX" --disable-shared --enable-static && make -j"$JOBS" && make install)

  write_cross_file

  echo "=== glib ==="
  fetch https://download.gnome.org/sources/glib/2.78/glib-2.78.6.tar.xz glib
  (cd "$SRC/glib" && meson setup build --cross-file "$ROOT/android-arm.cross" --prefix="$PREFIX" \
    --default-library=static --buildtype=release --wrap-mode=nofallback \
    -Dtests=false -Dxattr=false -Dlibmount=disabled -Dselinux=disabled -Dnls=disabled \
    -Dintrospection=disabled -Dglib_debug=disabled -Dlibelf=disabled \
    && ninja -C build install)

  echo "=== pixman ==="
  fetch https://cairographics.org/releases/pixman-0.42.2.tar.gz pixman
  (cd "$SRC/pixman" && meson setup build --cross-file "$ROOT/android-arm.cross" --prefix="$PREFIX" \
    --default-library=static --buildtype=release --wrap-mode=nofallback \
    -Dneon=disabled -Darm-simd=disabled -Dopenmp=disabled -Dgtk=disabled -Dlibpng=disabled \
    -Dtests=disabled -Ddemos=disabled \
    && ninja -C build install)
}

build_qemu() {
  echo "=== qemu ==="
  fetch https://download.qemu.org/qemu-8.2.2.tar.xz qemu

  cat > "$ROOT/bin/pkg-config-static" <<'EOF'
#!/bin/sh
exec pkg-config --static "$@"
EOF
  chmod +x "$ROOT/bin/pkg-config-static"
  export PKG_CONFIG="$ROOT/bin/pkg-config-static"

  mkdir -p "$SRC/qemu/build"
  cd "$SRC/qemu/build"
  ../configure \
    --cross-prefix=arm-linux-androideabi- \
    --cpu=arm \
    --cc="$CC" --cxx="$CXX" --host-cc=gcc \
    --prefix=/qemu \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --target-list=i386-softmmu \
    --disable-docs --disable-tools --disable-guest-agent --disable-user \
    --disable-werror --disable-capstone --disable-kvm

  make -j"$JOBS"
  make install DESTDIR="$OUT/install"
  llvm-strip "$OUT/install/qemu/bin/qemu-system-i386" || true
  tar -czf "$OUT/qemu-android-armv7.tar.gz" -C "$OUT/install" qemu
  ls -lh "$OUT"
}

case "$STAGE" in
  deps) build_deps ;;
  qemu) build_qemu ;;
  all)  build_deps; build_qemu ;;
  *) echo "unknown stage: $STAGE"; exit 1 ;;
esac
