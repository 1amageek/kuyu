# Kuyūkai Specification (Verification World)

## Scope
Kuyūkai defines a deterministic simulation and verification environment for control systems.
It does **not** define Manas semantics or symbolic control events.

## Logging & Configuration
Kuyūkai integrates `swift-log` and `swift-configuration` for runtime controls.
Configuration is optional and only applied when explicitly provided.
Environment keys:
- `KUYU_LOG_LEVEL` (trace/debug/info/notice/warning/error/critical; default: info)
- `KUYU_LOG_LABEL` (default: kuyu)
- `KUYU_LOG_DIR` (optional log output directory)

Runtime bootstrap uses `KuyukaiRuntime` (or `KuyukaiConfigLoader` with a `ConfigReader`) to load configuration and create a logger.

## Determinism Tiers
- **Tier0**: bitwise determinism (exact log match).
- **Tier1**: epsilon determinism (declared tolerances).
- **Tier2**: statistical determinism (invariants over seed sets; not for M1 gating unless declared).

Validation reports must always declare tier and tolerances.

## Time Model and Execution Order
- Fixed base step Δt; all subsystem periods are integer multiples.
- Required update order per StepWorld(Δt):
  time → disturbance → actuator → plant RK4 → sensor → CUT → external DAL → apply → log → replay check.

## Plant, Actuators, and Sensors
- 6‑DOF quadrotor with RK4 integration; quaternion renormalized every step.
- Motor first‑order dynamics and mixer matrix.
- IMU6 sensor with numeric channelIndex 0..5 (gyro x/y/z, accel x/y/z).
- Seeded noise, bias, drift, and delay; **no state estimates** exposed.

## World Environment Parameters
Kuyūkai supports declaring world parameters even when the current simulation ignores them for cost.
The environment is modeled as a structured parameter set with explicit usage flags:

- gravity (m/s^2)
- windVelocityWorld (m/s)
- airPressure (Pa)
- airTemperature (K)
- usage flags: useGravity / useWind / useAtmosphere

Default behavior in the baseline engine:
- parameters are recorded and hashed in config for reproducibility
- gravity applies when useGravity=true
- wind and atmosphere apply when useWind/useAtmosphere=true (drag, buoyancy, lift, thrust scaling)

## Modeling Formats
Kuyu separates physics, rendering, and printing formats:
- Physics model: URDF or SDF
- Render mesh: glTF/GLB (preferred), OBJ or USDZ
- Print mesh: STL or 3MF

See `MODELING.md` and `RobotModelDescriptor` for the binding structure.

## Disturbances
Continuous, seeded, reproducible disturbances.
For M1, torque disturbances are mandatory.

## CUT Interface (Black‑Box)
Inputs: (channelIndex, scalar, timestamp).
Outputs: actuator commands or drive intents (if DAL externalized).
No ground truth, no simulator internals, no symbolic tokens.

## Reference Model (Baseline)
Kuyūkai‑QuadRef v0:
m=1.00 kg, I=diag(0.005,0.005,0.009), L=0.12 m, τ_m=0.030 s,
f_max=6.0 N, κ_yaw=0.020 N·m/N, g=9.80665, Δt=0.001 s.

## Scenario Suite KUY‑ATT‑1 (M1)
Duration 20 s, seeds {1001,1002,1003} with safety envelope:
ω_safe_max=20 rad/s, tilt_safe_max=60°, sustained violation threshold=0.200 s.
SCN‑1..5 cover hover start, impulse shock, sustained torque, sensor drift, actuator degradation.

## Optional Strict Suite (B2)
KUY‑ATT‑PERM adds channel permutations for strict robustness.

## Logging Requirements
Must log tier/tolerances, scenario ID, seed, config hash, Δt, sensor channels,
actuator commands, motor thrust, safety traces, disturbances, and replay residuals.

## MLX‑Enabled Profiles
If the CUT enables MLX‑based learning inside the DAL, the validation report must
declare a distinct profile/badge for MLX‑enabled runs. MLX‑disabled remains the default
baseline profile for determinism and M1 gating.
