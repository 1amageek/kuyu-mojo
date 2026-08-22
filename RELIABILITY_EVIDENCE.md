# Reliability evidence

## 2026-08-22 canonical Metal dynamics acceptance

| Claim | Evidence | Result |
|---|---|---|
| Accelerator identity does not change canonical structure | `acceleratorCompilationPreservesCanonicalGraphStructure` compares program digest, force-term order, workspace sizes, encoded plans, input bindings, and output bindings for CPU and Metal Float32 compilations | Passed; Metal uses executor version `mojo-accelerator-float32-ssa-v1` and device class `metal` |
| Unsupported accelerator precision cannot silently fall back | `acceleratorCompilationRejectsUnsupportedFloat64` requests Metal and CUDA Float64 compilation | Both reject with `MojoProgramCompilationError.unsupportedNumericType` |
| Plan and runtime storage have an explicit checked boundary | `float32InvocationSeparatesPlanFromRuntimeInput` checks exact plan materialization, runtime element count, workspace size, and rejection of a fractional/corrupt plan boundary | Passed as a typed failure |
| Canonical Metal execution matches the CPU Float32 oracle | `scripts/accept-metal-canonical-runtime-bundle.sh` generates the harness from reference program digest `6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310`; nine force graphs, derivative, and observables execute for a full-dynamics scenario and a zero-boundary scenario | 11/11 graphs × 2 batches passed on Apple M4 Max after device transfer and explicit synchronization |
| The canonical Metal runtime closure is reproducible and relocatable | Two independent runs of the backend-neutral generator produced receipt `6d04ae4e8a0cdc9320316e417ac5a63e2d6d64ea8f02f872f9425de8b16687be` and bundle `2c6e4b91593af4db7fc939cfa4c72d1fa534eaf36cd6705f78f3b0c134040ae8`; each original and relocated executable ran under `env -i` | Passed four executions; executable `bin/kuyu-mojo-metal-canonical`, exact four-library MAX closure, target `arm64-apple-macosx14.0|apple-m4|metal:4` |
| Public Kuyu preflight admits only that exact canonical bundle | Full package test used `KUYU_MOJO_TEST_ACCELERATOR_BUNDLE=/tmp/kuyu-mojo-accelerator-canonical-bundle-v1` and exercised both `KuyuMojoCore` and `KuyuMojoTrainingRuntime` source/relocation checks | 26/26 passed at `/tmp/kuyu-mojo-accelerator-neutral-final.xcresult`, including the strict CPU performance gate |
| The identical canonical fixture cross-compiles for Jetson CUDA | Metal and CUDA generated sources differ only in the declared device label; the CUDA source compiled for `aarch64-unknown-linux-gnu`, `cortex-a78ae`, and CLI accelerator `sm_87` | Produced a 201,528-byte AArch64 ELF object with SHA-256 `ef696d6dbc8dfe42af2374e828e98b252d8d67471c3c158554e27a4622723b1b`; embedded PTX is version 8.1 and targets `sm_80`, so native Jetson link/run and specialization remain open |
| The CUDA cross-compile handoff is deterministic and cannot claim native acceptance | Two independent runs of `scripts/prepare-cuda-canonical-acceptance.sh` compared the complete output trees; rejection checks covered an existing output, a relative output, missing toolchain identity, and an intentional compiler failure | Both successful runs produced source `3467e04cd3b032d750de6825c8e0242d4f276ce78eb3b2dbb5960c170a635433`, object `ef696d6dbc8dfe42af2374e828e98b252d8d67471c3c158554e27a4622723b1b`, and evidence `18184adb85ab850b84dfa2198859e3ac2ba5d28a851aebb09f86f184e893edc9`; evidence fixes `crossCompiledOnly` and `nativeAcceptance: false`, while failure published no partial output and leaked no temporary directory |
| Checked-in CPU ABIs remain source-derived after the shared interpreter refactor | `swift package --disable-sandbox mojo inspect --target KuyuMojoDynamics` on the final generated artifacts | Passed; two synchronous Float32/Float64 bindings, input graph `74ff401f1cdeca4559652bbd8d0aa38562cc264a48e9ce87f247377d50591cea`, aggregate artifact `77490acc7cbecc26b6f77bc1d2f9a5e37d3d36d113291b35aace839048b0d97b` |
| Workspace boundaries and source-risk policy still hold | `validate-kuyu-boundaries.sh`, `validate-unconscious-boundaries.sh`, `audit-dangerous-code.sh --verbose`, the incomplete-implementation scan, and `bash -n` for the acceptance scripts | Passed; zero audit blockers, zero incomplete markers, and 44 pre-existing oversized-file review findings outside this package |

This is a canonical hardware-acceptance slice, not a production accelerator
session. It proves the same encoded Kuyu equations execute on Metal and that the
exact runtime artifact can be admitted and relocated. It does not yet prove an
attempt-owned worker protocol, cancellation/shutdown races, sustained batch
performance, training correctness, native CUDA execution, native Jetson
execution, sanitizer, or HIL qualification.

## 2026-08-21 CPU Float64 and Float32 canonical dynamics

| Claim | Evidence | Result |
|---|---|---|
| Canonical program compilation is deterministic and digest-bound | Two independent compilations of reference digest `6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310` | Passed |
| Mojo force, derivative, and observable traces match the Swift Float64 reference | Float64 and Float32 differential tests for full and single-prop fidelity using the numeric-specific tolerances in `PARITY_CONTRACT.md` | Passed |
| RK4 integration preserves declared projection semantics | Twenty-step full and single-prop traces, including vertical-only projection | Passed |
| Piecewise zero-norm behavior is portable | Zero relative wind and angular velocity fixture | Passed |
| Invalid execution cannot become a success value | Digest mismatch, undeclared fidelity, missing/shape/non-finite input, corrupt header, invalid opcode, division by zero, and non-finite arithmetic tests | Passed |
| Float32 conversion failures remain explicit | dtype mismatch, non-representable constants, non-representable runtime inputs, and non-representable corrupt plans | Passed as typed failures |
| CPU execution meets the current control-loop floor | Strict `KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1` test with 200 timed full RK4 steps per numeric type | Float32 `795.27` steps/s and Float64 `1410.88` steps/s; both passed the 400 steps/s floor |
| The checked-in ABI artifacts match the source graph | `swift package mojo inspect --target KuyuMojoDynamics` | Two bindings; input graph `cb12499884905d9cc48bb634b7f20339e7d502e978fa6a7d1bc78e35607eded8`; aggregate artifact `379d4e137fa359d8c1404ed7e07be4adbb0cc44a58ca3fad3f32c85617859e78` |
| The Linux ARM64 archive contains both compiled Mojo ABIs | `llvm-ar t`, `llvm-nm --undefined-only`, and extraction followed by `file` | Archive `85651efd647c619813cc5359bed719e841bb8871ed6a2731b06965998bedf1d4`; member `Bindings.o`; ELF64 aarch64; Float32 and Float64 call symbols; only unresolved symbol is libc `memset` |
| Linux ELF packaging cannot silently produce an empty archive | `swift-mojo` revision `4a2382cc6e06cd4f5fe9f888474e3fa235a1acc1` archive-member verification and its 167-test suite | Passed |
| Accelerator runtime symbols cannot enter the link-closed CPU artifact | The pinned `swift-mojo` linkage policy rejects undeclared `AsyncRT_*`, `KGEN_CompilerRT_*`, and `MGP_RT_*` symbols before archiving | Passed |
| Accelerator runtime identity is reproducible without ambient dependency search | A real MAX Metal object and `libAsyncRTMojoBindings.dylib`, `libAsyncRTRuntimeGlobals.dylib`, `libKGENCompilerRTShared.dylib`, and `libMSupportGlobals.dylib` produced receipt `050ceac20bc593aed6e36757c050e01a0f0ec7d002bcebb49f3675d77ba4e179` and exact bundle `38075467012f877bb5ea23daf3d4639aa175b478bfaca898706bd33e1ff72e77`; fresh verification rejected ambient dependencies, and relocated minimal-environment execution reported `Accelerator: Apple M4 Max` | Passed for macOS link, loader, and device-context creation; compute kernel and native Jetson pending |
| Repo-owned Metal hardware acceptance performs real compute | `HardwareAcceptance/MetalVectorAddProbe.mojo` launches a `metal:4` Float32 vector-add kernel, transfers two 257-element inputs and one output, synchronizes, and checks every output against the expected value | Passed on Apple M4 Max with `gpu_kernel_launch=ok`, `gpu_transfer=ok`, and `gpu_synchronization=ok` |
| The Metal kernel runtime bundle is reproducible and relocatable | `scripts/accept-metal-vector-add-runtime-bundle.sh` compiled the repo-owned source twice, produced receipt `2bc7264e13acb31f1c0be774cac0b07d5e450d44d552dbfb669dead321b98f50` and bundle `643f18ba4b227ba253e64642fdbfa9de0508d0a85d691d099d0bf846d9bdbf97` both times, freshly verified the managed tree, and executed both original and relocated bundles with an empty environment | Passed; executable `bin/kuyu-mojo-metal-vector-add`, exact four-library MAX closure, target `arm64-apple-macosx14.0|apple-m4|metal:4` |
| Kuyu rejects a runtime bundle whose declared identity changes | Seven focused preflight tests cover exact acceptance, schema/bundle/receipt/target mismatch, invalid requirements, runtime-verifier failure and cancellation preservation, non-file roots, and unsafe executable paths | Passed as typed failures with no fallback |
| Kuyu's public preflight accepts the real relocated runtime bundle | Direct `xctest` with `KUYU_MOJO_TEST_ACCELERATOR_BUNDLE=/tmp/kuyu-runtime-bundle-real-v1` re-inspected the managed tree and returned the verified worker path | Passed in `0.67` seconds; four runtime libraries observed |
| The Mojo verifier composes with Kuyu's generic source/staged executable contract | `KuyuMojoTrainingRuntime` tests reject root, relative-path, and resolved-executable disagreement; the opt-in real-bundle test derives the source contract, relocates the bundle, and verifies the relocated root through the same adapter | 5/5 passed at `/tmp/kuyu-mojo-training-runtime-real-bundle-1.xcresult` |
| Kuyu independently admits the real Metal kernel bundle | `KuyuMojoCore` and `KuyuMojoTrainingRuntime` opt-in tests re-read bundle `643f18ba…`, match receipt `2bc7264e…` and `metal:4`, derive the generic executable source, and verify a relocated copy | 12/12 passed at `/tmp/kuyu-mojo-metal-bundle-preflight-1.xcresult` |
| The new training-runtime adapter preserves package regression | Bounded `xcodebuild test` for the full package after adding `KuyuMojoTrainingRuntime` | 22/22 passed at `/tmp/kuyu-mojo-training-runtime-full-1.xcresult` |
| Workspace boundaries and source-risk policy hold | `validate-kuyu-boundaries.sh`, `validate-unconscious-boundaries.sh`, and `audit-dangerous-code.sh --verbose` | Passed; zero audit blockers |

The bounded test command was:

```text
KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1 TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault xcodebuild test -quiet -scheme kuyu-mojo-Package -destination platform=macOS,arch=arm64 -skipPackagePluginValidation -maximum-test-execution-time-allowance 60
```

The prior strict result bundle `/tmp/kuyu-mojo-preflight-full-1.xcresult`
reported 16 of 16 tests passed, including the original preflight contract tests
and the strict CPU performance gate. The current non-strict package result
`/tmp/kuyu-mojo-training-runtime-full-1.xcresult` reported 22 of 22 tests
passed. The installed real compiler was Mojo `1.0.0
(ed45d567)`.
The measured Float32 maximum absolute residuals were `4.60e-7` for force,
`2.10e-6` for derivative, `5.25e-7` for observables, `6.38e-8` for the 20-step
RK4 state, and `4.59e-7` at the zero boundary. Runtime evidence covers macOS
arm64 CPU Float64 and Float32. Linux ARM64 evidence covers cross-compilation,
package selection metadata, archive integrity, object architecture, and ABI
symbols. Metal evidence now includes the lower-level Float32 vector-add
regression and a generated canonical acceptance executable covering all 11
reference graphs. It does not claim a production Kuyu accelerator session,
training, performance qualification, Linux native link or execution, CUDA,
native Jetson, sanitizer, or HIL qualification.

## Shared-state review matrix

| Logical state | Storage type | Isolation | Read entry | Mutation entry | Release |
|---|---|---|---|---|---|
| Compiled program and graphs | Immutable `Sendable` values | Value isolation | Executor methods | None | Value lifetime |
| Canonical semantic values | Call-local `MojoCanonicalValue` | Calling task | Graph executor input | None | Value lifetime |
| Encoded CPU invocation payload | Call-local `[Double]` or `[Float]` | Calling task | ABI borrow | Payload assembly before borrow | Automatic |
| Accelerator plan and runtime input | Separate immutable `List[Float32]` values | Acceptance call | Host-to-device copy | Generated before device launch | Call end |
| Accelerator workspace and status buffers | Call-local MAX host/device buffers | One acceptance call; one graph instance per GPU thread | Read after synchronization | Kernel only | Device-context call end |
| Mojo workspace | Call-local `[Double]` or `[Float]` | Synchronous mutable borrow | Output reconstruction after return | Mojo ABI call only | Borrow end |
| Physics and execution identity | Immutable `Sendable` values | Value isolation | Explicit identity API | None | Value lifetime |

There is no target-conditioned storage or concurrency contract in this slice.
No lock contains I/O, `await`, event emission, or an external callback.
