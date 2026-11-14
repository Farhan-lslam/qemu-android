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
