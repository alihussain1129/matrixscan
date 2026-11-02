#!/usr/bin/env bash
set -euo pipefail

# Script to build Android Release APK for Exalted
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Building Exalted Android Release APK ==="
cd "${REPO_ROOT}"

# Ensure Android SDK is accessible
export ANDROID_HOME="${ANDROID_HOME:-/home/alihussain/Android/Sdk}"
export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

echo "Android SDK: ${ANDROID_HOME}"

# Build APK with split per ABI to optimize bundle size for ARM64 and ARMv7
flutter build apk --release --split-per-abi

echo "=== Android Build Finished ==="
echo "Generated APKs located in: build/app/outputs/flutter-apk/"
