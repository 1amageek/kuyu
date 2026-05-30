# Plant API (Normative)

This document defines the minimum API contracts for profile-based robot models in Kuyu.
The API is expressed by the core protocols in `KuyuCore`.

## Required Protocols
- `DisturbanceField`
- `ActuatorEngine`
- `PlantEngine`
- `SensorField`

## DisturbanceField
Contract:
- Updates only internal disturbance state for the current time step.
- Must be deterministic for a given seed and time.
- `snapshot()` returns data for logging and UI only.

## ActuatorEngine
Contract:
- `update(time:)` advances actuator internal dynamics.
- `apply(values:time:)` applies actuator values for the current step.
- `telemetrySnapshot()` returns actuator telemetry for MotorNerve.
- Must not mutate plant state directly.

## PlantEngine
Contract:
- `integrate(time:)` advances the plant dynamics by one step.
- Uses the latest actuator and disturbance state.
- `snapshot()` returns plant state for logging and visualization.
- `safetyTrace()` returns safety envelope telemetry.

## SensorField
Contract:
- `sample(time:)` reads the current plant state and returns sensor samples.
- Must not mutate plant or actuator state.
- Delay and dropout are represented by missing samples or timestamp lag.

## Determinism Requirements
- All randomness must be seeded and logged.
- No hidden time sources are allowed in deterministic runs.
- The execution order is defined in `WORLD_SPEC.md` and MUST be followed.

## Body/World/Embodiment Binding
Plant construction is bound by three native contracts:

| Contract | Plant responsibility |
|---|---|
| `KuyuBodyModel` | Build morphology-specific plant state from declared links, joints, mass, inertia, limits, damping, friction, and actuator attachments. |
| `KuyuWorldModel` | Use declared gravity, fixed timestep, solver policy, and enabled contact/friction capabilities. |
| `EmbodimentContract` | Honor signal units, actuator ranges, latency budgets, and MotorNerve output channels. |

The plant implementation MUST fail closed when a required physical value is
missing for the requested `ReadinessLevel`. It MUST NOT use render assets or
external import files as hidden physics authority.
