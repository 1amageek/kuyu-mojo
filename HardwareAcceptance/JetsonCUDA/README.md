# Jetson CUDA acceptance

This directory defines the least-privilege WendyOS container used by
`scripts/accept-cuda-canonical-on-jetson.sh`. It is not a standalone build
context: the host script validates a source-complete CUDA handoff and stages it
as `Handoff` beside these files.

The container is pinned to the Linux ARM64 manifest of Modular
`max-nvidia-base:26.5.0`:

```text
index:  sha256:cb38ee4e04da5fb84eb4864b83098afd281f894971111c6ef059b8f8d0a9a5f8
arm64:  sha256:4566cb6f9ff3b51dc71542066f9dc72de27a823ea7b5c4613bd883ad71c1c57e
Mojo:  Mojo 1.0.0 (ed45d567)
CUDA:  13.0
```

The image installs no additional packages from mutable operating-system
repositories. The checked-in Python validator performs the ELF64/AArch64,
embedded PTX, executable digest, CUDA driver-library, and handoff inspections.

Only the Wendy `gpu` entitlement is granted. The container receives no
network, persistence, camera, actuator, host-control, or admin entitlement.
At startup it validates every managed handoff file, compiles the canonical
source natively for `sm_87`, executes all 11 graph differentials, and emits
`native_acceptance=ok` only after every check passes.

Cross-compilation, container build, a visible CUDA library, or a zero process
status alone is not acceptance. The host runner additionally requires WendyOS
`0.18.1`, AArch64, an NVIDIA GPU, and a Jetson Orin device identity before it
deploys this container.

The host admission and receipt paths can be regression-tested without claiming
hardware acceptance:

```bash
HardwareAcceptance/JetsonCUDA/test_host_gate.py \
  --handoff /absolute/path/to/cuda-handoff
```

This fixture exercises the exact production host runner, including accepted,
incomplete-native-evidence, wrong-WendyOS, offline-device, relocatable-object,
and unexpected-handoff-tree outcomes. Its native markers are synthetic and
therefore cannot be used as Jetson evidence.
