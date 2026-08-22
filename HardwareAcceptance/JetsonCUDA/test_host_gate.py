#!/usr/bin/env python3

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


def parsed_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--handoff", required=True, type=pathlib.Path)
    return parser.parse_args()


def load_receipt(output_directory: pathlib.Path) -> dict[str, object]:
    with (output_directory / "NativeAcceptance.json").open(
        encoding="utf-8"
    ) as source:
        receipt = json.load(source)
    if not isinstance(receipt, dict):
        raise AssertionError("native acceptance receipt must be an object")
    return receipt


def invoke_host_gate(
    host_gate: pathlib.Path,
    handoff: pathlib.Path,
    output_directory: pathlib.Path,
    fake_bin: pathlib.Path,
    invocation_log: pathlib.Path,
    mode: str,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
    environment["FAKE_WENDY_MODE"] = mode
    environment["FAKE_WENDY_INVOCATION_LOG"] = str(invocation_log)
    return subprocess.run(
        [str(host_gate), str(handoff), str(output_directory), "test-jetson.local"],
        check=False,
        capture_output=True,
        encoding="utf-8",
        env=environment,
    )


def assert_run_count(invocation_log: pathlib.Path, expected: int) -> None:
    invocations = [
        json.loads(line)
        for line in invocation_log.read_text(encoding="utf-8").splitlines()
    ]
    run_count = sum("run" in invocation for invocation in invocations)
    if run_count != expected:
        raise AssertionError(
            f"expected {expected} Wendy run invocations, observed {run_count}"
        )


def main() -> int:
    arguments = parsed_arguments()
    handoff = arguments.handoff.resolve(strict=True)
    acceptance_directory = pathlib.Path(__file__).resolve().parent
    repository_root = acceptance_directory.parent.parent
    validator = acceptance_directory / "validate_handoff.py"
    host_gate = repository_root / "scripts" / "accept-cuda-canonical-on-jetson.sh"
    fake_wendy = acceptance_directory / "FakeWendy.py"

    subprocess.run(
        [sys.executable, str(validator), "--handoff", str(handoff)],
        check=True,
    )

    with tempfile.TemporaryDirectory(prefix="kuyu-jetson-host-gate-") as temporary:
        root = pathlib.Path(temporary)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        installed_fake = fake_bin / "wendy"
        shutil.copy2(fake_wendy, installed_fake)
        installed_fake.chmod(0o755)

        tampered_handoff = root / "tampered-handoff"
        shutil.copytree(handoff, tampered_handoff)
        (tampered_handoff / "unexpected").mkdir()
        invalid_result = subprocess.run(
            [
                sys.executable,
                str(validator),
                "--handoff",
                str(tampered_handoff),
            ],
            check=False,
            capture_output=True,
            encoding="utf-8",
        )
        if invalid_result.returncode != 70:
            raise AssertionError("validator admitted an extra handoff directory")

        object_as_executable = subprocess.run(
            [
                sys.executable,
                str(validator),
                "--handoff",
                str(handoff),
                "--native-executable",
                str(handoff / "CanonicalCUDAAcceptance.o"),
            ],
            check=False,
            capture_output=True,
            encoding="utf-8",
        )
        if object_as_executable.returncode != 70:
            raise AssertionError("validator admitted a relocatable object as native")

        accepted_log = root / "accepted-invocations.log"
        accepted_output = root / "accepted"
        accepted = invoke_host_gate(
            host_gate,
            handoff,
            accepted_output,
            fake_bin,
            accepted_log,
            "accepted",
        )
        if accepted.returncode != 0:
            raise AssertionError(
                f"accepted host route failed: {accepted.stdout}{accepted.stderr}"
            )
        accepted_receipt = load_receipt(accepted_output)
        if accepted_receipt.get("status") != "accepted":
            raise AssertionError("accepted route did not produce accepted status")
        if accepted_receipt.get("nativeAcceptance") is not True:
            raise AssertionError("accepted route did not record native acceptance")
        assert_run_count(accepted_log, 1)

        incomplete_log = root / "incomplete-invocations.log"
        incomplete_output = root / "incomplete"
        incomplete = invoke_host_gate(
            host_gate,
            handoff,
            incomplete_output,
            fake_bin,
            incomplete_log,
            "missing-native-evidence",
        )
        if incomplete.returncode != 70:
            raise AssertionError("incomplete native evidence was not rejected")
        incomplete_receipt = load_receipt(incomplete_output)
        if incomplete_receipt.get("nativeAcceptance") is not False:
            raise AssertionError("incomplete route claimed native acceptance")
        assert_run_count(incomplete_log, 1)

        rejected_log = root / "rejected-invocations.log"
        rejected_output = root / "rejected"
        rejected = invoke_host_gate(
            host_gate,
            handoff,
            rejected_output,
            fake_bin,
            rejected_log,
            "wrong-os",
        )
        if rejected.returncode != 70:
            raise AssertionError("wrong WendyOS version was not rejected")
        rejected_receipt = load_receipt(rejected_output)
        if rejected_receipt.get("status") != "failed":
            raise AssertionError("rejected route did not produce failed status")
        if rejected_receipt.get("nativeAcceptance") is not False:
            raise AssertionError("rejected route claimed native acceptance")
        assert_run_count(rejected_log, 0)

        offline_log = root / "offline-invocations.log"
        offline_output = root / "offline"
        offline = invoke_host_gate(
            host_gate,
            handoff,
            offline_output,
            fake_bin,
            offline_log,
            "offline",
        )
        if offline.returncode != 70:
            raise AssertionError("offline device route was not rejected")
        offline_receipt = load_receipt(offline_output)
        if offline_receipt.get("status") != "failed":
            raise AssertionError("offline route did not produce failed status")
        if offline_receipt.get("nativeAcceptance") is not False:
            raise AssertionError("offline route claimed native acceptance")
        assert_run_count(offline_log, 0)

    print("jetson_host_gate_test=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
