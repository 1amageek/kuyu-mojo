# Target ownership

| Target | Owns | Must not own |
|---|---|---|
| `KuyuMojoCore` | Backend execution identity, numeric type, and device class | Physics equations, scenarios, training plans, fallback policy |
| `KuyuMojoDynamics` | Canonical-program compilation and deterministic Mojo CPU Float64 execution | Canonical equation definition, scenario selection, reward/failure semantics |

`KuyuPhysics` remains the sole authority for opcodes, layouts, units,
differentiability, force terms, integration declarations, and program digests.
The Mojo package implements a generic closed-opcode interpreter and consumes
the canonical graph as data.
