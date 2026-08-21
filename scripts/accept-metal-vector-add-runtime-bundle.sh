#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <absolute-output-bundle>" >&2
  exit 64
fi

output_bundle="$1"
if [[ "$output_bundle" != /* || "$output_bundle" == "/" ]]; then
  echo "output bundle must be an absolute non-root path" >&2
  exit 64
fi
if [[ -e "$output_bundle" ]]; then
  echo "output bundle already exists: $output_bundle" >&2
  exit 73
fi

max_project="${KUYU_MOJO_MAX_PIXI_PROJECT:-}"
if [[ -z "$max_project" || ! -f "$max_project/pixi.toml" ]]; then
  echo "KUYU_MOJO_MAX_PIXI_PROJECT must name a provisioned pixi workspace" >&2
  exit 78
fi

pixi_executable="${KUYU_MOJO_PIXI_EXECUTABLE:-pixi}"
if ! command -v "$pixi_executable" >/dev/null 2>&1; then
  echo "pixi executable is unavailable: $pixi_executable" >&2
  exit 69
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
source_file="$repository_root/HardwareAcceptance/MetalVectorAddProbe.mojo"
environment_root="$max_project/.pixi/envs/default"
runtime_libraries=(
  "$environment_root/lib/libAsyncRTMojoBindings.dylib"
  "$environment_root/lib/libAsyncRTRuntimeGlobals.dylib"
  "$environment_root/lib/libKGENCompilerRTShared.dylib"
  "$environment_root/lib/libMSupportGlobals.dylib"
)
for runtime_library in "${runtime_libraries[@]}"; do
  if [[ ! -f "$runtime_library" ]]; then
    echo "required MAX runtime library is unavailable: $runtime_library" >&2
    exit 78
  fi
done

working_directory="$(mktemp -d "${TMPDIR:-/tmp}/kuyu-mojo-metal.XXXXXX")"
trap 'rm -rf "$working_directory"' EXIT
object_file="$working_directory/MetalVectorAddProbe.o"
receipt_file="$working_directory/RuntimeReceipt.json"
executable_name="kuyu-mojo-metal-vector-add"

"$pixi_executable" run \
  --manifest-path "$max_project/pixi.toml" \
  --as-is \
  mojo build "$source_file" \
  --emit object \
  --target-triple arm64-apple-macosx14.0 \
  --target-cpu apple-m4 \
  --target-accelerator metal:4 \
  -o "$object_file"

cd "$repository_root"
runtime_arguments=()
for runtime_library in "${runtime_libraries[@]}"; do
  runtime_arguments+=(--runtime-library "$runtime_library")
done

swift package \
  --disable-sandbox \
  --allow-writing-to-package-directory \
  mojo runtime-prepare \
  --object "$object_file" \
  "${runtime_arguments[@]}" \
  --receipt "$receipt_file" \
  --target-triple arm64-apple-macosx14.0 \
  --target-cpu apple-m4 \
  --target-accelerator metal:4 \
  --format json

swift package \
  --disable-sandbox \
  --allow-writing-to-package-directory \
  mojo runtime-bundle-prepare \
  --object "$object_file" \
  "${runtime_arguments[@]}" \
  --receipt "$receipt_file" \
  --output "$output_bundle" \
  --executable-name "$executable_name" \
  --target-triple arm64-apple-macosx14.0 \
  --target-cpu apple-m4 \
  --target-accelerator metal:4 \
  --format json

swift package \
  --disable-sandbox \
  mojo runtime-bundle-verify \
  --bundle "$output_bundle" \
  --format json

validate_worker_output() {
  local worker_path="$1"
  local worker_output
  worker_output="$(env -i "$worker_path")"
  printf '%s\n' "$worker_output"
  for expected_line in \
    "gpu_kernel_launch=ok" \
    "gpu_transfer=ok" \
    "gpu_synchronization=ok"
  do
    if ! grep -Fqx "$expected_line" <<<"$worker_output"; then
      echo "worker output is missing: $expected_line" >&2
      exit 70
    fi
  done
}

validate_worker_output "$output_bundle/bin/$executable_name"

relocated_bundle="$working_directory/relocated-bundle"
/bin/cp -R "$output_bundle" "$relocated_bundle"
swift package \
  --disable-sandbox \
  mojo runtime-bundle-verify \
  --bundle "$relocated_bundle" \
  --format json
validate_worker_output "$relocated_bundle/bin/$executable_name"

printf 'accepted_bundle=%s\n' "$output_bundle"
