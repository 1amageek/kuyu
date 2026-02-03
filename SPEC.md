# Kuyu Specification — v2.4

## Purpose (Normative)
Kuyu is a **training world** for Manas, not a general‑purpose simulator.
It injects swappability events and HF stressors while keeping runs reproducible.

## Core Principles
- Training‑first, quadcopter‑first (attitude stabilization only).
- Same‑type swappability is a first‑class event.
- Reflex‑aware HF stress (impulse/vibration/glitch/latency spike).
- Bundle/Gating stress (salience and normalization shocks).

## Interface Boundary
- Inputs: sensor streams only (no ground truth).
- Outputs: DriveIntent + Reflex corrections → DAL → actuator commands.

## World Engine (Baseline)
- Fixed Δt, multi‑rate as integer multiples.
- Quadcopter attitude dynamics with IMU sensor emulation.
- Actuator lag, saturation, asymmetry models.
- Disturbances: wind torque, impulses, vibration.

## Swappability & Stress Events
- Sensor swaps: gain/bias/noise/delay/bandwidth/dropout changes.
- Actuator swaps: max output, time constant, gain, deadzone shifts.
- HF stress: impulse torque, vibration, brief glitches, latency spikes.

## Evaluation Metrics (Normative)
- No‑sustained‑failure.
- Recovery time after swaps.
- Transient overshoot and violation budgets.
- HF stability score (chatter/oscillation/saturation cascades).

## Logs (Minimum)
Sensors, DriveIntent, Reflex outputs, actuator commands,
attitude/omega traces, event schedule + seeds, and safety traces.

## Training Environment
See `TRAINING_SPEC.md` for training loop contracts, required suites, and
dataset/metric requirements for M1.

## World Physics Specification
Canonical physics + deterministic negligibility policy live in `WORLD_SPEC.md`.

## System/Plugin Architecture (Gazebo-aligned)
Kuyu mirrors Gazebo’s separation of concerns: physics, sensors, rendering, and control
are treated as distinct systems. Determinism is enforced in physics + sensor systems;
rendering is allowed to be non-deterministic.

Required systems:
- PhysicsSystem (fixed Δt, deterministic integrator)
- SensorSystem (IMU6 minimum; noise/bias/delay models)
- ActuatorSystem (motor lag/saturation/asymmetry)
- EventSystem (swaps, HF stressors, latency spikes)

Optional systems:
- RenderSystem (RealityKit or other renderer)
- CommandSystem (UI and external control)

World → System order is fixed and versioned in `WORLD_SPEC.md`.

### RenderSystem (required for KuyuUI)
- KuyuUI must use RenderSystem as a pure consumer of scene state.
- Rendering must never write to physics or sensor state.

### CommandSystem (required for KuyuUI)
- KuyuUI issues run/train/export commands through CommandSystem only.
- Commands enqueue into EventSystem / scheduler, never mutate physics directly.
