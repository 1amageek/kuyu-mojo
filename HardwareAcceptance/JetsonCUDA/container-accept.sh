#!/bin/bash

set -euo pipefail

handoff_root="/opt/kuyu/handoff"
validator="/opt/kuyu/validate_handoff.py"
runtime_output="/tmp/kuyu-canonical-cuda-output.log"
native_executable="/tmp/kuyu-mojo-canonical-cuda"
expected_mojo_version="Mojo 1.0.0 (ed45d567)"

python3 "$validator" \
  --handoff "$handoff_root" \
  --require-cuda-driver

host_architecture="$(uname -m)"
if [[ "$host_architecture" != "aarch64" ]]; then
  echo "native host architecture is not AArch64: $host_architecture" >&2
  exit 70
fi

mojo_version="$(mojo --version)"
if [[ "$mojo_version" != "$expected_mojo_version" ]]; then
  echo "native Mojo version is not accepted: $mojo_version" >&2
  exit 70
fi

mojo build "$handoff_root/CanonicalCUDAAcceptance.mojo" \
  -I "$handoff_root/Mojo" \
  --target-accelerator sm_87 \
  -o "$native_executable"

set +e
"$native_executable" >"$runtime_output" 2>&1
runtime_status=$?
set -e
cat "$runtime_output"
if [[ $runtime_status -ne 0 ]]; then
  echo "native CUDA acceptance executable failed with status $runtime_status" >&2
  exit 70
fi

python3 "$validator" \
  --handoff "$handoff_root" \
  --native-executable "$native_executable" \
  --runtime-output "$runtime_output"

device_model="unavailable"
if [[ -r /proc/device-tree/model ]]; then
  device_model="$(tr -d '\0' </proc/device-tree/model)"
fi

printf 'native_host_architecture=%s\n' "$host_architecture"
printf 'native_device_model=%s\n' "$device_model"
printf 'native_mojo_version=%s\n' "$mojo_version"
printf 'native_cuda_device_execution=ok\n'
printf 'native_acceptance=ok\n'
