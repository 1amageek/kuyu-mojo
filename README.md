# kuyu-mojo

Portable Mojo compute backends for Kuyu. KuyuPhysics owns canonical dynamics
semantics; this package compiles and executes those programs without defining a
second set of equations.

```text
CanonicalDynamicsProgram
    -> KuyuMojoProgramCompiler
        -> immutable Float64 SSA plan
            -> MojoScalarDynamicsExecutor
```

The current verified slice is deterministic macOS CPU Float64 execution.
Metal, CUDA, session-owned device buffers, and native Jetson execution require
their own capability and runtime acceptance before they become public runtime
paths.

The numerical and failure gates are defined in `PARITY_CONTRACT.md`, with
executed results in `RELIABILITY_EVIDENCE.md`. The
runtime identity binds the canonical program schema and digest to the executor
version, Float64 CPU device class, fidelity/projection declaration, control
semantics, and mixer/spin convention.
