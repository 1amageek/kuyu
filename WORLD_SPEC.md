# World Specification (Draft)

This document defines the **canonical physics** for Kuyu. It is shared across
all training suites (swappability, HF stress, bundle/gating stress).

## Purpose
Define the simulation world rigorously for reproducible verification while allowing fast execution. The world is specified by strict physical equations, with a deterministic *negligibility policy* that can approximate small effects as zero without changing the underlying model.

## Core Principles
- **Canonical physics first**: Use strict equations as the normative definition.
- **Approximate by magnitude**: Effects can be set to zero only when their contribution is provably small under declared thresholds.
- **Deterministic and reproducible**: All parameters, thresholds, and decisions are logged and hashed.
- **Cost control without semantic drift**: Zeroing is a controlled approximation, not a different model.

---

## 0. System/Profile Architecture (Gazebo-aligned)
Kuyu mirrors Gazebo’s separation of concerns: physics, sensors, rendering, and control
are treated as distinct systems. Determinism is enforced in physics + sensor systems;
rendering may be non-deterministic.

### Core systems (required)
- PhysicsSystem: rigid-body integration, fixed Δt
- SensorSystem: IMU6 + optional sensors
- ActuatorSystem: motor dynamics, saturation, asymmetry
- EventSystem: swaps, HF stress, latency spikes

### UI systems (required)
- RenderSystem: visual inspection renderer (non-deterministic allowed)
- CommandSystem: UI / automation triggers (does not touch physics state)

### Engine compatibility (view‑only)
External engines may be attached **only as visualization or verification targets**.
The PhysicsSystem remains entirely within Kuyu; adapters are **read‑only** and
consume Kuyu state. Any “shadow physics” run in external engines must never
write back into Kuyu or affect determinism.

Baseline target:
- Apple platforms use **RealityKit** as the default render backend.
- Other engines (e.g., Unreal/Chaos) are supported via view‑only adapters and
  are not required for correctness.

### Execution order (fixed)
1. time advance
2. event injection
3. actuator update
4. physics integration
5. sensor sampling
6. control update (CUT/Manas)
7. logging + replay checks

### RenderSystem (spec detail)
- Input: read-only scene state (poses, geometry ids, materials)
- Output: visual frames / UI overlays only
- Must NOT mutate physics state or sensor outputs
- Can run at independent frame rate (e.g., 30–120 Hz)
- Must support debug overlays (axes, forces/torques, actuators, event markers)
- Must support timeline scrub/step for deterministic replay

### CommandSystem (spec detail)
- Input: operator/UI commands (run, pause, export, switch suite)
- Output: queued command intents for the scheduler
- Must NOT directly mutate physics state; all effects go through EventSystem or run lifecycle

## 1. World State and Time
- Fixed step Δt; all subsystem update periods are integer multiples of Δt.
- Deterministic execution order per step:
  time → disturbance → actuator → plant RK4 → sensor → CUT → external MotorNerve → apply → log → replay check.

## 1.1 Failure & Termination (Normative)
Failure is **fail‑fast** and terminates the scenario immediately. The world must
emit `failureReason` and `failureTime` on termination. Minimum conditions:

- **simulation‑integrity**: NaN/Inf in state, sensor output, or command.
- **ground‑violation**: position.z < groundZ (default 0).
- **sustained‑fall**: vertical velocity < -fallVelocityThreshold for ≥ fallDurationSeconds.
- **safety‑envelope**: sustained violation of tilt or |ω| limits.

These conditions are part of the world contract and are enforced during runs
used for training and evaluation.

---

## 2. Canonical Dynamics (Normative)
Translational:
```
p_dot = v
v_dot = (1/m) * (R(q) * F_body + F_world) + g(r)
```
Rotational:
```
ω_dot = I^{-1} * (τ_body - ω × (Iω))
```

All forces and torques are defined below. Numerical integration uses fixed‑step RK4 and quaternion renormalization after each step.

---

## 3. Gravity Model (Required)
### 3.1 Canonical equation
```
F = G * m * M / r^2
g(r) = G * M / r^2  (direction: toward center)
```

### 3.2 Gravity modes
- **UniformGravity**: constant vector g (near-surface approximation)
- **CentralGravity**: single primary body (GM, origin)
- **MultiBodyGravity**: sum of multiple bodies

Gravity **must be declared** in the environment, even if approximated as zero at runtime by the policy in Section 6.

---

## 4. Environment Models (Declared, Optional in Effect)
### 4.1 Atmosphere
- Parameters: airPressure (Pa), airTemperature (K)
- Modes: None / Standard / Layered

### 4.2 Wind
- Parameter: windVelocityWorld (m/s)
- Modes: None / Constant / Field

Atmosphere and wind are always declared, but may be approximated as zero if negligible (Section 6).

---

## 5. Force and Torque Set (Normative)
### 5.1 Forces
- **Gravity**: F_g = m * g(r)
- **Thrust / Propulsion**: from actuators (motor/jet/thruster)
- **Thrust scaling by density**: F_thrust ∝ ρ (if atmosphere enabled)
- **Disturbance**: defined external force inputs
- **Aerodynamic drag**: F_d = -1/2 * ρ * Cd * A * |v_rel| * v_rel
- **Lift**: F_l = 1/2 * ρ * Cl * A * |v_rel|^2
- **Buoyancy**: F_b = ρ * V * g
- **Contact / friction**: constraint‑based forces (if enabled)
- **Environment extras**: magnetic, radiation pressure, etc. (optional extensions)

### 5.2 Torques
- **Propulsion torque** (mixer geometry)
- **Aerodynamic torque** (drag/lift about COM)
- **Disturbance torque**
- **Contact torque**

All listed forces/torques are part of the canonical world definition, even if approximated as zero.

---

## 6. Negligibility Approximation Policy (NAP)
### 6.1 Rule
A force/torque may be replaced with zero **only if** its contribution is below declared thresholds.

```
if bound(F_i) < ε_F_abs OR bound(F_i) / F_ref < ε_F_rel:
    F_i = 0
else:
    F_i = F_i_strict
```

### 6.2 Thresholds
- ε_F_abs (N), ε_F_rel (ratio)
- ε_τ_abs (N·m), ε_τ_rel (ratio)

Reference scales (examples):
- F_ref = m * |g|
- τ_ref = max(armLength * maxThrust, yawCoeff * maxThrust)

### 6.3 Hysteresis (recommended)
To avoid discontinuity:
```
if |F_i| > ε_on -> compute
if |F_i| < ε_off -> zero
(ε_off < ε_on)
```

### 6.4 Determinism requirement
All thresholds and evaluation rules are logged and hashed. The same input yields the same zeroing decisions.

---

## 7. Logging & Reproducibility (Required)
The following are required in logs and config hashes:
- Gravity model + parameters
- Atmosphere model + parameters
- Wind model + parameters
- NAP thresholds and hysteresis values
- Any enabled/disabled effect derived from NAP decisions

---

## 8. Baseline Configuration (Phase 0)
- Gravity: UniformGravity (Earth default g)
- Atmosphere: declared, but negligible (treated as zero)
- Wind: declared, but negligible (treated as zero)
- NAP thresholds tuned for speed and stability

---

## 9. Future Extensions
- Multi‑body gravity for orbital simulation
- Layered atmosphere with density varying by altitude
- Time‑varying wind fields
- Contact and surface interaction models

---

## Summary
The World is **always defined by strict equations**. Performance is achieved by a **deterministic negligibility policy** that can safely reduce small contributions to zero without changing the underlying model or breaking reproducibility.

---

## Benchmark Notes (2026-02-01)
Measured on macOS 26.2 (arm64e), single scenario (5s, Δt=0.001), repeated 100 times.

- Baseline (gravity + disturbances + IMU noise, no atmosphere/wind): ~154.48x realtime (154,480 steps/s)
- + Drag/ buoyancy/ angular damping + wind: ~143.20x realtime (143,196 steps/s)
- + Thrust density scaling + simple lift: ~119.10x realtime (119,101 steps/s)

These values are reference points for regression checks when expanding the world model.
