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

# signup_request 是唯一会建立新账号的模式。先在本机读取有限的配置字段，
# 再决定是否允许 Flutter 启动；这里不联系 Supabase，也不读取密码。
if ! command -v dart >/dev/null 2>&1; then
  echo "signup 安全检查需要 Flutter SDK 自带的 dart 命令读取 JSON 配置。" >&2
  exit 1
fi

if ! auth_spike_config_values="$(
  dart tool/parse_supabase_auth_spike_config.dart "${AUTH_SPIKE_CONFIG}"
)"; then
  echo "无法读取 AUTH_SPIKE_CONFIG 的 JSON 内容。" >&2
  exit 1
fi

IFS=$'\t' read -r auth_spike_mode auth_spike_email \
  auth_spike_signup_confirmation <<<"${auth_spike_config_values}"

if [[ "${auth_spike_mode}" == "signup_request" ]]; then
  if [[ "${auth_spike_signup_confirmation}" != "true" ]]; then
    echo "signup_request 需要 AUTH_SPIKE_SIGNUP_CONFIRM_NEW_SYNTHETIC_ACCOUNT=true。" >&2
    echo "该字段只确认本次地址是新的合成测试账号；其他模式不读取它。" >&2
    exit 1
  fi

  if [[ ! "${auth_spike_email}" =~ ^auth-spike-[a-z0-9][a-z0-9._-]*@[a-z0-9][a-z0-9.-]*\.[a-z0-9]+$ ]]; then
    echo "signup_request 只接受带 auth-spike- 前缀的 synthetic-test email。" >&2
    echo "普通个人地址和示例占位地址不会启动 Flutter。" >&2
    exit 1
  fi
fi

# 不在命令行展开 email、密码或 OTP；Flutter 直接读取受忽略的 JSON 文件。
if [[ "${AUTH_SPIKE_DEVICE}" == "chrome" ]]; then
  # Flutter Web 的 integration_test 必须通过 flutter drive 与 ChromeDriver 运行。
  if ! command -v chromedriver >/dev/null 2>&1; then
    echo "Chrome 探针需要 chromedriver；请按 docs/spikes 中的 Web 步骤安装。" >&2
    exit 1
  fi

  # Web 安全存储受 origin 和浏览器 profile 约束。固定 hostname／port，并让
  # 前后两次 runner 复用同一个被 Git 忽略的 profile，才能真实验证进程重启恢复。
  auth_spike_web_port="${AUTH_SPIKE_WEB_PORT:-57320}"
  if [[ ! "${auth_spike_web_port}" =~ ^[0-9]+$ ]] ||
    ((auth_spike_web_port < 1024 || auth_spike_web_port > 65535)); then
    echo "AUTH_SPIKE_WEB_PORT 必须是 1024–65535 的端口号。" >&2
    exit 1
  fi

  auth_spike_web_profile_dir="${AUTH_SPIKE_WEB_PROFILE_DIR:-.dart_tool/supabase-auth-web-profile}"
  if [[ "${auth_spike_web_profile_dir}" != /* ]]; then
    auth_spike_web_profile_dir="$(pwd -P)/${auth_spike_web_profile_dir}"
  fi
  mkdir -p "${auth_spike_web_profile_dir}"

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
    --device-id web-server \
    --browser-name chrome \
    --web-hostname=127.0.0.1 \
    --web-port "${auth_spike_web_port}" \
    --web-browser-flag="--user-data-dir=${auth_spike_web_profile_dir}" \
    --dart-define-from-file "${AUTH_SPIKE_CONFIG}"
else
  # 原生平台可以直接把 integration_test 运行在目标设备上。
  # 默认卸载会让 iOS 删除设备上唯一的开发 App，并连带撤销开发者信任；保留 App
  # 也让多阶段 OTP 探针无需在每次重新构建后手工信任同一张证书。
  flutter test \
    integration_test/supabase_auth_spike_test.dart \
    --device-id "${AUTH_SPIKE_DEVICE}" \
    --no-uninstall \
    --dart-define-from-file "${AUTH_SPIKE_CONFIG}"
fi
