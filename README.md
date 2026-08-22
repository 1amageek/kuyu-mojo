# kuyu-mojo

Portable Mojo compute backends for Kuyu. KuyuPhysics owns canonical dynamics
semantics; this package compiles and executes those programs without defining a
second set of equations.

```text
CanonicalDynamicsProgram
    -> KuyuMojoProgramCompiler
        -> immutable numeric-specific SSA plan
            -> Mojo Float64 / Float32 CPU execution
            -> Float32 plan + batched runtime inputs
                -> backend-neutral accelerator acceptance source
                    -> Metal runtime bundle (native accepted)
                    -> CUDA AArch64 handoff (cross-compiled)
```

The current runtime-verified slices include deterministic macOS CPU Float64 and
Float32 execution and bounded Apple M4 Metal Float32 execution of the same
canonical SSA plans. Float64 remains the semantic verifier. Float32 establishes
the explicit precision boundary required by Apple Metal and NVIDIA CUDA. The
backend-neutral acceptance generator compiles the reference program once for
CPU and accelerator identities, proves that all graph plans and bindings are
identical, and then compares all outputs of nine force graphs, the derivative
graph, and the observable graph for two scenarios. One GPU thread owns each
graph instance; plan and runtime input storage are transferred separately, and
host-visible results are read only after explicit synchronization.

The canonical acceptance executable is an evidence tool, not the public Kuyu
runtime executor or training worker. It creates a bounded device context for
each acceptance call and deliberately omits worker lifecycle, cancellation,
progress, performance qualification, and artifact publication. Those concerns
remain at the attempt-owned worker boundary. The CPU ABIs remain packaged in a
Linux ARM64 static library. The CUDA acceptance source is instead preserved as
a digest-bound AArch64 ELF handoff for native acceptance on Jetson.
Cross-compilation is not native execution evidence; native linking, device
execution, and Jetson `sm_87` qualification retain separate acceptance gates.

Prepare that handoff from the pinned Modular pixi workspace with:

```bash
KUYU_MOJO_MAX_PIXI_PROJECT=/absolute/path/to/pixi-workspace \
  scripts/prepare-cuda-canonical-acceptance.sh \
  /absolute/path/to/new-output-directory
```

The output contains `CanonicalCUDAAcceptance.mojo`, its AArch64 ELF object, the
complete imported `Mojo/KuyuCanonicalDynamics` source closure, and
`CrossCompileEvidence.json`. The object is compiled against the copied closure,
not the repository source tree. The evidence records the canonical program,
source, object and module-closure digests, host/CPU/accelerator targets,
embedded PTX identity, Mojo version, and pixi manifest/lock digests. It always
records `artifactStatus: crossCompiledOnly` and `nativeAcceptance: false`; only
native Jetson acceptance may advance those claims.

When an admitted Jetson is reachable, run the native gate with a new evidence
directory:

```bash
scripts/accept-cuda-canonical-on-jetson.sh \
  /absolute/path/to/cuda-handoff \
  /absolute/path/to/new-native-evidence-directory \
  wendyos-valiant-iris.local
```

The host gate validates the handoff before contacting the device, requires
WendyOS `0.18.1`, AArch64, NVIDIA, and Jetson Orin identities, and only then
builds and runs the digest-pinned MAX acceptance container. Both accepted and
post-contact failed attempts preserve device info, the run log, the exact
cross-compile evidence, Wendy CLI identity, and a typed native receipt. An
offline device produces a failed receipt and no deploy; an OS mismatch is
rejected before build or deployment.

The pinned swift-mojo revision provides schema-1 accelerator runtime receipts,
isolated worker bundles, and a public read-only bundle verifier. KuyuMojoCore's
`MojoAcceleratorWorkerBundlePreflighting` boundary accepts a worker executable
only after the schema, bundle digest, receipt digest, target, managed tree,
loader policy, and executable-relative path pass validation. It does not select
CPU as a fallback. The backend-neutral generator's canonical Metal object and
its exact four-library
AsyncRT/KGEN closure reproducibly produce receipt
`6d04ae4e8a0cdc9320316e417ac5a63e2d6d64ea8f02f872f9425de8b16687be`
and bundle
`2c6e4b91593af4db7fc939cfa4c72d1fa534eaf36cd6705f78f3b0c134040ae8`.
Both the original and relocated bundle pass fresh verification and execute all
11 canonical graph checks under `env -i`.

`KuyuMojoTrainingRuntime` bridges that backend-owned verification into
`KuyuTrainingRuntime`'s generic executable-bundle contract. It derives the
generic executable source only from a verified manifest and rechecks that the
requested root, executable-relative path, and resolved executable URL agree on
both source and staged roots. The target does not expose the device-context
probe as a training worker; executable worker-protocol support remains a
separate acceptance gate.

The numerical and failure gates are defined in `PARITY_CONTRACT.md`, with
executed results in `RELIABILITY_EVIDENCE.md`. The
runtime identity binds the canonical program schema and digest to the executor
version, numeric type, CPU device class, fidelity/projection declaration,
control semantics, and mixer/spin convention.

The final Metal/CUDA worker, MAX runtime deployment, ownership, and native
acceptance contracts are defined in `ACCELERATOR_ARCHITECTURE.md`.
