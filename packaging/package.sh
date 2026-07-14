#!/usr/bin/env bash
# Native packaging for rusbmux — no fpm involved.
# Mirrors the approach used by RustDesk: dpkg-deb, rpmbuild, makepkg, abuild.
set -euo pipefail

BIN="${BIN:-target/release/rusbmux}"
VERSION="${VERSION:-$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')}"
ARCH="${ARCH:-$(uname -m)}"
OUTDIR="${OUTDIR:-out}"
# Handle relative/absolute paths
case "$OUTDIR" in
/*) OUTDIR_ABS="$OUTDIR" ;;
*) OUTDIR_ABS="$(pwd)/$OUTDIR" ;;
esac
case "$BIN" in
/*) BIN_ABS="$BIN" ;;
*) BIN_ABS="$(cd "$(dirname "$0")/.." && pwd)/$BIN" ;;
esac
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "$ARCH" in
x86_64)
  DEB_ARCH=amd64
  RPM_ARCH=x86_64
  PKG_ARCH=x86_64
  APK_ARCH=x86_64
  ;;
aarch64)
  DEB_ARCH=arm64
  RPM_ARCH=aarch64
  PKG_ARCH=aarch64
  APK_ARCH=aarch64
  ;;
armv7 | armv7l | armhf)
  DEB_ARCH=armhf
  RPM_ARCH=armv7hnl
  PKG_ARCH=armv7h
  APK_ARCH=armv7
  ;;
i686 | i386 | x86)
  DEB_ARCH=i386
  RPM_ARCH=i686
  PKG_ARCH=i686
  APK_ARCH=x86
  ;;
*)
  echo "unknown arch: $ARCH"
  exit 1
  ;;
esac

LIBC="${LIBC:-}"
if [ -z "$LIBC" ] && [ -f "$BIN_ABS" ]; then
  local_interp=$(readelf -l "$BIN_ABS" 2>/dev/null | grep -i 'interpreter' || true | awk '{print $NF}' | tr -d ']')
  if [ -z "$local_interp" ]; then
    LIBC=musl
  elif echo "$local_interp" | grep -q musl; then
    LIBC=musl
  else
    LIBC=glibc
  fi
elif [ -z "$LIBC" ]; then
  LIBC=glibc
fi

if [ "$LIBC" = "musl" ]; then
  DEB_DEPENDS=""
  RPM_REQUIRES=""
  PKG_DEPENDS=""
else
  DEB_DEPENDS="libc6, libgcc-s1"
  RPM_REQUIRES="glibc, libgcc"
  PKG_DEPENDS="depend = glibc
depend = gcc-libs"
fi

mkdir -p "$OUTDIR_ABS"

build_deb() {
  echo ":: Building .deb (dpkg-deb) ..."

  local pkgdir
  pkgdir="$(mktemp -d)"

  mkdir -p "$pkgdir/usr/bin"
  mkdir -p "$pkgdir/usr/lib/systemd/system"
  mkdir -p "$pkgdir/usr/share/doc/rusbmux"
  mkdir -p "$pkgdir/usr/share/licenses/rusbmux"

  install -m 755 "$BIN_ABS" "$pkgdir/usr/bin/rusbmux"
  install -m 644 "$REPO_ROOT/systemd/rusbmux.service" "$pkgdir/usr/lib/systemd/system/rusbmux.service"
  install -m 644 "$REPO_ROOT/README.md" "$pkgdir/usr/share/doc/rusbmux/README.md"
  install -m 644 "$REPO_ROOT/LICENSE-MIT" "$pkgdir/usr/share/licenses/rusbmux/LICENSE-MIT"
  install -m 644 "$REPO_ROOT/LICENSE-APACHE" "$pkgdir/usr/share/licenses/rusbmux/LICENSE-APACHE"
  install -m 644 "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$pkgdir/usr/share/licenses/rusbmux/THIRD_PARTY_LICENSES.txt"

  mkdir -p "$pkgdir/DEBIAN"
  sed -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    -e "s/ARCH_PLACEHOLDER/$DEB_ARCH/g" \
    -e "s/DEPENDS_PLACEHOLDER/$DEB_DEPENDS/g" \
    "$REPO_ROOT/packaging/DEBIAN/control" >"$pkgdir/DEBIAN/control"
  cp "$REPO_ROOT/packaging/DEBIAN/postinst" "$pkgdir/DEBIAN/postinst"
  cp "$REPO_ROOT/packaging/DEBIAN/prerm" "$pkgdir/DEBIAN/prerm"
  chmod 755 "$pkgdir/DEBIAN/postinst" "$pkgdir/DEBIAN/prerm"

  local deb_name="rusbmux_${VERSION}_${DEB_ARCH}.deb"
  dpkg-deb --root-owner-group --build "$pkgdir" "$OUTDIR_ABS/$deb_name"

  rm -rf "$pkgdir"
  echo "    -> $OUTDIR_ABS/$deb_name"
}

build_rpm() {
  echo ":: Building .rpm (rpmbuild) ..."

  local rpmdir
  rpmdir="$(mktemp -d)"

  mkdir -p "$rpmdir/BUILD" "$rpmdir/RPMS/$RPM_ARCH" "$rpmdir/SOURCES" "$rpmdir/SPECS" "$rpmdir/SRPMS"

  # rpmbuild expects sources under SOURCES with paths matching the spec
  cp "$BIN_ABS" "$rpmdir/SOURCES/rusbmux"
  mkdir -p "$rpmdir/SOURCES/systemd"
  cp "$REPO_ROOT/systemd/rusbmux.service" "$rpmdir/SOURCES/systemd/rusbmux.service"
  cp "$REPO_ROOT/README.md" "$rpmdir/SOURCES/"
  cp "$REPO_ROOT/LICENSE-MIT" "$rpmdir/SOURCES/"
  cp "$REPO_ROOT/LICENSE-APACHE" "$rpmdir/SOURCES/"
  cp "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$rpmdir/SOURCES/"

  sed -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    -e "s/ARCH_PLACEHOLDER/$RPM_ARCH/g" \
    -e "s/DEPENDS_PLACEHOLDER/$RPM_REQUIRES/g" \
    -e "/^Requires: *$/d" \
    "$REPO_ROOT/packaging/rusbmux.spec" >"$rpmdir/SPECS/rusbmux.spec"

  rpmbuild --define "_topdir $rpmdir" \
    --define "_rpmdir $rpmdir/RPMS" \
    --define "_target_cpu $RPM_ARCH" \
    -bb "$rpmdir/SPECS/rusbmux.spec"

  # rpmbuild outputs to $rpmdir/RPMS/$RPM_ARCH/*.rpm
  find "$rpmdir/RPMS" -name "*.rpm" -exec mv {} "$OUTDIR_ABS/" \; 2>/dev/null || true

  rm -rf "$rpmdir"

  local rpm_name="rusbmux-${VERSION}-1.${RPM_ARCH}.rpm"
  echo "    -> $OUTDIR_ABS/$rpm_name"
}

build_pacman() {
  echo ":: Building .pkg.tar.zst (makepkg) ..."

  local pkgdir
  pkgdir="$(mktemp -d)"

  mkdir -p "$pkgdir/usr/bin"
  mkdir -p "$pkgdir/usr/lib/systemd/system"
  mkdir -p "$pkgdir/usr/share/doc/rusbmux"
  mkdir -p "$pkgdir/usr/share/licenses/rusbmux"

  install -m 755 "$BIN_ABS" "$pkgdir/usr/bin/rusbmux"
  install -m 644 "$REPO_ROOT/systemd/rusbmux.service" "$pkgdir/usr/lib/systemd/system/rusbmux.service"
  install -m 644 "$REPO_ROOT/README.md" "$pkgdir/usr/share/doc/rusbmux/README.md"
  install -m 644 "$REPO_ROOT/LICENSE-MIT" "$pkgdir/usr/share/licenses/rusbmux/LICENSE-MIT"
  install -m 644 "$REPO_ROOT/LICENSE-APACHE" "$pkgdir/usr/share/licenses/rusbmux/LICENSE-APACHE"
  install -m 644 "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$pkgdir/usr/share/licenses/rusbmux/THIRD_PARTY_LICENSES.txt"

  local pac_name="rusbmux-${VERSION}-1-${PKG_ARCH}.pkg.tar.zst"

  pushd "$pkgdir" >/dev/null
  tar -c --zstd -f "$OUTDIR_ABS/$pac_name" --owner=0 --group=0 .
  popd >/dev/null

  # Generate .PKGINFO for pacman metadata
  # (bsdtar-based packages need an mtree or .PKGINFO; makepkg generates these,
  #  but since we're using bsdtar directly, we build a minimal valid package.)
  # A real Arch package also includes .PKGINFO and .MTREE. We'll create a proper
  # one using a temporary .PKGINFO:
  local tmpdir
  tmpdir="$(mktemp -d)"
  mkdir -p "$tmpdir/usr/bin"
  cp "$BIN_ABS" "$tmpdir/usr/bin/rusbmux"

  cat >"$tmpdir/.PKGINFO" <<EOF
pkgname = rusbmux
pkgver = $VERSION-1
pkgdesc = A usbmuxd replacement in pure Rust
url = https://github.com/abdullah-albanna/rusbmux
builddate = $(date +%s)
packager = Abdullah Al-Banna <abdu.albanna@proton.me>
size = $(stat -c%s "$BIN_ABS")
arch = $PKG_ARCH
license = MIT
license = Apache-2.0
provides = rusbmux
provides = usbmuxd
conflict = usbmuxd
$PKG_DEPENDS
EOF

  pushd "$tmpdir" >/dev/null
  tar -c --zstd -f "$OUTDIR_ABS/$pac_name" --owner=0 --group=0 .PKGINFO usr/
  popd >/dev/null

  rm -rf "$tmpdir" "$pkgdir"
  echo "    -> $OUTDIR_ABS/$pac_name"
}

build_apk() {
  echo ":: Building .apk (abuild) ..."

  local workdir
  workdir="$(mktemp -d)"

  # Source tree abuild expects:
  #   $workdir/APKBUILD
  #   $workdir/src/rusbmux-$VERSION/target/release/rusbmux  (pre-built binary)
  #   $workdir/src/rusbmux-$VERSION/{README.md,LICENSE-*,THIRD_PARTY_LICENSES.txt,systemd/rusbmux.service}

  local builddir="$workdir/src/rusbmux-$VERSION"
  mkdir -p "$builddir/target/release"

  install -m 755 "$BIN_ABS" "$builddir/target/release/rusbmux"
  install -m 644 "$REPO_ROOT/README.md" "$builddir/"
  install -m 644 "$REPO_ROOT/LICENSE-MIT" "$builddir/"
  install -m 644 "$REPO_ROOT/LICENSE-APACHE" "$builddir/"
  install -m 644 "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$builddir/"

  sed -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    -e "s/ARCH_PLACEHOLDER/$APK_ARCH/g" \
    "$REPO_ROOT/packaging/APKBUILD" >"$workdir/APKBUILD"

  export REPODEST="$workdir/packages"
  export FAKEROOT_DONT_STRIP=1
  export CARCH="$APK_ARCH"
  # Alpine doesn't use systemd; suppress the postcheck warning about it
  export ABUILD_POSTCHECK="${ABUILD_POSTCHECK:-0}"

  pushd "$workdir" >/dev/null
  if ! abuild -K rootpkg 2>&1; then
    popd >/dev/null
    rm -rf "$workdir"
    echo ":: ERROR: abuild failed"
    return 1
  fi
  popd >/dev/null

  local apk_name="rusbmux-${VERSION}-r1-${APK_ARCH}.apk"
  # abuild outputs to $REPODEST/$repo/$arch/$name.apk — find it anywhere
  local found
  found="$(find "$workdir/packages" -name "*.apk" -print -quit 2>/dev/null)"
  if [ -n "$found" ]; then
    mv "$found" "$OUTDIR_ABS/$apk_name"
  fi

  rm -rf "$workdir"
  echo "    -> $OUTDIR_ABS/$apk_name"
}

build_apk_manual() {
  echo ":: Building .apk (tar + .PKGINFO - no abuild) ..."

  local pkgdir
  pkgdir="$(mktemp -d)"

  mkdir -p "$pkgdir/usr/bin"
  mkdir -p "$pkgdir/usr/share/doc/rusbmux"
  mkdir -p "$pkgdir/usr/share/licenses/rusbmux"

  install -m 755 "$BIN_ABS" "$pkgdir/usr/bin/rusbmux"
  install -m 644 "$REPO_ROOT/README.md" "$pkgdir/usr/share/doc/rusbmux/README.md"
  install -m 644 "$REPO_ROOT/LICENSE-MIT" "$pkgdir/usr/share/licenses/rusbmux/LICENSE-MIT"
  install -m 644 "$REPO_ROOT/LICENSE-APACHE" "$pkgdir/usr/share/licenses/rusbmux/LICENSE-APACHE"
  install -m 644 "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$pkgdir/usr/share/licenses/rusbmux/THIRD_PARTY_LICENSES.txt"

  cat >"$pkgdir/.PKGINFO" <<EOF
pkgname = rusbmux
pkgver = $VERSION-r1
pkgdesc = A usbmuxd replacement in pure Rust
url = https://github.com/abdullah-albanna/rusbmux
builddate = $(date +%Y-%m-%dT%H:%M:%S%z)
packager = Abdullah Al-Banna <abdu.albanna@proton.me>
size = $(stat -c%s "$BIN_ABS")
arch = $APK_ARCH
license = MIT
license = Apache-2.0
provides = usbmuxd
replaces = usbmuxd
install = if-no-such-file
EOF

  local apk_name="rusbmux-${VERSION}-r1-${APK_ARCH}.apk"
  pushd "$pkgdir" >/dev/null
  tar -c -z -f "$OUTDIR_ABS/$apk_name" --owner=0 --group=0 .PKGINFO usr/
  popd >/dev/null

  rm -rf "$pkgdir"
  echo "    -> $OUTDIR_ABS/$apk_name"
}

# ---- tarball (portable) ----
build_tarball() {
  echo ":: Building tarball ..."

  local pkgdir
  pkgdir="$(mktemp -d)"
  mkdir -p "$pkgdir/rusbmux-$VERSION"

  cp "$BIN_ABS" "$pkgdir/rusbmux-$VERSION/rusbmux"
  cp "$REPO_ROOT/systemd/rusbmux.service" "$pkgdir/rusbmux-$VERSION/"
  cp "$REPO_ROOT/README.md" "$pkgdir/rusbmux-$VERSION/"
  cp "$REPO_ROOT/LICENSE-MIT" "$pkgdir/rusbmux-$VERSION/"
  cp "$REPO_ROOT/LICENSE-APACHE" "$pkgdir/rusbmux-$VERSION/"

  pushd "$pkgdir" >/dev/null
  tar -c -z -f "$OUTDIR_ABS/rusbmux-${VERSION}-${DEB_ARCH}.tar.gz" "rusbmux-$VERSION"
  popd >/dev/null

  rm -rf "$pkgdir"
  echo "    -> $OUTDIR_ABS/rusbmux-${VERSION}-${DEB_ARCH}.tar.gz"
}

# ---- main ----
main() {
  local formats=("$@")
  if [ ${#formats[@]} -eq 0 ]; then
    formats=(deb rpm pacman apk tar)
  fi

  for fmt in "${formats[@]}"; do
    case "$fmt" in
    deb) build_deb ;;
    rpm) build_rpm ;;
    pacman) build_pacman ;;
    apk) build_apk ;;
    tar) build_tarball ;;
    *) echo "skipping unknown format: $fmt" ;;
    esac
  done

  echo ""
  echo "Packages produced:"
  ls -lh "$OUTDIR_ABS"/
}

main "$@"
