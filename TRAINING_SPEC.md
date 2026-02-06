# Kuyu Training Environment Specification (M1‑ATT)

## Purpose
Kuyu is the **learning simulator** for Manas. It generates data and injects
swappability and HF stress for MLX‑based learning. Kuyu **does not** implement
learning algorithms, and metric computation is external. This document defines
the **M1‑ATT reference suite**, not the only supported morphology.

## Training Loop (Conceptual)
Scenario + Seed
→ World Engine (Plant + Sensor/Actuator Emulation + Events)
→ Sensor Streams
→ Manas (Bundle→Gating→Trunks→Core+Reflex)
→ DriveIntent (primitive activations) + Reflex corrections
→ MotorNerve → Actuator values → Plant → Sensors …
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
- MotorNerve actuator values
- Plant attitude / ω traces
- Event schedule + seed

## Metrics (Optional / External)
Metrics are computed downstream from Kuyu logs as needed. Kuyu only guarantees
correct state evolution, logs, and fail‑fast termination metadata.

## Failure‑Aware Training (Normative)
Scenarios are **fail‑fast**. On first failure, the run terminates and the
training loop treats the run as **terminal**. Failure MUST be logged as:
- `failureReason` (enum string)
- `failureTime` (seconds from run start)

Required failure reasons:
- `simulation-integrity` (NaN/Inf or invalid state)
- `ground-violation`
- `sustained-fall`
- `safety-envelope`

Training loops MUST:
1. Stop data collection at the failure time (no “continuing past crash”).
2. Use failure as a negative signal (score penalty and/or curriculum step).
3. Persist failure metadata in exported datasets.

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
- `meta.json`: dataset metadata (scenario, seed, dt, driveCount, channelCount)
- `records.jsonl`: one JSON object per time step

Record fields:
- `time`: simulation time (seconds)
- `sensors`: array of `{channelIndex, value, timestamp}`
- `driveIntents`: array of `{driveIndex, value}`
- `reflexCorrections`: array of `{driveIndex, clamp, damping, delta}`

`meta.json` MUST include:
- `failureReason` (nullable)
- `failureTime` (nullable)

Implementation reference: `TrainingDatasetWriter` in Kuyu.

## Bundle Export
`TrainingDatasetExporter` writes one dataset per scenario (from `KuyAtt1RunOutput`
or `[ScenarioLogEntry]`) into a subdirectory named `<ScenarioId>_seed_<Seed>`.
