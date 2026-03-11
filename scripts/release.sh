#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: release.sh <version>}"
BINARY_NAME="ding"
BUILD_DIR=".build"
OUTPUT_DIR="${BUILD_DIR}/release-artifacts"

echo "Building ding v${VERSION}..."

# Build for both architectures
echo "Building arm64..."
swift build -c release --triple arm64-apple-macosx

echo "Building x86_64..."
swift build -c release --triple x86_64-apple-macosx

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Create universal binary
echo "Creating universal binary..."
lipo -create \
  "${BUILD_DIR}/arm64-apple-macosx/release/${BINARY_NAME}" \
  "${BUILD_DIR}/x86_64-apple-macosx/release/${BINARY_NAME}" \
  -output "${OUTPUT_DIR}/${BINARY_NAME}"

# Verify universal binary
echo "Verifying universal binary..."
lipo -info "${OUTPUT_DIR}/${BINARY_NAME}"

# Verify version
echo "Version check:"
"${OUTPUT_DIR}/${BINARY_NAME}" --version

# Create zip archive
echo "Creating archive..."
cd "${OUTPUT_DIR}"
ditto -c -k --keepParent "${BINARY_NAME}" "${BINARY_NAME}-${VERSION}-macos.zip"
cd - > /dev/null

# Compute SHA256
SHA256=$(shasum -a 256 "${OUTPUT_DIR}/${BINARY_NAME}-${VERSION}-macos.zip" | awk '{print $1}')
echo "SHA256: ${SHA256}"

# Save SHA256 for formula update
echo "${SHA256}" > "${OUTPUT_DIR}/sha256.txt"

echo ""
echo "Release artifacts ready in ${OUTPUT_DIR}/"
echo "  Binary:  ${OUTPUT_DIR}/${BINARY_NAME}"
echo "  Archive: ${OUTPUT_DIR}/${BINARY_NAME}-${VERSION}-macos.zip"
echo "  SHA256:  ${SHA256}"
echo ""
echo "Next steps:"
echo "  1. Create GitHub release: gh release create v${VERSION} ${OUTPUT_DIR}/${BINARY_NAME}-${VERSION}-macos.zip --title 'ding v${VERSION}'"
echo "  2. Update homebrew-tap/Formula/ding.rb with the new URL and SHA256"
echo "  3. Push homebrew-tap changes"
