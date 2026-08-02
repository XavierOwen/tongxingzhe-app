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
if [[ "${AUTH_SPIKE_DEVICE}" == "chrome" ]]; then
  # Flutter Web 的 integration_test 必须通过 flutter drive 与 ChromeDriver 运行。
  if ! command -v chromedriver >/dev/null 2>&1; then
    echo "Chrome 探针需要 chromedriver；请按 docs/spikes 中的 Web 步骤安装。" >&2
    exit 1
  fi

  chromedriver_owned=false
  # 复用已在 4444 端口运行的 driver；否则由本脚本临时启动并负责关闭。
  if ! curl --silent --fail http://127.0.0.1:4444/status >/dev/null 2>&1; then
    chromedriver --port=4444 >/dev/null 2>&1 &
    chromedriver_pid=$!
    chromedriver_owned=true

    chromedriver_ready=false
    for _ in {1..20}; do
      if curl --silent --fail http://127.0.0.1:4444/status >/dev/null 2>&1; then
        chromedriver_ready=true
        break
      fi
      sleep 0.25
    done
    if [[ "${chromedriver_ready}" != "true" ]]; then
      echo "chromedriver 未能在 4444 端口启动。" >&2
      exit 1
    fi
  fi

  cleanup_chromedriver() {
    if [[ "${chromedriver_owned}" == "true" ]]; then
      kill "${chromedriver_pid}" >/dev/null 2>&1 || true
      wait "${chromedriver_pid}" 2>/dev/null || true
    fi
  }
  trap cleanup_chromedriver EXIT INT TERM

  # test_driver 在主机端接收浏览器内同一份合同探针的结果。
  flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/supabase_auth_spike_test.dart \
    --device-id chrome \
    --dart-define-from-file "${AUTH_SPIKE_CONFIG}"
else
  # 原生平台可以直接把 integration_test 运行在目标设备上。
  flutter test \
    integration_test/supabase_auth_spike_test.dart \
    --device-id "${AUTH_SPIKE_DEVICE}" \
    --dart-define-from-file "${AUTH_SPIKE_CONFIG}"
fi
