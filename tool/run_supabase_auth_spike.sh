#!/usr/bin/env bash

set -euo pipefail

: "${AUTH_SPIKE_DEVICE:?请设置 AUTH_SPIKE_DEVICE，例如 chrome、macos 或设备 ID}"
: "${AUTH_SPIKE_CONFIG:?请设置 AUTH_SPIKE_CONFIG，指向 secrets/ 下的 JSON 配置}"

if [[ ! -f "${AUTH_SPIKE_CONFIG}" ]]; then
  echo "找不到 spike 配置文件：${AUTH_SPIKE_CONFIG}" >&2
  exit 1
fi

case "${AUTH_SPIKE_CONFIG}" in
  */secrets/* | secrets/*) ;;
  *)
    echo "为避免误提交，AUTH_SPIKE_CONFIG 必须位于被 Git 忽略的 secrets/ 目录。" >&2
    exit 1
    ;;
esac

# 不在命令行展开 email、密码或 OTP；Flutter 直接读取受忽略的 JSON 文件。
flutter test \
  integration_test/supabase_auth_spike_test.dart \
  --device-id "${AUTH_SPIKE_DEVICE}" \
  --dart-define-from-file "${AUTH_SPIKE_CONFIG}"
