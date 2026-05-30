# World Model Spec

`KuyuWorldModel` describes the simulated physical environment.

| Section | Meaning |
|---|---|
| `time` | Fixed step and substep policy. |
| `integrator`, `solver` | Deterministic integration and constraint policy. |
| `gravity`, `atmosphere`, `wind` | Global environment fields. |
| `surfaces`, `materials`, `contact` | Contact/friction declarations. |
| `nap` | Negligibility approximation thresholds. |
| `randomness` | Seed and replay policy. |

SDF can be imported into this model. SDF remains a compatibility surface; Kuyu's
native world model is the simulation authority.
