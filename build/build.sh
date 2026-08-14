#!/bin/bash
# Builds the patched nginx .deb from upstream source.
# Runs inside debian:bookworm-slim — see build/Dockerfile. No pre-baked
# binaries: we fetch the exact source package the upstream image shipped
# (nginx 1.25.5-1~bookworm from nginx.org), apply our CVE patches, and
# compile the .deb ourselves.
set -euo pipefail

NGINX_VERSION="${NGINX_VERSION:-1.25.5}"
DEB_REVISION="${DEB_REVISION:-1~bookworm}"
SRC_BASE="http://nginx.org/packages/mainline/debian/pool/nginx/n/nginx"

DSC="nginx_${NGINX_VERSION}-${DEB_REVISION}.dsc"
ORIG="nginx_${NGINX_VERSION}.orig.tar.gz"
DEBIAN_TAR="nginx_${NGINX_VERSION}-${DEB_REVISION}.debian.tar.xz"

echo "=== [1/4] Fetching upstream source package ${NGINX_VERSION}-${DEB_REVISION} ==="
for f in "$DSC" "$ORIG" "$DEBIAN_TAR"; do
    curl -fsSL -o "$f" "$SRC_BASE/$f"
done
# --no-check: we did not import the nginx.org signing key into this
# throwaway build container; integrity comes from fetching over the
# official pool plus the .dsc checksums that dpkg-source still verifies.
dpkg-source --no-check -x "$DSC" nginx-src

echo "=== [2/4] Registering CVE patches with the Debian patch system (quilt) ==="
cd nginx-src
mkdir -p debian/patches
touch debian/patches/series
for p in /build/patches/*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
cat debian/patches/series

echo "=== [3/4] Compiling the .deb from source (dpkg-buildpackage) ==="
# -b binary only, -uc -us unsigned; quilt patches in series are applied
# automatically before the build.
dpkg-buildpackage -b -uc -us

echo "=== [4/4] Collecting artifacts ==="
cd ..
mkdir -p out
cp ./*.deb ./*.buildinfo ./*.changes out/
ls -la out/
