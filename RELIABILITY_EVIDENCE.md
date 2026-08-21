# Reliability evidence

## 2026-08-21 CPU Float64 canonical dynamics

| Claim | Evidence | Result |
|---|---|---|
| Canonical program compilation is deterministic and digest-bound | Two independent compilations of reference digest `6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310` | Passed |
| Mojo force, derivative, and observable traces match the Swift Float64 reference | Differential tests for full and single-prop fidelity using the tolerances in `PARITY_CONTRACT.md` | Passed |
| RK4 integration preserves declared projection semantics | Twenty-step full and single-prop traces, including vertical-only projection | Passed |
| Piecewise zero-norm behavior is portable | Zero relative wind and angular velocity fixture | Passed |
| Invalid execution cannot become a success value | Digest mismatch, undeclared fidelity, missing/shape/non-finite input, corrupt header, invalid opcode, division by zero, and non-finite arithmetic tests | Passed |
| CPU execution meets the current control-loop floor | Strict `KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1` test with 200 timed full RK4 steps | Passed at the 400 steps/s floor |
| The checked-in ABI artifacts match the source graph | `swift package mojo inspect --target KuyuMojoDynamics` | One binding; input graph `17ccc1dafcd1a39fe839f86cd62aad3c592f740eac953e1dc288834373f29d4d`; aggregate artifact `f947ad6dfe03d4e2c73032836b394db8b15325eb1f3aa6db09fb86e3e3879088` |
| The Linux ARM64 archive contains the compiled Mojo object | `llvm-ar t`, `llvm-nm --undefined-only`, and extraction followed by `file` | Archive `c75748ded8452c9409d1cdc4375fa2fb0c275fc2b3793b61ac1fc1e7ab9b253d`; member `Bindings.o`; ELF64 aarch64; only unresolved symbol is libc `memset` |
| Linux ELF packaging cannot silently produce an empty archive | `swift-mojo` revision `4f3f2e70e176be9f9698d03d1041ddf9a5698433` archive-member verification and its 140-test suite | Passed |
| Workspace boundaries and source-risk policy hold | `validate-kuyu-boundaries.sh`, `validate-unconscious-boundaries.sh`, and `audit-dangerous-code.sh --verbose` | Passed; zero audit blockers |

The bounded test command was:

```text
KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1 TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault xcodebuild test -quiet -scheme kuyu-mojo-Package -destination platform=macOS,arch=arm64 -skipPackagePluginValidation -maximum-test-execution-time-allowance 60
```

The result bundle reported 9 of 9 tests passed. The installed real compiler was
Mojo `1.0.0 (ed45d567)`. Runtime evidence covers macOS arm64 CPU Float64. Linux
ARM64 evidence covers cross-compilation, package selection metadata, archive
integrity, object architecture, and ABI symbols. It does not claim Linux native
link or execution, Metal, CUDA, native Jetson, sanitizer, learning, or HIL
qualification.

## Shared-state review matrix

| Logical state | Storage type | Isolation | Read entry | Mutation entry | Release |
|---|---|---|---|---|---|
| Compiled program and graphs | Immutable `Sendable` values | Value isolation | Executor methods | None | Value lifetime |
| Encoded invocation payload | Call-local `[Double]` | Calling task | ABI borrow | Payload assembly before borrow | Automatic |
| Mojo workspace | Call-local `[Double]` | Synchronous mutable borrow | Output reconstruction after return | Mojo ABI call only | Borrow end |
| Physics and execution identity | Immutable `Sendable` values | Value isolation | Explicit identity API | None | Value lifetime |

There is no target-conditioned storage or concurrency contract in this slice.
No lock contains I/O, `await`, event emission, or an external callback.
