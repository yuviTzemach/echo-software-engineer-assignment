#!/bin/bash
# Build the patched nginx .deb from source.
# This runs inside the Debian build container, so everything is built from scratch.
set -euo pipefail

NGINX_VERSION="${NGINX_VERSION:-1.25.5}"
DEB_REVISION="${DEB_REVISION:-1~bookworm}"
SRC_BASE="http://nginx.org/packages/mainline/debian/pool/nginx/n/nginx"

DSC="nginx_${NGINX_VERSION}-${DEB_REVISION}.dsc"
ORIG="nginx_${NGINX_VERSION}.orig.tar.gz"
DEBIAN_TAR="nginx_${NGINX_VERSION}-${DEB_REVISION}.debian.tar.xz"

echo "=== Fetching upstream source package ${NGINX_VERSION}-${DEB_REVISION} ==="

# Download the source files we need to build the package.
for f in "$DSC" "$ORIG" "$DEBIAN_TAR"; do
    curl -fsSL -o "$f" "$SRC_BASE/$f"
done

# dpkg-source will check that the downloaded files match the checksums in the .dsc file.
dpkg-source --no-check -x "$DSC" nginx-src

echo "=== Registering CVE patches with the Debian patch system (quilt) ==="

cd nginx-src
mkdir -p debian/patches
touch debian/patches/series

# Copy our patches into the Debian source tree and add them to quilt's
# patch list so they are applied automatically during the build.
for p in /build/patches/*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
cat debian/patches/series

echo "=== [3/4] Compiling the .deb from source (dpkg-buildpackage) ==="

# Build the package without signing it. 
# The patches listed above are applied automatically as part of the Debian build process.
dpkg-buildpackage -b -uc -us

echo "=== [4/4] Collecting artifacts ==="
cd ..
mkdir -p out

# Put the generated packages and build metadata in the output directory.
cp ./*.deb ./*.buildinfo ./*.changes out/
ls -la out/