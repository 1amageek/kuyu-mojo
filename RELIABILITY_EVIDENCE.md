# Reliability evidence

## 2026-08-23 backend-neutral Manas inference transport

| Claim | Evidence | Result |
|---|---|---|
| Core and Reflex keep semantic ownership inside Manas while accepting an external accelerator session | `ManasMojoInferenceSessionTransport` exposes only typed initialize/infer operations, capabilities, and shutdown. `ManasMojoCoreModelSession` and `ManasMojoReflexModelSession` still materialize validated weights, encode payloads, decode and validate outputs, and own recurrent/decomposition semantics | The complete `ManasMojoRuntimeTests` target passed 23 tests with failure 0 at `/Users/1amageek/Library/Developer/Xcode/DerivedData/manas-cqxwgyvkqnujwkakahjhivwakwuf/Logs/Test/Test-manas-Package-2026.08.23_08-15-31-+0900.xcresult`, including real CPU/MLX differential inference and injected accelerator success/failure paths |
| Kuyu admits only the exact Manas Core or Reflex callable ABI | Separate public factories require the corresponding Manas session-factory name and ordered initialize/infer operations before preflight; the loaded session repeats the ordered-operation check and requests only `.accelerator` with synchronous Float32 device memory | Cross-wired Core/Reflex requirements and session operation drift failed as typed errors; the complete `KuyuManasMojoAdapterTests` target passed 29 tests with failure 0 at `/Users/1amageek/Library/Developer/Xcode/DerivedData/kuyu-mojo-ermfutvxklhjkhfvlwksygiupozt/Logs/Test/Test-kuyu-mojo-Package-2026.08.23_08-16-15-+0900.xcresult` |
| Dynamic ownership remains ordered and backend-neutral | One Kuyu transport owns one verified runtime plus one Core or Reflex session; initialization failure transfers cleanup to the Manas model session, and explicit shutdown closes the session before its runtime | The deterministic adapter fixture observed `session.shutdown` followed by `runtime.shutdown`; missing device memory closed before inference, and dynamic invocation failure remained a typed Manas transport error without CPU fallback |
| Workspace boundaries and source-risk policy remain intact | Kuyu and unconscious boundary validators, verbose dangerous-code audit, incomplete-implementation scan, target-conditioned synchronization scan, and diff checks | Both validators passed; audit blocker 0 with 921 review findings, no new direct file decoding, child process, unsafe memory, target-conditioned synchronization, or incomplete implementation in this slice |

This slice closes the Swift transport, capability, operation-identity, and
ownership seam for Core and Reflex inference. It does not claim that a real
accelerator inference kernel or runtime bundle exists, nor does it provide
Apple or Jetson inference parity, latency, memory, thermal, or cancellation
evidence.

## 2026-08-23 device-resident Manas Adam on Apple Metal

| Claim | Evidence | Result |
|---|---|---|
| Adam committed state resides behind the accelerator session rather than a CPU fallback | Manas' backend-neutral accelerator source creates one real `DeviceContext`, retains parameter and moment buffers on device, uses separate pending proposal buffers, and validates candidate parameters on GPU before commit | Mojo 1.0.0 compiled schema-3 bundle `daaaaaa311e3a61729ff11368f71c0b95fd0f97273c73069f9c81e03661df161` for `arm64-apple-macosx14.0|apple-m4|metal:4`; the verified session advertised device-memory capability 29 and `.accelerator` |
| The dynamic Metal trajectory preserves CPU Adam semantics | `executesOptInRealMetalBundleWithCPUParity()` preflights the exact bundle identity, loads it through `KuyuManasMojoAdamOptimizerSessionFactory`, and advances it beside the static Manas CPU session | Proposal plus discard left both states unchanged; three committed steps matched descent directions, metrics, parameters, first moments, second moments, and update count |
| Artifact drift and runtime failure remain fail closed | The test requirement fixes module, bundle, receipt, input-graph, target, factory, and all six ordered operation names; the Mojo session poisons itself on device/runtime exceptions instead of returning success | The complete adapter target passed 26 tests in 4 suites, including malformed identity, ABI mismatch, initialization cleanup, operation mismatch, and the real Metal path |
| CPU behavior remains intact after sharing the Adam contract | The regenerated static CPU artifacts ran through the Manas optimizer suite after the common validation/math extraction | 20 tests in 4 suites passed, including MLX differential continuation, checkpoint resume, arithmetic rollback, concurrent serialization, and lifecycle failure |

This is semantic acceptance of one Apple Metal optimizer slice. Latency,
allocation, sustained memory, complete RR-PPO worker composition, and native
Jetson CUDA remain separate gates.

## 2026-08-23 Manas Adam verified-runtime adapter

| Claim | Evidence | Result |
|---|---|---|
| Kuyu can provide a verified accelerator session without taking ownership of Adam semantics | `KuyuManasMojoAdamOptimizerSessionFactory` composes the public bundle preflight and dynamic loader with `ManasMojoAdamOptimizerSession`; Kuyu routes the six public operation names but never decodes a payload or creates a proposal token | The focused fixture observed initialization and proposal through the exact Manas ABI, while status 35 returned `proposalAlreadyPending` from Manas |
| Artifact or ABI drift cannot select another backend or operation | Factory construction fixes the Manas session request to `.accelerator` and requires the factory plus ordered execution names to equal `ManasMojoAdamABI`; the runtime session repeats the ordered-name check before Manas initialization | Mismatched manifest operations and mismatched runtime operations failed before optimizer use; the mismatch path released session before runtime |
| Creation and initialization failures preserve ownership order | Session-creation failure closes the loaded runtime; after a session exists, Manas initialization failure closes the transport, which shuts down session before library | Status 23 returned `invalidInitialState`; lifecycle observations were exactly `session.shutdown`, then `runtime.shutdown`; failed creation observed runtime shutdown only |
| Existing Kuyu/Manas adaptation remains intact | arm64 `xcodebuild build` completed the production adapter target; the complete `KuyuManasMojoAdapterTests` target exercised the new factory alongside dataset and on-policy conversion | 25 tests in 4 suites passed with failure 0 at `/tmp/kuyu-mojo-adam-adapter-dd/Logs/Test/Test-kuyu-mojo-Package-2026.08.23_01-54-41-+0900.xcresult` |

This slice closes the typed Swift ownership and routing seam. It does not claim
device-resident Adam execution: the Manas-owned accelerator Mojo source, its
schema-3 bundles, real Metal parity, and native Jetson CUDA evidence remain
separate gates.

## 2026-08-23 ordered accelerator session operations

| Claim | Evidence | Result |
|---|---|---|
| One persistent Mojo session can expose multiple product-level operations | The bundle requirement and preflight accept a nonempty ordered list of unique execution function names, require every binding to use the session-buffer signature and the same factory, and preserve requested order into the loaded session | Core tests admitted two execution bindings in reversed manifest order and retained the required order; empty and duplicate requirements failed as typed validation errors |
| Runtime dispatch cannot silently select the wrong operation | `DynamicMojoAcceleratorRuntimeLoader` rechecks unique function names and binding IDs against fresh verification and generated ABI availability; `OwnedMojoAcceleratorSession` maps an explicit name to its immutable binding ID | A two-operation C ABI fixture returned distinct results for IDs 12 and 13; an unknown name preserved the caller's output and returned `unavailableExecutionFunction`, while a duplicate ID returned `runtimeBindingIdentityMismatch` |
| All named operations share one lifetime and concurrency boundary | Named and default calls both borrow the same `MojoSessionOwner`; the deterministic foreign-call fixture blocked the secondary operation while a default call and shutdown competed | Both competing operations returned `MojoSessionError.busy`; releasing the call permitted ordered session and library shutdown |
| Existing single-operation Metal bundles remain executable | The exact Mojo 1.0.0 pixi environment regenerated schema-3 bundle `2e89bda4bc15fb935f5df9cb1a43f029336653ef095bea62d60076dbb3d84f99`; public preflight and the changed dynamic loader then created one Apple M4 Metal session and executed two requests | The strict package run passed 58 tests / 59 runs, including 6 Core and 7 runtime tests, with failure 0 and skip 0; real Metal returned `[41, 42]` then `[43, 44]` at `/tmp/kuyu-mojo-multibinding-full-dd/Logs/Test/Test-kuyu-mojo-Package-2026.08.23_01-26-58-+0900.xcresult` |

This slice generalizes the verified runtime boundary required by transactional
optimizer proposal, commit, discard, read, and checkpoint operations. The
current accepted dynamics bundle still contains one execution binding; an
accelerator-resident Adam implementation and its platform artifacts remain a
separate implementation gate.

## 2026-08-22 schema-3 callable accelerator session

| Claim | Evidence | Result |
|---|---|---|
| Production admission is bound to a callable library rather than an evidence executable | swift-mojo schema-3 bundle `2e89bda4bc15fb935f5df9cb1a43f029336653ef095bea62d60076dbb3d84f99` and receipt `3969ad6b6d12dd2416aa745bdc4037ad2faba85bd24b34d0abd3d5eb1c8be747` bind module `SwiftMojo_KuyuMojoAcceleratorSession_ABI`, input graph `d35ef968…`, its generated header, exported symbols, runtime libraries, factory `createKuyuMojoAcceleratorSession`, and execution `executeKuyuMojoAcceleratorBatch` | Public preflight accepted the exact identity and rejected schema, bundle, receipt, target, module, graph, function, signature, and factory-relationship drift as typed failures |
| The generated ABI reaches real Metal through a persistent session | Fresh runtime-library verification was followed by a linked C ABI probe under `env -i` and by `DynamicMojoAcceleratorRuntimeLoader`; each created an Apple M4 Metal session, executed two canonical Float32 graph requests through the same context and reusable buffer owner, then shut down session before library | `metal_session_create`, `metal_session_batch`, `metal_session_reuse`, and `metal_session_shutdown` passed; Swift returned `[41, 42]` then `[43, 44]` from the real bundle |
| The generic training launcher never mistakes the library for its worker | `MojoTrainingWorkerBundlePreflight` returns only the outer Kuyu worker path and independently verifies the nested runtime library on source and attempt-owned staged roots; the process fixture places executable `/usr/bin/true` at the worker path and non-executable bytes at the library path | The worker reached status 0 and the expected missing durable outcome; source and staged real-bundle paths passed in the final full result below |
| Foreign-call concurrency preserves ownership and ordered shutdown | A deterministic C fixture blocks session creation or execution after entering the ABI. Concurrent library shutdown reports `activeCreations: 1`; concurrent session invocation and shutdown report `MojoSessionError.busy`; release then permits session followed by library shutdown | All 6 loader tests passed as part of the final full result below |
| The migration does not regress existing canonical dynamics or strict CPU performance | Full Xcode build-for-testing and test-without-building ran with `KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1` and the real schema-3 Metal bundle | 55 tests / 56 runs passed, failure 0, skip 0, at `/tmp/kuyu-mojo-schema3-final-dd/Logs/Test/Test-kuyu-mojo-Package-2026.08.22_22-36-19-+0900.xcresult` |
| Source-risk and architecture boundaries remain enforced | `validate-kuyu-boundaries.sh`, `validate-unconscious-boundaries.sh`, verbose dangerous-code audit, incomplete-implementation scan, target-conditioned synchronization scan, swift-format lint, and structural scan | Both validators passed; audit blocker 0 with 44 reported review call sites read, all outside `kuyu-mojo`; no incomplete implementation or target-conditioned state split exists in this runtime target |

This slice completes the callable Metal library, verified admission, persistent
session, attempt staging, and synchronous concurrency/lifetime boundary. It does
not yet provide the authenticated worker executable that consumes this loader,
the Manas Mojo optimizer, sustained accelerator performance qualification, or
native Jetson CUDA execution.

## 2026-08-22 attempt worker and schema-1 runtime separation (historical, superseded)

| Claim | Evidence | Result |
|---|---|---|
| The accelerator evidence executable cannot be selected as the training worker | `MojoTrainingWorkerBundleLayout` requires separate non-overlapping worker and accelerator-runtime paths; `MojoTrainingWorkerBundlePreflight` rejects any generic preflight request whose executable path is not the declared Kuyu worker path | Path traversal, path overlap, non-file direct lookup, and accelerator-as-worker fixtures returned typed failures |
| Source and staged attempts re-verify the same nested runtime | The Mojo preflight conforms to KuyuTraining's existing executable-bundle preflight while returning the outer worker source; the generic stager pins and makes the complete outer tree read-only before the same preflight inspects the staged nested runtime | Focused source/staged launcher coverage passed without adding Mojo knowledge to `KuyuTrainingRuntime` |
| The generic launcher reaches the real worker path | The process fixture places `/usr/bin/true` at `bin/kuyu-worker` and `/usr/bin/false` at `AcceleratorRuntime/bin/kuyu-mojo-canonical`, then launches through `TrainingRunWorkerProcessLauncher` | The handle observed status 0 and the expected missing durable outcome; executing the nested evidence binary would have produced status 1 |
| Focused worker-boundary behavior passes | `xcodebuild test -scheme kuyu-mojo-Package -only-testing:KuyuMojoTrainingRuntimeTests -destination 'platform=macOS,arch=arm64' -maximum-test-execution-time-allowance 60` | 10/10 passed, failure 0, skip 0, in `/tmp/kuyu-mojo-worker-boundary-focused-final/Logs/Test/Test-kuyu-mojo-Package-2026.08.22_19-05-11-+0900.xcresult` |
| The accepted Metal closure survives the real attempt staging path | The same focused suite ran with `KUYU_MOJO_TEST_ACCELERATOR_BUNDLE=/tmp/kuyu-mojo-accelerator-canonical-bundle-v1`; `TrainingRunWorkerProcessLauncher` verified the source outer bundle, staged its complete real canonical runtime closure, re-verified the nested staged runtime, and launched the outer Kuyu worker path | 10/10 passed, failure 0, skip 0, in `/tmp/kuyu-mojo-worker-boundary-real-final/Logs/Test/Test-kuyu-mojo-Package-2026.08.22_19-21-18-+0900.xcresult` |
| Existing Mojo behavior and the strict CPU performance floor remain intact | Full non-parallel `kuyu-mojo-Package` test with the real accelerator bundle and `KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1` | 52 tests / 53 parameterized runs passed, failure 0, skip 0, in `/tmp/kuyu-mojo-worker-boundary-full/Logs/Test/Test-kuyu-mojo-Package-2026.08.22_19-07-56-+0900.xcresult` |

This historical slice closed executable identity and staging composition only.
It did not claim
that the Kuyu worker has a Mojo optimizer backend, owns a production MAX device
session, or has passed cancellation, shutdown, performance, or native Jetson
gates. The schema-3 callable session above supersedes its production admission
contract while retaining the schema-1 executable as reproducible acceptance
evidence.

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
| Accelerator identity does not change canonical structure | `acceleratorCompilationPreservesCanonicalGraphStructure` compares program digest, force-term order, workspace sizes, encoded plans, input bindings, and output bindings for CPU and accelerator Float32 compilations | Passed; the backend-neutral device class uses executor version `mojo-accelerator-float32-ssa-v1` |
| Unsupported accelerator precision cannot silently fall back | `acceleratorCompilationRejectsUnsupportedFloat64` requests accelerator Float64 compilation | It rejects with `MojoProgramCompilationError.unsupportedNumericType` |
| Plan and runtime storage have an explicit checked boundary | `float32InvocationSeparatesPlanFromRuntimeInput` checks exact plan materialization, runtime element count, workspace size, and rejection of a fractional/corrupt plan boundary | Passed as a typed failure |
| Canonical Metal execution matches the CPU Float32 oracle | `scripts/accept-metal-canonical-runtime-bundle.sh` generates the harness from reference program digest `6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310`; nine force graphs, derivative, and observables execute for a full-dynamics scenario and a zero-boundary scenario | 11/11 graphs × 2 batches passed on Apple M4 Max after device transfer and explicit synchronization |
| The canonical Apple accelerator runtime closure is reproducible and relocatable | Two independent runs of the backend-neutral generator produced receipt `c0b15f5d1628d1eec444d513de876028c7e940ddae15af209bc08d577e2cbb6c` and bundle `4337e0ba9aff535f07db67908b929aff403c6f11022738e8d5f3d78c1e072636`; each original and relocated executable ran under `env -i` and reported `canonical_accelerator_device=accelerator` | Passed four executions; executable `bin/kuyu-mojo-metal-canonical`, exact four-library MAX closure, artifact target `arm64-apple-macosx14.0|apple-m4|metal:4` |
| Public Kuyu preflight admits only that exact canonical bundle | Full package test used `KUYU_MOJO_TEST_ACCELERATOR_BUNDLE=/tmp/kuyu-mojo-accelerator-canonical-bundle-v1` and exercised both `KuyuMojoCore` and `KuyuMojoTrainingRuntime` source/relocation checks | 26/26 passed at `/tmp/kuyu-mojo-accelerator-neutral-final.xcresult`, including the strict CPU performance gate |
| The identical canonical fixture cross-compiles for Jetson | One backend-neutral generated source requests `accelerator`; the deployment compiler targets `aarch64-unknown-linux-gnu`, `cortex-a78ae`, and `sm_87` | Produced a 201,528-byte AArch64 ELF object with SHA-256 `d1751032ed6b08cfd318f1145c2eb36429b43ad72a747897b9d515d84c357253`; embedded PTX is version 8.1 and targets `sm_80`, so native Jetson link/run and specialization remain open |
| The Jetson cross-compile handoff is deterministic, source-complete, and cannot claim native acceptance | Two independent runs of `scripts/prepare-cuda-canonical-acceptance.sh` compared the complete nested output trees; the checked-in imported module was copied before compilation and that copy was used as the compiler search root; the host-gate regression again covered accepted synthetic evidence, incomplete evidence, wrong WendyOS, offline device, relocatable object, and unexpected handoff tree | Both successful runs produced source `5e482da97b0d56c1077e0021c53f23ea7a325fc5d5c95c2ab3b6c75a96e70893`, object `d1751032ed6b08cfd318f1145c2eb36429b43ad72a747897b9d515d84c357253`, module closure `bec3fe7eb6981380c9b2c09294b49c2e46f8d2394b539ea3e1044da1314d24a1`, and evidence `2e1301afbaafd9c642a929058614d87e17d21ff633bce28d2a5fcf5e68ca008f`; evidence fixes `crossCompiledOnly` and `nativeAcceptance: false` |
| Checked-in CPU ABIs remain source-derived after the shared interpreter refactor | `swift package --disable-sandbox mojo inspect --target KuyuMojoDynamics` on the final generated artifacts | Passed; two synchronous Float32/Float64 bindings, input graph `7401e30dd0ed46f0321fb376a4d0f7f285614784295f2425466316cd9b11a2f3`, aggregate artifact `cc66ce5fb97e5c751f4866822b0c176085ebdd6a2fbe76d470a23df6eb1d32fa` |
| Workspace boundaries and source-risk policy still hold | `validate-kuyu-boundaries.sh`, `validate-unconscious-boundaries.sh`, `audit-dangerous-code.sh --verbose`, the incomplete-implementation scan, and `bash -n` for the acceptance scripts | Passed; zero audit blockers, zero incomplete markers, and 43 oversized-file review findings |

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
| Kuyu's public preflight accepts the real relocated runtime bundle | Direct `xctest` with `KUYU_MOJO_TEST_ACCELERATOR_BUNDLE=/tmp/kuyu-runtime-bundle-real-v1` re-inspected the managed tree and returned the verified runtime executable path | Passed in `0.67` seconds; four runtime libraries observed |
| The Mojo verifier composes with Kuyu's generic source/staged executable contract | The original adapter tests proved exact relocation but incorrectly exposed the runtime evidence executable as the generic worker source | Superseded by the 2026-08-22 outer-worker/nested-runtime contract above |
| Kuyu independently admits the real Metal kernel bundle | Historical `KuyuMojoCore` and `KuyuMojoTrainingRuntime` opt-in tests re-read bundle `643f18ba…`, matched receipt `2bc7264e…` and `metal:4`, and verified a relocated copy; the former generic-worker-source projection is superseded by the outer-worker/nested-runtime contract above | 12/12 passed at `/tmp/kuyu-mojo-metal-bundle-preflight-1.xcresult` |
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
| Dynamic runtime library token and counters | `Mutex<State>` containing a process-local address token and session/creation counters | Short synchronous memory-only critical sections | `isShutdown` | begin/finish creation, register/release session, shutdown | `dlclose` after the lock and after active counts reach zero |
| Mojo accelerator session handle and resources | swift-mojo `MojoSessionOwner` with `Mutex<State>` | One synchronous foreign borrow at a time | capabilities and `isShutdown` | execute borrow, resource registration, shutdown | Generated shutdown after borrows/resources reach zero |

There is no target-conditioned storage or concurrency contract in this slice.
No lock contains I/O, `await`, event emission, or an external callback.

| Target | Storage and isolation | Read/mutation entry points | Shutdown/verification status |
|---|---|---|---|
| Native macOS Metal | `Mutex<State>` library owner plus `MojoSessionOwner` | Identical protocol methods shown above | Runtime concurrency and real Metal lifecycle passed |
| Native Linux / Jetson CUDA | Same source, `Mutex<State>`, and Glibc loader boundary | Same protocol methods; no raw-state branch | Native link/run remains unverified while the admitted Jetson is offline |
| WASM | Dynamic loading product is unsupported; no alternative storage declaration exists | No callable runtime path | Not compiled or claimed |
| Embedded | Dynamic loading product is unsupported; no raw pointer, weakened `Sendable`, or no-op lock branch exists | No callable runtime path | Not compiled or claimed |
