# Reliability evidence

## 2026-08-22 production Plant and IMU injection

| Claim | Evidence | Result |
|---|---|---|
| Mojo CPU execution reaches Kuyu's production physics objects | `MojoInjectedPlantRuntimeTests` constructs the real `ReferenceQuadrotorPlantEngine` and `IMU6SensorField` with one `MojoScalarDynamicsExecutor`, advances eight RK4 ticks, and samples the IMU after every tick | Passed for Float64 and Float32; every state component, channel index, timestamp, and sensor value matched the Swift scalar oracle within the numeric-specific tolerance |
| The executor boundary preserves failure semantics | KuyuPhysics' injected failure fixture throws from the same `ReferenceQuadrotorCanonicalExecuting` protocol used by Mojo | Plant integration and IMU sampling returned the typed failure; neither selected the scalar default |
| Existing Mojo runtime and ABI behavior remains intact | `KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1 xcodebuild test -quiet -scheme kuyu-mojo-Package -destination 'platform=macOS,arch=arm64' -maximum-test-execution-time-allowance 60` | 47 tests / 48 parameterized runs passed, failure 0, skip 0, at `/tmp/kuyu-mojo-injected-full/Logs/Test/Test-kuyu-mojo-Package-2026.08.22_18-36-42-+0900.xcresult` |
| Workspace safety and boundaries remain intact | `validate-kuyu-boundaries.sh`, `validate-unconscious-boundaries.sh`, `audit-dangerous-code.sh --verbose`, incomplete-implementation and target-conditioned synchronization scans | Passed; blocker 0, 892 review findings, 44 existing files over 450 lines, no incomplete marker or target-conditioned state split in this change |

This slice makes Mojo Float64/Float32 a real injectable Kuyu physics backend; it
does not make batch accelerator execution an in-process control session. Metal
and CUDA remain attempt-owned worker backends with receipt-bound lifecycle and
hardware acceptance gates. Native Jetson execution remains open while the
admitted device is offline.

## 2026-08-22 KuyuDataset v7 to Manas adaptation

| Claim | Evidence | Result |
|---|---|---|
| Persisted Kuyu data has one typed conversion boundary into Manas | `KuyuManasMojoAdapter` depends on `KuyuTrainingContracts`, `KuyuTrainingValidation`, and `ManasLearningContracts`; its source imports neither MLX nor MAX | Package graph and import scan passed; the adapter does not duplicate dataset persistence or Manas model structure |
| On-policy behavior evidence cannot be fabricated during conversion | `KuyuDatasetManasLearningAdapter` fixed-owns `KuyuExactOnPolicyEvidenceVerifier`; callers cannot inject a no-op verifier. The verifier recomputes base Gaussian probability and identity, affine-tanh, or affine-sigmoid transform Jacobians, and compares action, transformed mean, and transformed log probability | Valid evidence for all three distributions and saturated tanh passed; fabricated log probability, invalid tolerance, non-finite values, transform/space mismatch, and unsupported versions are typed failures |
| Materialization is bounded and conversion identity is explicit | Adapter initialization validates transition/scalar limits; the complete Float budget includes recurrent initial state, model inputs, policy actions, rewards/costs/log probability, behavior vectors, and optional value evidence; the direct encoder requires two SHA-256 contract digests | Transition overflow, scalar overflow, placeholder digest, and lossy `Double`-to-`Float` conversion tests passed as typed failures |
| Fixed-history and recurrent semantics survive the boundary | The adapter constructs `ManasOnPolicyTrajectory`, whose initializer revalidates identity, dimensions, continuity, behavior identity, recurrent state chains, loss masks, and final boundary | Fixed-history and recurrent burn-in/loss-start fixtures passed and produced immutable Manas values |
| Existing package behavior remains intact | Bounded arm64 `xcodebuild build-for-testing` followed by `xcodebuild test-without-building`; boundary validators; verbose source-risk audit; incomplete and concurrency pattern scans | Adapter target 20/20 and full package 46/46 passed at `/tmp/kuyu-mojo-manas-adapter-full-v3.xcresult`; blocker 0, 44 existing oversized-file review findings outside this package |

The Swift 6.4 snapshot provides `libTesting.dylib`, but the installed Xcode 27
beta did not copy it into the package test bundle. Verification therefore used
the successful `xcodebuild build-for-testing` output, copied the snapshot's
signed universal `libTesting.dylib` and `lib_TestingInterop.dylib` only into
that DerivedData `PackageFrameworks` directory, and ran bounded `xcodebuild
test-without-building`. No source, system toolchain, or persistent environment
setting was changed by this runner workaround.

This slice proves the final semantic conversion owner and its success/failure
behavior. It does not prove Manas Mojo models or runtime, optimizer compute,
bundle/model-store gates, an attempt-owned worker, learned improvement,
application cutover, or native Jetson execution.

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
| The CUDA cross-compile handoff is deterministic, source-complete, and cannot claim native acceptance | Two independent runs of `scripts/prepare-cuda-canonical-acceptance.sh` compared the complete nested output trees; the checked-in imported module was copied before compilation and that copy was used as the compiler search root; rejection checks covered an existing output, a relative output, missing toolchain identity, and an intentional compiler failure | Both successful runs produced source `3467e04cd3b032d750de6825c8e0242d4f276ce78eb3b2dbb5960c170a635433`, object `ef696d6dbc8dfe42af2374e828e98b252d8d67471c3c158554e27a4622723b1b`, module closure `8ddf1b9ec3b446c50452ad5c0213415db9025cf7361853eb9754819497a71164`, and evidence `97f7af7bce2edfb409b7ea8a9b9afad7bb2e2d5b2fcbb624444cba1bf52ac64c`; evidence fixes `crossCompiledOnly` and `nativeAcceptance: false`, while failure published no partial output and leaked no temporary directory |
| Checked-in CPU ABIs remain source-derived after the shared interpreter refactor | `swift package --disable-sandbox mojo inspect --target KuyuMojoDynamics` on the final generated artifacts | Passed; two synchronous Float32/Float64 bindings, input graph `74ff401f1cdeca4559652bbd8d0aa38562cc264a48e9ce87f247377d50591cea`, aggregate artifact `77490acc7cbecc26b6f77bc1d2f9a5e37d3d36d113291b35aace839048b0d97b` |
| Workspace boundaries and source-risk policy still hold | `validate-kuyu-boundaries.sh`, `validate-unconscious-boundaries.sh`, `audit-dangerous-code.sh --verbose`, the incomplete-implementation scan, and `bash -n` for the acceptance scripts | Passed; zero audit blockers, zero incomplete markers, and 44 pre-existing oversized-file review findings outside this package |

This is a canonical hardware-acceptance slice, not a production accelerator
session. It proves the same encoded Kuyu equations execute on Metal and that the
exact runtime artifact can be admitted and relocated. It does not yet prove an
attempt-owned worker protocol, cancellation/shutdown races, sustained batch
performance, training correctness, native CUDA execution, native Jetson
execution, sanitizer, or HIL qualification.

## 2026-08-22 Jetson CUDA admission and native runner

| Claim | Evidence | Result |
|---|---|---|
| The native environment cannot drift to a mutable MAX image | Direct OCI manifest inspection of `modular/max-nvidia-base:26.5.0` resolved index `cb38ee4e04da5fb84eb4864b83098afd281f894971111c6ef059b8f8d0a9a5f8` and Linux ARM64 manifest `4566cb6f9ff3b51dc71542066f9dc72de27a823ea7b5c4613bd883ad71c1c57e`; its configuration reports ARM64, CUDA 13.0, and revision `ed45d567` | `HardwareAcceptance/JetsonCUDA/Dockerfile` uses the platform manifest digest directly, checks `Mojo 1.0.0 (ed45d567)`, and installs nothing from mutable operating-system repositories |
| Only the exact source-complete handoff can enter native acceptance | `validate_handoff.py` re-hashes the fixed evidence, canonical source, AArch64 object, every module file, aggregate module closure, target, PTX identity, and managed tree while rejecting symbolic links and extra files | Current handoff passed; the prior source-incomplete handoff failed with status 70 before any device access |
| Device admission cannot silently mutate or deploy to the wrong target | `HardwareAcceptance/JetsonCUDA/test_host_gate.py` exercises admitted WendyOS 0.18.1/AArch64/NVIDIA/Jetson Orin, incomplete native evidence, WendyOS 0.18.2, offline-device, relocatable-object, and unexpected-handoff-tree responses through the exact host orchestration with a bounded fake CLI | Accepted orchestration preserved all 11 ordered graph markers and a typed accepted receipt; pre-deploy rejections invoked no run path, while incomplete post-run evidence remained a typed failure |
| Offline hardware is explicit evidence rather than false success | `scripts/accept-cuda-canonical-on-jetson.sh` queried the pinned `wendyos-valiant-iris.local` identity with the installed Wendy CLI and a 20-second process-group timeout | Failed with status 70 and wrote `/tmp/kuyu-jetson-offline-receipt-v2`; receipt SHA-256 `b2736ac79e25f08f9eaf8551242882841be82a6e368b373574863f72237d21df`, `nativeAcceptance: false`, no device identity, and no deployment |
| The exact ARM64 acceptance image builds and fails closed without a CUDA driver | `wendy json validate` passed the GPU-only manifest; `docker buildx build --check --platform linux/arm64` reported no warnings; a subsequent full build validated the pinned base, AArch64, Mojo version, and source-complete handoff | Built 2,345,826,876-byte Linux ARM64 image `sha256:01ff080707f7676fe14b87441cf01059b1561df942974277638940aa3a6cc57b`; running it on the non-CUDA Apple host exited 70 because `libcuda.so.1` was unavailable, before native compilation or execution, so no Jetson result was claimed |

The accepted host-path fixture proves admission, routing, ordered marker
validation, and receipt composition only. It is not Jetson execution evidence.
Native acceptance remains open until the real device passes native Mojo
compilation, CUDA device execution, all 11 graph differentials, and the final
terminal marker inside the GPU-entitled container.

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
| Dataset adapter configuration | Immutable `Sendable` reader, encoder, verifier, and limits | Value isolation | `trajectory(from:)` | None | Adapter value lifetime |
| Trajectory materialization | Call-local arrays over a reader-owned immutable snapshot | One synchronous conversion call | Manas trajectory construction after validation | Reader callback before return | Automatic at call end |

There is no target-conditioned storage or concurrency contract in this slice.
No lock contains I/O, `await`, event emission, or an external callback.
