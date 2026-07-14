Name:       rusbmux
Version:    VERSION_PLACEHOLDER
Release:    1
Summary:    A usbmuxd replacement in pure Rust
License:    MIT OR Apache-2.0
URL:        https://github.com/abdullah-albanna/rusbmux
Vendor:     Abdullah Al-Banna <abdu.albanna@proton.me>
Requires:   glibc, libgcc
Provides:   rusbmux
Provides:   usbmuxd
Obsoletes:  usbmuxd
Conflicts:  usbmuxd

%define debug_package %{nil}

%description
rusbmux is a drop-in replacement for usbmuxd, written in pure Rust.
It provides USB multiplexing for Apple devices, supporting both
USB and WiFi connections. It works with libimobiledevice, idevice,
3uTools, iTunes, and other tools that use usbmuxd.

%prep
%setup -T -c

%build

%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/lib/systemd/system
mkdir -p %{buildroot}/usr/share/doc/rusbmux
mkdir -p %{buildroot}/usr/share/licenses/rusbmux

install -m 755 %{_sourcedir}/rusbmux %{buildroot}/usr/bin/rusbmux
install -m 644 %{_sourcedir}/systemd/rusbmux.service %{buildroot}/usr/lib/systemd/system/rusbmux.service
install -m 644 %{_sourcedir}/README.md %{buildroot}/usr/share/doc/rusbmux/README.md
install -m 644 %{_sourcedir}/LICENSE-MIT %{buildroot}/usr/share/licenses/rusbmux/LICENSE-MIT
install -m 644 %{_sourcedir}/LICENSE-APACHE %{buildroot}/usr/share/licenses/rusbmux/LICENSE-APACHE
install -m 644 %{_sourcedir}/THIRD_PARTY_LICENSES.txt %{buildroot}/usr/share/licenses/rusbmux/THIRD_PARTY_LICENSES.txt

%files
/usr/bin/rusbmux
/usr/lib/systemd/system/rusbmux.service
/usr/share/doc/rusbmux/README.md
/usr/share/licenses/rusbmux/LICENSE-MIT
/usr/share/licenses/rusbmux/LICENSE-APACHE
/usr/share/licenses/rusbmux/THIRD_PARTY_LICENSES.txt

%post
if systemctl --version >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl enable rusbmux || true
    systemctl restart rusbmux || true
fi

%preun
if [ "$1" = 0 ]; then
    if systemctl --version >/dev/null 2>&1; then
        systemctl disable --now rusbmux || true
    fi
fi

%postun
if [ "$1" = 0 ]; then
    if systemctl --version >/dev/null 2>&1; then
      rm -f /usr/lib/systemd/system/rusbmux.service
      systemctl daemon-reload || true
    fi
fi

%changelog
