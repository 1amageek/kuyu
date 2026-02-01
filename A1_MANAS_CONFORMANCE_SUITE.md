# A1 Manas Conformance Test Suite Specification (Local Copy)

## Scope
Defines the required structure and checks for declaring **Manas‑Conformant** implementations. Tests are valid **only** within a declared Operating Envelope Declaration (OED).

## Required Declarations (per implementation)
- OED (physical bounds, sensor bounds, disturbance bounds, actuator bounds, update rates)
- Input/output normalization ranges `R_y`, `R_u`
- Controller update period `Δt_c` and multi‑rate aggregation rule
- Continuity constants `L2`, `L∞`
- Total variation bound `V_max(T)` definition
- Phase bandwidth `B_phi` and minimum variance `Var_min(T)`
- Declared saturation and rate‑limit models (for residual analysis)
- Badge claims: B0/B1/B2

## Required Input Families
All families must be generated **within OED bounds** and with declared coverage across amplitude and frequency bands:
- Step (bounded amplitude)
- Ramp (bounded slope)
- PRBS (low‑pass shaped)
- Chirp (band‑limited sweep)
- Band‑limited noise (seeded)

## Mandatory Checks
### Continuity (normalized)
At controller steps `n`:
- `||u[n] - u'[n]||_2 ≤ L2 * ||y[n] - y'[n]||_2`
- `||u[n] - u'[n]||_∞ ≤ L∞ * ||y[n] - y'[n]||_∞`

### Total Variation (normalized)
For any window `T`:
- `TV(u; T) ≤ V_max(T)`

### Non‑Symbolic Behavior
- **Output snapping** detection on residuals after subtracting declared saturation/rate‑limit effects
- **Mode induction** detection: bounded perturbations must not select finite command‑like behaviors
- **Identifier policy**: numeric indices only; no semantic labels

### Phase Anti‑Token
- Snapping or low‑variance collapse detection
- Bandwidth limit `B_phi` enforced
- Minimum variance `Var_min(T)` under declared excitations

## Reporting Requirements
Each test run MUST log:
- OED identifier and version
- Suite version and configuration hash
- Pass/fail per test family and per check category
- Badge claims and any profile assumptions (e.g., IMU6 fixed mapping)

