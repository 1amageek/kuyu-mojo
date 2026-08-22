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
                -> Mojo Metal acceptance executor
```

The current runtime-verified slices include deterministic macOS CPU Float64 and
Float32 execution and bounded Apple M4 Metal Float32 execution of the same
canonical SSA plans. Float64 remains the semantic verifier. Float32 establishes
the explicit precision boundary required by Apple Metal and NVIDIA CUDA. The
Metal acceptance generator compiles the reference program once for CPU and
Metal identities, proves that all graph plans and bindings are identical, and
then compares all outputs of nine force graphs, the derivative graph, and the
observable graph for two scenarios. One GPU thread owns each graph instance;
plan and runtime input storage are transferred separately, and host-visible
results are read only after explicit synchronization.

The canonical acceptance executable is an evidence tool, not the public Kuyu
runtime executor or training worker. It creates a bounded device context for
each acceptance call and deliberately omits worker lifecycle, cancellation,
progress, performance qualification, and artifact publication. Those concerns
remain at the attempt-owned worker boundary. Both generated C ABIs are still
cross-packaged in one Linux ARM64 static library artifact for native acceptance
on Jetson. Cross-compilation is not native execution evidence; CUDA and native
Jetson `sm_87` execution retain separate acceptance gates.

The pinned swift-mojo revision provides schema-1 accelerator runtime receipts,
isolated worker bundles, and a public read-only bundle verifier. KuyuMojoCore's
`MojoAcceleratorWorkerBundlePreflighting` boundary accepts a worker executable
only after the schema, bundle digest, receipt digest, target, managed tree,
loader policy, and executable-relative path pass validation. It does not select
CPU as a fallback. The canonical Metal object and its exact four-library
AsyncRT/KGEN closure reproducibly produce receipt
`5e3ea40d3236289a757e6d063cbe8a2f8bde406cb82537c8338610b81283a6ab`
and bundle
`0159c5a65dc14324bcbb5c09b2208857feb242d431df79a420d578d6a8837303`.
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
