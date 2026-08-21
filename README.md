# kuyu-mojo

Portable Mojo compute backends for Kuyu. KuyuPhysics owns canonical dynamics
semantics; this package compiles and executes those programs without defining a
second set of equations.

```text
CanonicalDynamicsProgram
    -> KuyuMojoProgramCompiler
        -> immutable numeric-specific SSA plan
            -> MojoScalarDynamicsExecutor
                -> Mojo Float64 / Float32 CPU execution
```

The current runtime-verified slices are deterministic macOS CPU Float64 and
Float32 execution. Float64 remains the semantic verifier. Float32 establishes
the explicit precision boundary required by Apple Metal and NVIDIA CUDA; it is
not evidence of accelerator execution. Both generated C ABIs are
cross-packaged in one Linux ARM64 static library artifact for native acceptance
on Jetson. Cross-compilation is not native execution evidence. Metal, CUDA,
session-owned device buffers, MAX runtime deployment, and native Jetson
execution require their own capability and runtime acceptance before they
become public runtime paths.

The pinned swift-mojo revision provides schema-1 accelerator runtime receipts,
isolated worker bundles, and a public read-only bundle verifier. KuyuMojoCore's
`MojoAcceleratorWorkerBundlePreflighting` boundary accepts a worker executable
only after the schema, bundle digest, receipt digest, target, managed tree,
loader policy, and executable-relative path pass validation. It does not select
CPU as a fallback. A real MAX Metal object and its four-library AsyncRT/KGEN
closure were linked into exact bundle
`38075467012f877bb5ea23daf3d4639aa175b478bfaca898706bd33e1ff72e77`,
freshly verified, relocated, and executed with a minimal process environment.
The worker created a real Apple M4 Max device context. This proves the macOS
runtime deployment boundary, not a Metal compute kernel or Kuyu worker protocol.

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
