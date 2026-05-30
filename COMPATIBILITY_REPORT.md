# Compatibility Report

`CompatibilityReport` records how external or supplemented model information was
mapped into Kuyu-native contracts.

| Status | Meaning |
|---|---|
| `exact` | Semantics map directly. |
| `approximated` | Semantics are represented with a known approximation. |
| `supplemented` | Kuyu-native value was explicitly added because the source lacked it. |
| `ignored` | Source field is intentionally not used for the target readiness level. |
| `unsupported` | Source field cannot be represented and blocks readiness. |

Readiness gates fail when unsupported mappings are present. Supplemental values
are acceptable only when they are declared and sufficient for the requested
`ReadinessLevel`.
