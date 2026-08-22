#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <absolute-output-directory>" >&2
  exit 64
fi

output_directory="$1"
if [[ "$output_directory" != /* || "$output_directory" == "/" ]]; then
  echo "output directory must be an absolute non-root path" >&2
  exit 64
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

max_project="${KUYU_MOJO_MAX_PIXI_PROJECT:-}"
if [[ -z "$max_project" || ! -f "$max_project/pixi.toml" || ! -f "$max_project/pixi.lock" ]]; then
  echo "KUYU_MOJO_MAX_PIXI_PROJECT must name a provisioned pixi workspace" >&2
  exit 78
fi
pixi_manifest="$max_project/pixi.toml"
pixi_lock="$max_project/pixi.lock"

pixi_executable="${KUYU_MOJO_PIXI_EXECUTABLE:-pixi}"
if ! command -v "$pixi_executable" >/dev/null 2>&1; then
  echo "pixi executable is unavailable: $pixi_executable" >&2
  exit 69
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
timeout_runner="$repository_root/../scripts/run-with-process-group-timeout.py"
working_directory="$(mktemp -d "$output_parent/.kuyu-cuda-acceptance.XXXXXX")"
trap 'rm -rf "$working_directory"' EXIT

artifact_directory="$working_directory/artifact"
derived_data="$working_directory/DerivedData"
source_file="$artifact_directory/CanonicalCUDAAcceptance.mojo"
object_file="$artifact_directory/CanonicalCUDAAcceptance.o"
evidence_file="$artifact_directory/CrossCompileEvidence.json"
fixture_executable="$derived_data/Build/Products/Debug/kuyu-mojo-accelerator-acceptance-fixture"
mkdir "$artifact_directory"

env TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault \
  python3 "$timeout_runner" --timeout 120 \
  xcodebuild build \
  -scheme kuyu-mojo-accelerator-acceptance-fixture \
  -destination platform=macOS,arch=arm64 \
  -derivedDataPath "$derived_data" \
  -skipPackagePluginValidation \
  -quiet

if [[ ! -x "$fixture_executable" ]]; then
  echo "canonical accelerator fixture generator was not produced" >&2
  exit 70
fi
LLVM_PROFILE_FILE="$working_directory/default.profraw" \
  "$fixture_executable" cuda "$source_file"

"$pixi_executable" run \
  --manifest-path "$pixi_manifest" \
  --as-is \
  mojo build "$source_file" \
  -I "$repository_root/Mojo" \
  --emit object \
  --target-triple aarch64-unknown-linux-gnu \
  --target-cpu cortex-a78ae \
  --target-accelerator sm_87 \
  -o "$object_file"

file_description="$(file -b "$object_file")"
if [[ "$file_description" != *"ELF 64-bit LSB relocatable, ARM aarch64"* ]]; then
  echo "CUDA acceptance object has an unexpected architecture: $file_description" >&2
  exit 70
fi

undefined_symbols="$(xcrun llvm-nm --undefined-only "$object_file")"
for required_symbol in \
  AsyncRT_DeviceContext_create \
  AsyncRT_DeviceContext_enqueueFunctionDirect \
  AsyncRT_DeviceContext_synchronize \
  KGEN_CompilerRT_AlignedAlloc
do
  if ! grep -Fq "$required_symbol" <<<"$undefined_symbols"; then
    echo "CUDA acceptance object is missing runtime symbol: $required_symbol" >&2
    exit 70
  fi
done

object_strings="$(strings "$object_file")"
for expected_marker in \
  "canonical_program_digest=6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310" \
  "canonical_graph_count=11" \
  "canonical_accelerator_device=cuda" \
  "canonical_accelerator_differential=ok"
do
  if ! grep -Fqx "$expected_marker" <<<"$object_strings"; then
    echo "CUDA acceptance object is missing evidence marker: $expected_marker" >&2
    exit 70
  fi
done

embedded_ptx_version="$(awk '$1 == ".version" { print $2; exit }' <<<"$object_strings")"
embedded_ptx_target="$(awk '$1 == ".target" { print $2; exit }' <<<"$object_strings")"
if [[ -z "$embedded_ptx_version" || -z "$embedded_ptx_target" ]]; then
  echo "CUDA acceptance object does not expose embedded PTX metadata" >&2
  exit 70
fi

mojo_version="$($pixi_executable run \
  --manifest-path "$pixi_manifest" \
  --as-is \
  mojo --version)"

python3 - \
  "$source_file" \
  "$object_file" \
  "$evidence_file" \
  "$pixi_manifest" \
  "$pixi_lock" \
  "$mojo_version" \
  "$file_description" \
  "$embedded_ptx_version" \
  "$embedded_ptx_target" <<'PY'
import hashlib
import json
import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
object_path = pathlib.Path(sys.argv[2])
evidence_path = pathlib.Path(sys.argv[3])
pixi_manifest_path = pathlib.Path(sys.argv[4])
pixi_lock_path = pathlib.Path(sys.argv[5])

def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

evidence = {
    "artifactStatus": "crossCompiledOnly",
    "canonicalProgramDigest": "6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310",
    "cliTarget": {
        "accelerator": "sm_87",
        "cpu": "cortex-a78ae",
        "triple": "aarch64-unknown-linux-gnu",
    },
    "embeddedPTX": {
        "target": sys.argv[9],
        "version": sys.argv[8],
    },
    "files": {
        "object": {
            "byteCount": object_path.stat().st_size,
            "name": object_path.name,
            "sha256": sha256(object_path),
        },
        "source": {
            "byteCount": source_path.stat().st_size,
            "name": source_path.name,
            "sha256": sha256(source_path),
        },
    },
    "format": sys.argv[7],
    "nativeAcceptance": False,
    "schemaVersion": 1,
    "toolchain": {
        "mojoVersion": sys.argv[6].strip(),
        "pixiLockSHA256": sha256(pixi_lock_path),
        "pixiManifestSHA256": sha256(pixi_manifest_path),
    },
}
with evidence_path.open("x", encoding="utf-8") as destination:
    json.dump(evidence, destination, indent=2, sort_keys=True)
    destination.write("\n")
PY

mv "$artifact_directory" "$output_directory"
printf 'prepared_cuda_acceptance=%s\n' "$output_directory"
printf 'embedded_ptx_target=%s\n' "$embedded_ptx_target"
printf 'native_acceptance=false\n'
