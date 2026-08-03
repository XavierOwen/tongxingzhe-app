#!/usr/bin/env bash

set -euo pipefail

# Flutter 先生成 Xcode 配置；CI 随后明确关闭签名，只验证 macOS 可编译。
# Keychain entitlement 的真实可用性必须由带 Apple Development 签名的设备探针证明。
flutter config --enable-macos-desktop
flutter build macos --debug --config-only --no-pub

xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/macos/ci-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -quiet \
  build
