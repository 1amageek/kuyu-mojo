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

The pinned swift-mojo revision now provides a separate schema-1 accelerator
runtime receipt. A real MAX Metal object and its four-library AsyncRT/KGEN
closure have passed receipt preparation and fresh re-inspection. This proves
the dependency identity and fail-closed preflight layer; it does not yet create,
link, or execute the isolated worker.

The numerical and failure gates are defined in `PARITY_CONTRACT.md`, with
executed results in `RELIABILITY_EVIDENCE.md`. The
runtime identity binds the canonical program schema and digest to the executor
version, numeric type, CPU device class, fidelity/projection declaration,
control semantics, and mixer/spin convention.

The final Metal/CUDA worker, MAX runtime deployment, ownership, and native
acceptance contracts are defined in `ACCELERATOR_ARCHITECTURE.md`.
