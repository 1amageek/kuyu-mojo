# Target ownership

| Target | Owns | Must not own |
|---|---|---|
| `KuyuMojoCore` | Backend execution identity, numeric type, and device class | Physics equations, scenarios, training plans, fallback policy |
| `KuyuMojoDynamics` | Canonical-program compilation and deterministic Mojo CPU Float64/Float32 execution | Canonical equation definition, scenario selection, reward/failure semantics |

`KuyuPhysics` remains the sole authority for opcodes, layouts, units,
differentiability, force terms, integration declarations, and program digests.
The Mojo package implements one dtype-generic closed-opcode interpreter and
consumes the canonical graph as data. `MojoCanonicalValue` is the semantic
Double boundary; materialization into Float64 or Float32 is an explicit backend
decision recorded in execution identity.
