#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"
cd "${repository_root}"

if [[ "${1:-}" != '--session' ]]; then
  [[ "$(uname -s)" == Linux ]] || { echo 'Linux native runtime is required.' >&2; exit 1; }
  probe_directory="$(mktemp -d /tmp/tongxingzhe-linux-no-keyring.XXXXXXXX)"
  cleanup_files() {
    local status=$? log_file
    trap - EXIT
    if [[ "${status}" -ne 0 ]]; then
      for log_file in "${probe_directory}/build.log" "${probe_directory}/app.log"; do
        if [[ -f "${log_file}" ]]; then
          echo "Synthetic probe diagnostic: $(basename "${log_file}") (last 40 lines)" >&2
          tail -n 40 "${log_file}" >&2
        fi
      done
    fi
    rm -rf -- "${probe_directory}"
    exit "${status}"
  }
  trap cleanup_files EXIT
  trap 'exit 1' HUP INT TERM
  commit="$(git rev-parse HEAD)"
  flutter_version="$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')"
  [[ "${flutter_version}" == '3.44.2' ]] || { echo 'Flutter 3.44.2 is required.' >&2; exit 1; }
  run_id="7bs-linux-no-keyring-${commit:0:12}"
  os_version="Linux $(uname -r)"
  timeout --kill-after=5s 600s flutter build linux --debug --no-pub \
    -t tool/offline_pii_runtime_probe.dart \
    --dart-define="OFFLINE_PII_PROBE_COMMIT=${commit}" \
    --dart-define="OFFLINE_PII_PROBE_RUN_ID=${run_id}" \
    --dart-define="OFFLINE_PII_PROBE_FLUTTER_VERSION=${flutter_version}" \
    --dart-define="OFFLINE_PII_PROBE_OS_VERSION=${os_version}" \
    --dart-define=OFFLINE_PII_PROBE_ENVIRONMENT=native-host \
    --dart-define=OFFLINE_PII_PROBE_SIGNING=not-applicable \
    >"${probe_directory}/build.log" 2>&1
  case "$(uname -m)" in
    x86_64) bundle='build/linux/x64/debug/bundle' ;;
    aarch64|arm64) bundle='build/linux/arm64/debug/bundle' ;;
    *) echo 'Unsupported Linux architecture.' >&2; exit 1 ;;
  esac
  mkdir -p "${probe_directory}"/{data,config,cache,runtime,documents,tmp,config-dirs,data-dirs}
  chmod 700 "${probe_directory}/runtime"
  printf 'XDG_DOCUMENTS_DIR="%s/documents"\n' "${probe_directory}" \
    >"${probe_directory}/config/user-dirs.dirs"
  # Xvfb owns this DISPLAY and clipboard; never attach to a user's X server.
  timeout --kill-after=5s 90s env \
    XDG_DATA_HOME="${probe_directory}/data" \
    XDG_CONFIG_HOME="${probe_directory}/config" \
    XDG_CACHE_HOME="${probe_directory}/cache" \
    XDG_RUNTIME_DIR="${probe_directory}/runtime" \
    XDG_CONFIG_DIRS="${probe_directory}/config-dirs" \
    XDG_DATA_DIRS="${probe_directory}/data-dirs" \
    TMPDIR="${probe_directory}/tmp" \
    GDK_BACKEND=x11 GSETTINGS_BACKEND=memory GTK_USE_PORTAL=0 \
    NO_AT_BRIDGE=1 LIBGL_ALWAYS_SOFTWARE=1 \
    xvfb-run --auto-servernum --server-args='-screen 0 1280x1200x24 -nolisten tcp' \
    dbus-run-session --config="${script_dir}/fixtures/linux_no_keyring_probe.conf" -- \
    bash "${BASH_SOURCE[0]}" --session "${probe_directory}" \
      "${repository_root}/${bundle}/tongxingzhe_app" \
      "${commit}" "${run_id}" "${flutter_version}" "${os_version}"
  exit
fi

probe_directory="$2"
app_binary="$3"
commit="$4"
run_id="$5"
flutter_version="$6"
os_version="$7"
app_pid=''
cleanup() {
  if [[ -n "${app_pid}" ]]; then
    kill -KILL "${app_pid}" 2>/dev/null || true
    wait "${app_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
command -v xdg-user-dir >/dev/null 2>&1 \
  || { echo 'xdg-user-dir is required to validate the Linux Documents path.' >&2; exit 1; }
[[ "$(xdg-user-dir DOCUMENTS)" == "${probe_directory}/documents" ]] \
  || { echo 'Linux Documents path escaped the isolated probe directory.' >&2; exit 1; }

require_no_keyring() {
  local owner activation status=0
  owner="$(timeout 5s gdbus call --session --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner \
    org.freedesktop.secrets)"
  [[ "${owner}" == '(false,)' ]] || { echo 'Secret Service unexpectedly owns this bus.' >&2; return 1; }
  activation="$(timeout 5s gdbus call --session --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.StartServiceByName \
    org.freedesktop.secrets 0 2>&1)" || status=$?
  [[ "${status}" -ne 0 && "${activation}" == *'org.freedesktop.DBus.Error.ServiceUnknown'* ]] \
    || { echo 'Secret Service activation was not disabled.' >&2; return 1; }
}
require_no_keyring
"${app_binary}" >"${probe_directory}/app.log" 2>&1 &
app_pid=$!
window_id=''
for _ in {1..100}; do
  kill -0 "${app_pid}" 2>/dev/null || { echo 'Native GTK probe exited before evidence.' >&2; exit 1; }
  window_id="$(xdotool search --onlyvisible --pid "${app_pid}" --name '同行者' 2>/dev/null | head -n 1 || true)"
  [[ -z "${window_id}" ]] || break
  sleep 0.2
done
[[ -n "${window_id}" ]] || { echo 'Native GTK probe window did not appear.' >&2; exit 1; }
xdotool windowsize "${window_id}" 1280 1200
xdotool windowfocus --sync "${window_id}"
copied=0
for _ in {1..30}; do
  # Disabled PII actions are skipped by Flutter focus traversal; the existing
  # copy button is reached without coordinates or a new Dart export seam.
  xdotool key Tab space
  sleep 0.2
  if timeout 2s xclip -selection clipboard -out \
    >"${probe_directory}/clipboard.json" 2>/dev/null; then
    if python3 - "${probe_directory}/clipboard.json" "${commit}" "${run_id}" \
      "${flutter_version}" "${os_version}" >"${probe_directory}/evidence.json" 2>/dev/null <<'PY'
import datetime
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    evidence = json.load(source)
assert set(evidence) == {"schemaVersion", "platform", "osVersion", "flutterVersion", "commit", "runId", "environment", "signing", "evidenceClass", "events"}
assert type(evidence["schemaVersion"]) is int and evidence["schemaVersion"] == 1
assert evidence["platform"] == "linux"
assert evidence["commit"] == sys.argv[2]
assert evidence["runId"] == sys.argv[3]
assert evidence["flutterVersion"] == sys.argv[4] == "3.44.2"
assert evidence["osVersion"] == sys.argv[5]
assert evidence["environment"] == "native-host"
assert evidence["signing"] == "not-applicable"
assert evidence["evidenceClass"] == "unsupported"
assert type(evidence["events"]) is list and len(evidence["events"]) == 1
event = evidence["events"][0]
assert set(event) == {"recordedAtUtc", "scenario", "outcome", "evidenceClass", "reason"}
assert event["scenario"] == "platformGate"
assert event["outcome"] == event["evidenceClass"] == "unsupported"
assert event["reason"] == "sensitiveStorageDisabled"
assert type(event["recordedAtUtc"]) is str and event["recordedAtUtc"].endswith("Z")
recorded = datetime.datetime.fromisoformat(event["recordedAtUtc"].replace("Z", "+00:00"))
assert abs((datetime.datetime.now(datetime.timezone.utc) - recorded).total_seconds()) < 120
print(json.dumps(evidence, ensure_ascii=True, sort_keys=True))
PY
    then
      copied=1
      break
    fi
  fi
done
[[ "${copied}" == 1 ]] || { echo 'UI copy did not produce the exact unsupported gate evidence.' >&2; exit 1; }
require_no_keyring
# Drift's real native default is Documents/tongxingzhe_local.sqlite, not the
# application-support path. Check only this run's explicitly configured path.
for database_file in "${probe_directory}/documents/tongxingzhe_local.sqlite"{,-wal,-shm,-journal}; do
  [[ ! -e "${database_file}" ]] || { echo 'Disabled native probe initialized a database.' >&2; exit 1; }
done
cat "${probe_directory}/evidence.json"
