#!/usr/bin/env python3

import json
import os
import pathlib
import sys


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


def record_invocation(arguments: list[str]) -> None:
    log_path = os.environ.get("FAKE_WENDY_INVOCATION_LOG")
    if log_path is None:
        return
    with pathlib.Path(log_path).open("a", encoding="utf-8") as log:
        log.write(json.dumps(arguments))
        log.write("\n")


def device_info(mode: str) -> int:
    if mode == "offline":
        print("device unavailable", file=sys.stderr)
        return 1

    os_version = "0.18.2" if mode == "wrong-os" else "0.18.1"
    print(
        json.dumps(
            {
                "cpuArchitecture": "aarch64",
                "deviceType": "NVIDIA Jetson AGX Orin",
                "gpuVendor": "nvidia",
                "jetpackVersion": "test-fixture",
                "os": "WendyOS",
                "osVersion": os_version,
                "version": "test-agent",
            }
        )
    )
    return 0


def run_acceptance(mode: str) -> int:
    if mode not in {"accepted", "missing-native-evidence"}:
        print(f"unexpected deployment in {mode} mode", file=sys.stderr)
        return 99

    print(
        "canonical_program_digest="
        "6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310"
    )
    for graph in EXPECTED_GRAPHS:
        print(f"canonical_graph={graph} batches=2 ok")
    print("canonical_graph_count=11")
    print("canonical_accelerator_device=accelerator")
    print("canonical_accelerator_differential=ok")
    print("native_host_architecture=aarch64")
    print("native_device_model=NVIDIA Jetson AGX Orin test fixture")
    print("native_mojo_version=Mojo 1.0.0 (ed45d567)")
    if mode == "accepted":
        print("native_executable_sha256=" + "a" * 64)
        print("native_embedded_ptx_targets=sm_87")
    print("native_cuda_driver_library=ok")
    print("native_cuda_device_execution=ok")
    print("native_acceptance=ok")
    return 0


def main() -> int:
    arguments = sys.argv[1:]
    record_invocation(arguments)
    if arguments == ["--version"]:
        print("wendy test fixture")
        return 0

    mode = os.environ.get("FAKE_WENDY_MODE", "accepted")
    if arguments and arguments[0] == "--json" and arguments[-2:] == ["device", "info"]:
        return device_info(mode)
    if "run" in arguments:
        return run_acceptance(mode)

    print(f"unsupported fake Wendy invocation: {arguments}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    raise SystemExit(main())
