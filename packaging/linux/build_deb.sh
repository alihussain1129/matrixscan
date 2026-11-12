#!/usr/bin/env bash
set -euo pipefail

# Script to build a Debian package (.deb) and portable tarball for Exalted
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VERSION="1.0.0"
ARCH="amd64"
PKG_NAME="exalted"
BUNDLE_DIR="${REPO_ROOT}/build/linux/x64/release/bundle"
BUILD_OUTPUT_DIR="${REPO_ROOT}/build"
STAGE_DIR="${BUILD_OUTPUT_DIR}/deb_staging/${PKG_NAME}_${VERSION}_${ARCH}"

echo "=== Packaging Exalted for Linux x64 ==="

# Check that the release bundle exists; if not, build it.
if [ ! -f "${BUNDLE_DIR}/exalted" ]; then
    echo "Release bundle not found. Building with Flutter..."
    cd "${REPO_ROOT}"
    flutter build linux --release --no-pub
fi

# Clean prior staging
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/DEBIAN"
mkdir -p "${STAGE_DIR}/opt/exalted"
mkdir -p "${STAGE_DIR}/usr/bin"
mkdir -p "${STAGE_DIR}/usr/share/applications"
mkdir -p "${STAGE_DIR}/usr/share/icons/hicolor/512x512/apps"

# Copy release bundle contents
echo "Copying release bundle to /opt/exalted..."
cp -r "${BUNDLE_DIR}/." "${STAGE_DIR}/opt/exalted/"

# Ensure correct executable permissions
chmod 755 "${STAGE_DIR}/opt/exalted/exalted"
find "${STAGE_DIR}/opt/exalted/lib" -type f -name "*.so" -exec chmod 755 {} \;

# Create launcher symlink in /usr/bin
ln -sf "/opt/exalted/exalted" "${STAGE_DIR}/usr/bin/exalted"

# Install desktop entry
cp "${SCRIPT_DIR}/exalted.desktop" "${STAGE_DIR}/usr/share/applications/exalted.desktop"
chmod 644 "${STAGE_DIR}/usr/share/applications/exalted.desktop"

# Install application icon
if [ -f "${REPO_ROOT}/web/icons/Icon-512.png" ]; then
    cp "${REPO_ROOT}/web/icons/Icon-512.png" "${STAGE_DIR}/usr/share/icons/hicolor/512x512/apps/exalted.png"
    chmod 644 "${STAGE_DIR}/usr/share/icons/hicolor/512x512/apps/exalted.png"
fi

# Generate control file
cat <<EOF > "${STAGE_DIR}/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libtesseract5, tesseract-ocr, tesseract-ocr-eng
Maintainer: Exalted Engineering <engineering@exalted.local>
Homepage: https://github.com/alihussain1129/matrixscan
Description: Industrial Machine Vision, OCR/OCV & Barcode Platform
 Exalted is an industrial-grade machine vision and scanning platform
 supporting Keyence SR-751 CMOS cameras, offline Tesseract 5.3 OCR,
 Data Matrix ECC200 C++20 decoding, and automated OCV rule verification.
EOF

chmod 755 "${STAGE_DIR}/DEBIAN"
chmod 644 "${STAGE_DIR}/DEBIAN/control"

# Normalize folder permissions across the package tree
find "${STAGE_DIR}" -type d -exec chmod 755 {} \;

# Build Debian package
DEB_FILE="${BUILD_OUTPUT_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "Building Debian package: ${DEB_FILE}..."
dpkg-deb --build --root-owner-group "${STAGE_DIR}" "${DEB_FILE}"

# Create portable tarball
TAR_FILE="${BUILD_OUTPUT_DIR}/${PKG_NAME}-linux-x64-v${VERSION}.tar.gz"
echo "Building portable release tarball: ${TAR_FILE}..."
tar -czf "${TAR_FILE}" -C "${BUNDLE_DIR}" .

echo "=== Linux Packaging Complete ==="
echo "Debian package: ${DEB_FILE} ($(du -h "${DEB_FILE}" | cut -f1))"
echo "Portable tarball: ${TAR_FILE} ($(du -h "${TAR_FILE}" | cut -f1))"
