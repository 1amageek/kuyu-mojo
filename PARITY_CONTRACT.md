# CPU Float64 parity contract

KuyuPhysics is the semantic reference. The Mojo CPU Float64 executor consumes
the same digest-bound canonical program and is accepted only when every
declared comparison below passes. A time or fixture limit is not convergence.

```text
Canonical program digest
    -> Swift Float64 reference
    -> Mojo CPU Float64
        -> force / derivative / observable residuals
        -> full and singleProp RK4 state residuals
        -> zero and projection boundaries
        -> typed backend failures
```

| Surface | Absolute tolerance | Relative tolerance | Required boundary |
|---|---:|---:|---|
| Generalized force | `1e-12` | `1e-12` | all nine terms and single-prop subset |
| State derivative | `1e-12` | `1e-12` | full and single-prop forces |
| Observables | `1e-12` | `1e-12` | body rotation and specific force |
| RK4 integrated state | `1e-11` | `1e-11` | full identity and single-prop vertical projection |
| Zero norm | `1e-12` | `0` | zero relative wind and angular velocity |

The backend must classify invalid plan metadata/opcodes, division by zero, and
non-finite results as typed failures. It must not substitute reference values,
skip force terms, or select another device.

The strict performance gate is 400 complete RK4 steps per second under
`xcodebuild test`, enabled by `KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS=1`.
