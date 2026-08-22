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
                    -> Apple target artifact (native accepted)
                    -> Jetson target handoff (cross-compiled)
```

The current runtime-verified slices include deterministic macOS CPU Float64 and
Float32 execution and bounded Apple M4 Metal Float32 execution of the same
canonical SSA plans. Float64 remains the semantic verifier. Float32 establishes
the explicit precision boundary required by Apple Metal and NVIDIA CUDA. The
backend-neutral acceptance generator compiles the reference program once for
CPU and accelerator identities, proves that all graph plans and bindings are
identical, and then compares all outputs of nine force graphs, the derivative
graph, and the observable graph for two scenarios. Kuyu passes only the
`accelerator` class; the prepared Mojo artifact owns Metal, CUDA, or another
concrete target identity. One GPU thread owns each
graph instance; plan and runtime input storage are transferred separately, and
host-visible results are read only after explicit synchronization.

`MojoScalarDynamicsExecutor` also conforms directly to KuyuPhysics'
`ReferenceQuadrotorCanonicalExecuting` boundary. The production
`ReferenceQuadrotorPlantEngine` and `IMU6SensorField` accept that executor as a
single retained dependency. Integration tests advance the real plant for eight
RK4 ticks and sample the real IMU through both Mojo Float64 and Float32, compare
every state and sensor channel against the Swift scalar oracle, and exercise no
fallback branch.

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

The pinned swift-mojo revision provides schema-3 callable runtime-library
bundles and a public read-only verifier. KuyuMojoCore's
`MojoAcceleratorRuntimeBundlePreflighting` boundary admits a library only after
the schema, bundle and receipt digests, target, module, input graph, generated
header, managed tree, loader policy, and the typed session-factory/execution
binding relationship pass validation. `KuyuMojoAcceleratorRuntime` then loads
only the verified dylib, checks its static ABI, graph identity, and binding IDs,
and retains the loader image for every session borrow. One factory may own an
ordered set of named execution bindings; the first remains the default for
single-operation bundles, while unknown names and duplicate names or binding
IDs fail without selecting another operation or CPU fallback. The generated
Metal session library and its exact four-library
AsyncRT/KGEN closure produce receipt
`3969ad6b6d12dd2416aa745bdc4037ad2faba85bd24b34d0abd3d5eb1c8be747`
and bundle
`2e89bda4bc15fb935f5df9cb1a43f029336653ef095bea62d60076dbb3d84f99`.
Fresh verification plus an `env -i` probe and the Swift loader execute repeated
canonical graph calls through one persistent Apple M4 Metal session, followed
by ordered session and library shutdown.

`KuyuMojoTrainingRuntime` composes that backend-owned verification with
`KuyuTrainingRuntime`'s generic executable-bundle contract. A
`MojoTrainingWorkerBundleLayout` keeps the real Kuyu worker executable outside
the nested accelerator runtime. `MojoTrainingWorkerBundlePreflight` returns the
outer Kuyu worker as the executable source while independently re-verifying the
nested runtime on both source and attempt-owned staged roots. The generic
stager hashes and makes the complete outer tree read-only. A process test places
`/usr/bin/true` at the Kuyu worker path and non-executable bytes at the nested
accelerator-library path; the generic launcher reaches only the former and
reports its zero exit before the expected missing-outcome failure. A real-bundle
test also re-verifies the schema-3 library after it is copied into the
attempt-owned staged tree. Progress, cancellation, result publication, and
worker crash recovery remain separate acceptance gates.

`KuyuManasMojoAdapter` is the sole typed conversion boundary from persisted
KuyuDataset v7 artifacts to Manas-owned in-memory learning contracts. It uses
KuyuTraining's bounded snapshot reader and digest validation, recomputes exact
on-policy distribution evidence including transform Jacobians, applies an
injected `ManasLearningInputEncoding`, enforces transition and complete Float
scalar budgets, and returns an immutable validated `ManasOnPolicyTrajectory`.
The exact verifier is owned by the adapter and cannot be replaced by a caller.
The direct-coordinate encoder requires explicit contract digests and rejects
lossy `Double`-to-`Float` conversion. The same target provides
`KuyuManasMojoAdamOptimizerSessionFactory`, which admits only a digest-verified
accelerator bundle whose ordered operation set exactly matches Manas' public
Adam ABI. It always requests the backend-neutral `.accelerator` device class;
the verified artifact carries the concrete deployment target. Its transport
owns the dynamic session and library, routes opaque
Float32 payloads without interpreting them, and shuts down the session before
the runtime. Manas continues to own payload validation, proposal identity,
transactional commit/discard, and checkpoint semantics. This target imports
neither MLX nor MAX and does not own dataset persistence, model structure,
worker snapshots, or model-store gates.

The Manas-owned device implementation has now passed the first real optimizer
accelerator gate. Verified Apple deployment bundle
`daaaaaa311e3a61729ff11368f71c0b95fd0f97273c73069f9c81e03661df161`
was dynamically loaded through this adapter on Apple M4. One persistent Mojo
session matched the static CPU session after proposal discard and three
proposal/commit cycles, including directions, metrics, parameters, both moment
vectors, and update count. This proves semantic accelerator execution on the
Apple deployment for the Adam slice; it does not prove the complete Mojo RL
backend, production cutover, sustained performance, or native Jetson execution.

The numerical and failure gates are defined in `PARITY_CONTRACT.md`, with
executed results in `RELIABILITY_EVIDENCE.md`. The
runtime identity binds the canonical program schema and digest to the executor
version, numeric type, CPU device class, fidelity/projection declaration,
control semantics, and mixer/spin convention.

The final Metal/CUDA worker, MAX runtime deployment, ownership, and native
acceptance contracts are defined in `ACCELERATOR_ARCHITECTURE.md`.
