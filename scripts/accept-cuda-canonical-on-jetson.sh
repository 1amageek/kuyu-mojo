#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <absolute-handoff-directory> <absolute-output-directory> [device-hostname]" >&2
  exit 64
fi

handoff_directory="$1"
output_directory="$2"
device_hostname="${3:-wendyos-valiant-iris.local}"

for required_directory in "$handoff_directory" "$output_directory"; do
  if [[ "$required_directory" != /* || "$required_directory" == "/" ]]; then
    echo "handoff and output directories must be absolute non-root paths" >&2
    exit 64
  fi
done
if [[ ! -d "$handoff_directory" ]]; then
  echo "handoff directory does not exist: $handoff_directory" >&2
  exit 66
fi
if [[ -e "$output_directory" ]]; then
  echo "output directory already exists: $output_directory" >&2
  exit 73
fi

output_parent="$(dirname "$output_directory")"
if [[ ! -d "$output_parent" || ! -w "$output_parent" ]]; then
  echo "output parent must be an existing writable directory: $output_parent" >&2
  exit 73
fi
if [[ -z "$device_hostname" || "$device_hostname" == *[[:space:]]* ]]; then
  echo "device hostname must be a non-empty token" >&2
  exit 64
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "required command is unavailable: python3" >&2
  exit 69
fi
wendy_executable="$(command -v wendy || true)"
if [[ -z "$wendy_executable" || ! -x "$wendy_executable" ]]; then
  echo "required command is unavailable: wendy" >&2
  exit 69
fi
wendy_executable="$(python3 - "$wendy_executable" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).resolve(strict=True))
PY
)"
wendy_executable_sha256="$(shasum -a 256 "$wendy_executable" | awk '{ print $1 }')"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
acceptance_source="$repository_root/HardwareAcceptance/JetsonCUDA"
validator="$acceptance_source/validate_handoff.py"
timeout_runner="$repository_root/../scripts/run-with-process-group-timeout.py"

python3 "$validator" --handoff "$handoff_directory"

working_directory="$(mktemp -d "$output_parent/.kuyu-jetson-acceptance.XXXXXX")"
trap 'rm -rf "$working_directory"' EXIT
artifact_directory="$working_directory/artifact"
build_context="$working_directory/context"
device_info="$artifact_directory/DeviceInfo.json"
run_log="$artifact_directory/ContainerRun.log"
native_receipt="$artifact_directory/NativeAcceptance.json"
mkdir -p "$artifact_directory" "$build_context"

cp "$handoff_directory/CrossCompileEvidence.json" \
  "$artifact_directory/CrossCompileEvidence.json"
cp "$acceptance_source/Dockerfile" "$build_context/Dockerfile"
cp "$acceptance_source/wendy.json" "$build_context/wendy.json"
cp "$acceptance_source/container-accept.sh" "$build_context/container-accept.sh"
cp "$validator" "$build_context/validate_handoff.py"
cp -R "$handoff_directory" "$build_context/Handoff"

wendy_version="$("$wendy_executable" --version)"

write_receipt() {
  local status="$1"
  local failure_reason="$2"
  python3 - \
    "$status" \
    "$failure_reason" \
    "$device_hostname" \
    "$wendy_version" \
    "$wendy_executable_sha256" \
    "$device_info" \
    "$run_log" \
    "$artifact_directory/CrossCompileEvidence.json" \
    "$native_receipt" <<'PY'
import datetime
import hashlib
import json
import pathlib
import sys


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


status = sys.argv[1]
failure_reason = sys.argv[2]
device_hostname = sys.argv[3]
wendy_version = sys.argv[4]
wendy_executable_sha256 = sys.argv[5]
device_info_path = pathlib.Path(sys.argv[6])
run_log_path = pathlib.Path(sys.argv[7])
cross_evidence_path = pathlib.Path(sys.argv[8])
receipt_path = pathlib.Path(sys.argv[9])

device_info = {}
if device_info_path.is_file():
    try:
        decoded = json.loads(device_info_path.read_text(encoding="utf-8"))
        if isinstance(decoded, dict):
            device_info = decoded
    except (OSError, UnicodeError, json.JSONDecodeError):
        pass

if not run_log_path.exists():
    run_log_path.touch()
run_log_lines = run_log_path.read_text(
    encoding="utf-8", errors="replace"
).splitlines()
runtime_markers = {}
for line in run_log_lines:
    if not line.startswith("native_") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    runtime_markers[key] = value

receipt = {
    "container": {
        "imageIndexSHA256": "cb38ee4e04da5fb84eb4864b83098afd281f894971111c6ef059b8f8d0a9a5f8",
        "linuxARM64ManifestSHA256": "4566cb6f9ff3b51dc71542066f9dc72de27a823ea7b5c4613bd883ad71c1c57e",
        "mojoVersion": "Mojo 1.0.0 (ed45d567)",
    },
    "crossCompileEvidenceSHA256": sha256(cross_evidence_path),
    "device": {
        "agentVersion": device_info.get("version"),
        "cpuArchitecture": device_info.get("cpuArchitecture"),
        "deviceType": device_info.get("deviceType"),
        "gpuVendor": device_info.get("gpuVendor"),
        "hostname": device_hostname,
        "jetpackVersion": device_info.get("jetpackVersion"),
        "os": device_info.get("os"),
        "osVersion": device_info.get("osVersion"),
    },
    "nativeAcceptance": status == "accepted",
    "observedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "runLog": {
        "byteCount": run_log_path.stat().st_size,
        "sha256": sha256(run_log_path),
    },
    "runtimeMarkers": runtime_markers,
    "schemaVersion": 1,
    "status": status,
    "wendyCLI": {
        "executableSHA256": wendy_executable_sha256,
        "version": wendy_version,
    },
}
if failure_reason:
    receipt["failureReason"] = failure_reason
with receipt_path.open("x", encoding="utf-8") as destination:
    json.dump(receipt, destination, indent=2, sort_keys=True)
    destination.write("\n")
PY
}

publish_and_exit() {
  local status="$1"
  local failure_reason="$2"
  local exit_status="$3"
  write_receipt "$status" "$failure_reason"
  mv "$artifact_directory" "$output_directory"
  printf 'jetson_acceptance_status=%s\n' "$status"
  printf 'jetson_acceptance_evidence=%s\n' "$output_directory"
  exit "$exit_status"
}

set +e
python3 "$timeout_runner" --timeout 20 \
  "$wendy_executable" --json --device "$device_hostname" device info \
  >"$device_info" 2>"$run_log"
device_info_status=$?
set -e
if [[ $device_info_status -ne 0 ]]; then
  publish_and_exit \
    "failed" \
    "device info failed or timed out with status $device_info_status" \
    70
fi

set +e
python3 - "$device_info" >>"$run_log" 2>&1 <<'PY'
import json
import pathlib
import sys


path = pathlib.Path(sys.argv[1])
try:
    device = json.loads(path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    print(f"device admission failed: unreadable device info: {error}")
    raise SystemExit(70)

os_version = device.get("osVersion")
if isinstance(os_version, str) and os_version.startswith("WendyOS-"):
    os_version = os_version.removeprefix("WendyOS-")
if os_version != "0.18.1":
    print(f"device admission failed: WendyOS 0.18.1 required, observed {os_version!r}")
    raise SystemExit(70)

architecture = str(device.get("cpuArchitecture", "")).lower()
if architecture not in {"arm64", "aarch64"}:
    print(f"device admission failed: AArch64 required, observed {architecture!r}")
    raise SystemExit(70)

gpu_vendor = str(device.get("gpuVendor", "")).lower()
if gpu_vendor != "nvidia":
    print(f"device admission failed: NVIDIA GPU required, observed {gpu_vendor!r}")
    raise SystemExit(70)

device_type = str(device.get("deviceType", "")).lower()
if "jetson" not in device_type or "orin" not in device_type:
    print(f"device admission failed: Jetson Orin required, observed {device_type!r}")
    raise SystemExit(70)

print("device_admission=ok")
PY
device_admission_status=$?
set -e
if [[ $device_admission_status -ne 0 ]]; then
  publish_and_exit "failed" "device identity admission failed" 70
fi

set +e
python3 "$timeout_runner" --timeout 1800 \
  "$wendy_executable" --device "$device_hostname" run \
  --prefix "$build_context" \
  --build-type docker \
  --builder docker \
  --dockerfile Dockerfile \
  --no-restart \
  2>&1 | tee -a "$run_log"
wendy_run_status=${PIPESTATUS[0]}
set -e
if [[ $wendy_run_status -ne 0 ]]; then
  publish_and_exit \
    "failed" \
    "Wendy build, deploy, or container execution failed with status $wendy_run_status" \
    70
fi

set +e
python3 "$validator" \
  --handoff "$handoff_directory" \
  --runtime-output "$run_log" \
  >>"$run_log" 2>&1
runtime_validation_status=$?
set -e
if [[ $runtime_validation_status -ne 0 ]]; then
  publish_and_exit "failed" "native runtime output validation failed" 70
fi
required_native_markers=(
  "native_host_architecture=aarch64"
  "native_mojo_version=Mojo 1.0.0 (ed45d567)"
  "native_cuda_driver_library=ok"
  "native_cuda_device_execution=ok"
  "native_acceptance=ok"
)
for required_native_marker in "${required_native_markers[@]}"; do
  if [[ "$(grep -Fxc "$required_native_marker" "$run_log")" -ne 1 ]]; then
    publish_and_exit \
      "failed" \
      "native terminal marker is missing or duplicated: $required_native_marker" \
      70
  fi
done
required_native_patterns=(
  '^native_device_model=.+$'
  '^native_executable_sha256=[0-9a-f]{64}$'
  '^native_embedded_ptx_targets=sm_[0-9]+(,sm_[0-9]+)*$'
)
for required_native_pattern in "${required_native_patterns[@]}"; do
  if [[ "$(grep -Ec "$required_native_pattern" "$run_log")" -ne 1 ]]; then
    publish_and_exit \
      "failed" \
      "native evidence marker is missing, malformed, or duplicated: $required_native_pattern" \
      70
  fi
done

publish_and_exit "accepted" "" 0
