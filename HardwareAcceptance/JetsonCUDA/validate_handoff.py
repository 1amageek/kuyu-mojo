#!/usr/bin/env python3

import argparse
import ctypes
import hashlib
import json
import pathlib
import re
import sys


EXPECTED_CANONICAL_PROGRAM_DIGEST = (
    "6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310"
)
EXPECTED_EVIDENCE_SHA256 = (
    "97f7af7bce2edfb409b7ea8a9b9afad7bb2e2d5b2fcbb624444cba1bf52ac64c"
)
EXPECTED_MODULE_CLOSURE_SHA256 = (
    "8ddf1b9ec3b446c50452ad5c0213415db9025cf7361853eb9754819497a71164"
)
EXPECTED_OBJECT_SHA256 = (
    "ef696d6dbc8dfe42af2374e828e98b252d8d67471c3c158554e27a4622723b1b"
)
EXPECTED_SOURCE_SHA256 = (
    "3467e04cd3b032d750de6825c8e0242d4f276ce78eb3b2dbb5960c170a635433"
)
EXPECTED_MOJO_VERSION = "Mojo 1.0.0 (ed45d567)"
EXPECTED_GRAPHS = (
    "reference_quadrotor_gravity",
    "reference_quadrotor_propulsion",
    "reference_quadrotor_thrust_density_scaling",
    "reference_quadrotor_disturbance",
    "reference_quadrotor_aerodynamic_drag",
    "reference_quadrotor_aerodynamic_lift",
    "reference_quadrotor_buoyancy",
    "reference_quadrotor_angular_drag",
    "reference_quadrotor_gyroscopic",
    "reference_quadrotor_derivative",
    "reference_quadrotor_observables",
)


class ValidationError(Exception):
    pass


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validated_relative_path(raw_path: object) -> pathlib.PurePosixPath:
    if not isinstance(raw_path, str):
        raise ValidationError("module path must be a string")
    path = pathlib.PurePosixPath(raw_path)
    if (
        path.is_absolute()
        or ".." in path.parts
        or path.parts[:2] != ("Mojo", "KuyuCanonicalDynamics")
    ):
        raise ValidationError(f"unsafe module path: {raw_path}")
    return path


def validated_handoff(root: pathlib.Path) -> dict[str, object]:
    if not root.is_dir() or root.is_symlink():
        raise ValidationError("handoff root must be a non-symbolic-link directory")

    observed_paths = list(root.rglob("*"))
    for path in observed_paths:
        if path.is_symlink():
            raise ValidationError(f"handoff contains a symbolic link: {path}")
        if not path.is_file() and not path.is_dir():
            raise ValidationError(f"handoff contains a special file: {path}")

    evidence_path = root / "CrossCompileEvidence.json"
    if not evidence_path.is_file():
        raise ValidationError("cross-compile evidence is missing")
    if sha256(evidence_path) != EXPECTED_EVIDENCE_SHA256:
        raise ValidationError("cross-compile evidence digest is not accepted")

    try:
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValidationError(f"cross-compile evidence is unreadable: {error}") from error
    if not isinstance(evidence, dict):
        raise ValidationError("cross-compile evidence root must be an object")

    if evidence.get("schemaVersion") != 1:
        raise ValidationError("unsupported cross-compile evidence schema")
    if evidence.get("artifactStatus") != "crossCompiledOnly":
        raise ValidationError("handoff artifact status is not crossCompiledOnly")
    if evidence.get("nativeAcceptance") is not False:
        raise ValidationError("handoff must not claim native acceptance")
    if evidence.get("canonicalProgramDigest") != EXPECTED_CANONICAL_PROGRAM_DIGEST:
        raise ValidationError("canonical program digest is not accepted")
    if evidence.get("cliTarget") != {
        "accelerator": "sm_87",
        "cpu": "cortex-a78ae",
        "triple": "aarch64-unknown-linux-gnu",
    }:
        raise ValidationError("cross-compile target identity is not accepted")
    if evidence.get("embeddedPTX") != {"target": "sm_80", "version": "8.1"}:
        raise ValidationError("embedded PTX identity is not accepted")

    toolchain = evidence.get("toolchain")
    if not isinstance(toolchain, dict):
        raise ValidationError("toolchain identity is missing")
    if toolchain.get("mojoVersion") != EXPECTED_MOJO_VERSION:
        raise ValidationError("Mojo toolchain version is not accepted")

    files = evidence.get("files")
    if not isinstance(files, dict):
        raise ValidationError("handoff file evidence is missing")
    expected_managed_paths = {"CrossCompileEvidence.json"}
    for role, filename, expected_digest in (
        ("source", "CanonicalCUDAAcceptance.mojo", EXPECTED_SOURCE_SHA256),
        ("object", "CanonicalCUDAAcceptance.o", EXPECTED_OBJECT_SHA256),
    ):
        record = files.get(role)
        if not isinstance(record, dict) or record.get("name") != filename:
            raise ValidationError(f"{role} evidence is invalid")
        path = root / filename
        if not path.is_file():
            raise ValidationError(f"{role} file is missing")
        if record.get("byteCount") != path.stat().st_size:
            raise ValidationError(f"{role} byte count does not match")
        actual_digest = sha256(path)
        if record.get("sha256") != actual_digest or actual_digest != expected_digest:
            raise ValidationError(f"{role} digest is not accepted")
        expected_managed_paths.add(filename)

    module_closure = evidence.get("moduleClosure")
    if not isinstance(module_closure, dict):
        raise ValidationError("module closure evidence is missing")
    module_records = module_closure.get("files")
    if not isinstance(module_records, list) or not module_records:
        raise ValidationError("module closure file list is empty")

    module_digest = hashlib.sha256()
    observed_module_paths: set[str] = set()
    for record in module_records:
        if not isinstance(record, dict):
            raise ValidationError("module file evidence must be an object")
        relative_path = validated_relative_path(record.get("path"))
        normalized_path = relative_path.as_posix()
        if normalized_path in observed_module_paths:
            raise ValidationError(f"duplicate module path: {normalized_path}")
        observed_module_paths.add(normalized_path)
        path = root.joinpath(*relative_path.parts)
        if not path.is_file():
            raise ValidationError(f"module file is missing: {normalized_path}")
        contents = path.read_bytes()
        if record.get("byteCount") != len(contents):
            raise ValidationError(f"module byte count does not match: {normalized_path}")
        actual_digest = hashlib.sha256(contents).hexdigest()
        if record.get("sha256") != actual_digest:
            raise ValidationError(f"module digest does not match: {normalized_path}")
        module_digest.update(normalized_path.encode("utf-8"))
        module_digest.update(b"\0")
        module_digest.update(contents)
        module_digest.update(b"\0")
        expected_managed_paths.add(normalized_path)

    required_module_paths = {
        "Mojo/KuyuCanonicalDynamics/__init__.mojo",
        "Mojo/KuyuCanonicalDynamics/accelerator.mojo",
    }
    if not required_module_paths.issubset(observed_module_paths):
        raise ValidationError("required canonical module files are missing")
    actual_module_digest = module_digest.hexdigest()
    if (
        module_closure.get("sha256") != actual_module_digest
        or actual_module_digest != EXPECTED_MODULE_CLOSURE_SHA256
    ):
        raise ValidationError("module closure digest is not accepted")

    actual_managed_paths = {
        path.relative_to(root).as_posix()
        for path in observed_paths
        if path.is_file()
    }
    if actual_managed_paths != expected_managed_paths:
        unexpected = sorted(actual_managed_paths - expected_managed_paths)
        missing = sorted(expected_managed_paths - actual_managed_paths)
        raise ValidationError(
            f"handoff managed tree mismatch; unexpected={unexpected}, missing={missing}"
        )

    expected_directories = set()
    for managed_path in expected_managed_paths:
        parent = pathlib.PurePosixPath(managed_path).parent
        while parent != pathlib.PurePosixPath("."):
            expected_directories.add(parent.as_posix())
            parent = parent.parent
    actual_directories = {
        path.relative_to(root).as_posix()
        for path in observed_paths
        if path.is_dir()
    }
    if actual_directories != expected_directories:
        unexpected = sorted(actual_directories - expected_directories)
        missing = sorted(expected_directories - actual_directories)
        raise ValidationError(
            f"handoff directory tree mismatch; unexpected={unexpected}, missing={missing}"
        )
    return evidence


def validate_runtime_output(path: pathlib.Path) -> None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise ValidationError(f"runtime output is unreadable: {error}") from error

    graph_lines = [line for line in lines if line.startswith("canonical_graph=")]
    expected_graph_lines = [
        f"canonical_graph={graph} batches=2 ok" for graph in EXPECTED_GRAPHS
    ]
    if graph_lines != expected_graph_lines:
        raise ValidationError("runtime canonical graph results are incomplete or reordered")

    required_lines = (
        f"canonical_program_digest={EXPECTED_CANONICAL_PROGRAM_DIGEST}",
        "canonical_graph_count=11",
        "canonical_accelerator_device=cuda",
        "canonical_accelerator_differential=ok",
    )
    for required_line in required_lines:
        if lines.count(required_line) != 1:
            raise ValidationError(f"runtime marker is missing or duplicated: {required_line}")


def validate_cuda_driver_library() -> None:
    try:
        ctypes.CDLL("libcuda.so.1")
    except OSError as error:
        raise ValidationError(
            f"CUDA driver library is unavailable: {error}"
        ) from error


def validated_native_executable(path: pathlib.Path) -> tuple[str, list[str]]:
    try:
        contents = path.read_bytes()
    except OSError as error:
        raise ValidationError(f"native executable is unreadable: {error}") from error

    if len(contents) < 20 or contents[:4] != b"\x7fELF":
        raise ValidationError("native executable is not an ELF file")
    if contents[4] != 2 or contents[5] != 1:
        raise ValidationError("native executable is not little-endian ELF64")
    elf_type = int.from_bytes(contents[16:18], byteorder="little")
    if elf_type not in {2, 3}:
        raise ValidationError("native ELF is not an executable or PIE")
    machine = int.from_bytes(contents[18:20], byteorder="little")
    if machine != 183:
        raise ValidationError("native ELF does not declare AArch64")

    ptx_targets = sorted(
        {
            match.decode("ascii")
            for match in re.findall(rb"\.target[ \t]+(sm_[0-9]+)", contents)
        }
    )
    if not ptx_targets:
        raise ValidationError("native executable does not expose embedded PTX metadata")
    return hashlib.sha256(contents).hexdigest(), ptx_targets


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--handoff", required=True, type=pathlib.Path)
    parser.add_argument("--native-executable", type=pathlib.Path)
    parser.add_argument("--require-cuda-driver", action="store_true")
    parser.add_argument("--runtime-output", type=pathlib.Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        validated_handoff(arguments.handoff)
        print("handoff_validation=ok")
        if arguments.runtime_output is not None:
            validate_runtime_output(arguments.runtime_output)
            print("runtime_output_validation=ok")
        if arguments.require_cuda_driver:
            validate_cuda_driver_library()
            print("native_cuda_driver_library=ok")
        if arguments.native_executable is not None:
            executable_digest, ptx_targets = validated_native_executable(
                arguments.native_executable
            )
            print(f"native_executable_sha256={executable_digest}")
            print(f"native_embedded_ptx_targets={','.join(ptx_targets)}")
    except (OSError, ValidationError) as error:
        print(f"validation_error={error}", file=sys.stderr)
        return 70
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
