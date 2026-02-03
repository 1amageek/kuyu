# Kuyu Training Environment Specification — v2.4 (M1‑ATT)

## Purpose
Kuyu is the **training world** for Manas. It generates data, injects
swappability and HF stress, and reports metrics. Kuyu **does not** implement
learning algorithms.

## Training Loop (Conceptual)
Scenario + Seed
→ World Engine (Plant + Sensor/Actuator Emulation + Events)
→ Sensor Streams
→ Manas (Bundle→Gating→Trunks→Core+Reflex)
→ DriveIntent + Reflex corrections
→ DAL → Actuators → Plant → Sensors …
→ Logs + Metrics

## Required Suites (M1)
- **Suite‑0**: Warmup (no swaps)
- **Suite‑1**: Sensor swappability
- **Suite‑2**: Actuator swappability
- **Suite‑3**: Reflex HF stress
- **Suite‑4**: Bundle/Gating stress
- **Suite‑5**: Combined

## Event Injection
### Sensor swaps
Gain, bias, noise, delay, bandwidth, dropout, saturation, contamination.

### Actuator swaps
Max output, time constant, gain, rate limit, deadzone, asymmetry.

### HF stress
Impulse torque, vibration, brief sensor glitches, brief saturation, latency spikes.

## Logs (Training‑critical)
- Sensor streams (post emulation)
- NerveBundle outputs + gating coefficients
- Trunks (Energy / Phase / Quality)
- DriveIntent
- Reflex corrections
- DAL actuator commands
- Plant attitude / ω traces
- Event schedule + seed

## Metrics (M1)
- No‑sustained‑failure
- Recovery time after swaps
- Overshoot and violation budget
- HF stability score
- Bundle/Gating stability proxy

## Reproducibility
- Deterministic seed schedule
- Config hash recorded per run
- Scenario manifest stored with logs

## Output Artifacts
- Scenario logs per seed
- Validation summary with aggregate metrics
- Optional dataset export for MLX training

## Dataset Export Format (JSONL)
Kuyu exports a training dataset as a directory containing:
- `meta.json`: dataset metadata (version, scenario, seed, dt, driveCount, channelCount)
- `records.jsonl`: one JSON object per time step

Record fields:
- `time`: simulation time (seconds)
- `sensors`: array of `{channelIndex, value, timestamp}`
- `driveIntents`: array of `{driveIndex, value}`
- `reflexCorrections`: array of `{driveIndex, clamp, damping, delta}`

Implementation reference: `TrainingDatasetWriter` in Kuyu.

## Bundle Export
`TrainingDatasetExporter` writes one dataset per scenario (from `KuyAtt1RunOutput`
or `[ScenarioLogEntry]`) into a subdirectory named `<ScenarioId>_seed_<Seed>`.
