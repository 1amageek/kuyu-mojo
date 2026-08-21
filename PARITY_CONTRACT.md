# CPU numeric parity contract

KuyuPhysics is the semantic reference. The Mojo CPU Float64 executor consumes
the same digest-bound canonical program as the Float32 executor. Float64 is the
semantic verifier; Float32 is the declared precision rung consumed by future
Metal and CUDA executors. Each is accepted only when every declared comparison
below passes. A time or fixture limit is not convergence.

```text
Canonical program digest
    -> Swift Float64 reference
        -> Mojo CPU Float64 semantic verifier
        -> Mojo CPU Float32 accelerator precision verifier
            -> force / derivative / observable residuals
            -> full and singleProp RK4 state residuals
            -> zero and projection boundaries
            -> typed backend failures
```

## Float64 verifier

| Surface | Absolute tolerance | Relative tolerance | Required boundary |
|---|---:|---:|---|
| Generalized force | `1e-12` | `1e-12` | all nine terms and single-prop subset |
| State derivative | `1e-12` | `1e-12` | full and single-prop forces |
| Observables | `1e-12` | `1e-12` | body rotation and specific force |
| RK4 integrated state | `1e-11` | `1e-11` | full identity and single-prop vertical projection |
| Zero norm | `1e-12` | `0` | zero relative wind and angular velocity |

## Float32 accelerator precision rung

| Surface | Absolute tolerance | Relative tolerance | Required boundary |
|---|---:|---:|---|
| Generalized force | `5e-6` | `5e-6` | all nine terms and single-prop subset |
| State derivative | `1e-5` | `5e-6` | full and single-prop forces |
| Observables | `5e-6` | `5e-6` | body rotation and specific force |
| RK4 integrated state | `1e-6` | `1e-5` | full identity and single-prop vertical projection |
| Zero norm | `2e-6` | `0` | zero relative wind and angular velocity |

Float32 plan metadata is accepted only within the exact 24-bit integer range.
Constants and runtime inputs that cannot be represented as finite Float32
values are typed failures; they are never clamped or converted to infinity.

The backend must classify invalid plan metadata/opcodes, division by zero, and
non-finite results as typed failures. It must not substitute reference values,
skip force terms, or select another device.

The strict performance gate is 400 complete RK4 steps per second for both CPU
numeric types under `xcodebuild test`, enabled by
`KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1`.
