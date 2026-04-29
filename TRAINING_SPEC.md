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

## Execution Modes (Normative)
Kuyu separates two training-world execution modes:

- **Supervised / BC loop**: runs scenarios, exports datasets, and calls the
  Manas/MLX training bridge. This is the existing `kuyu loop` path and is not an
  RL algorithm.
- **RL rollout harness**: exposes environment episodes through
  `reset / step / reward / done / truncated / info`, collects serial or
  parallel rollouts, and exports reward-aware artifacts. This is the `kuyu
  rollout` path and is not PPO, Dreamer, or another optimizer.

Both modes use Kuyu physics as the source of truth and must preserve
fail-fast failure metadata. Manas control protocol and model internals remain
outside Kuyu's training-world responsibility.

## Required Suites (M1)
- **Suite‑0**: Warmup (no swaps)
- **Suite‑1**: Sensor swappability
- **Suite‑2**: Actuator swappability
- **Suite‑3**: Reflex HF stress
- **Suite‑4**: Bundle/Gating stress
- **Suite‑5**: Combined

## Required Extension Suites (M2+)
M1 suites remain mandatory. For M2+, Kuyu MUST support additional suites:
- **Suite‑6**: Long-horizon task programs (planner-driven descending channels).
- **Suite‑7**: Morphology transfer runs (descriptor changes with shared task intent).
- **Suite‑8**: Partial observability + delay + disturbance combined stress.

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
- Actuator telemetry snapshots (per-channel values and identifiers)
- MotorNerve trace (raw/saturated/rate-limited outputs where available)
- Plant attitude / ω traces
- Event schedule + seed

M2+ runs MUST additionally log:
- planner command events and applied descending channel snapshots,
- Manas upward summary snapshots (`salience`, `risk`, `uncertainty`, `constraintPressure`, `recoveryState`),
- arbitration decisions for descending/reflex conflicts (selected source + reason),
- fallback/autocorrection transitions with `from` / `to` / `reason`,
- memory recall/apply events (if memory integration is enabled),
- modality synchronization metadata (`timebase`, skew, timestamp source),
- descriptor/model identifiers required for cross-run comparability,
- latency budget violations (`path`, `budgetMs`, `observedMs`, `time`, `reason`).

## Metrics (Optional / External)
Metrics are computed downstream from Kuyu logs as needed. Kuyu only guarantees
correct state evolution, logs, and fail‑fast termination metadata.

## RL Rollout Contract (M1.5/M1.6)
The rollout harness MUST:
- construct one environment per scenario/seed execution,
- construct one policy instance per worker,
- keep the primary action path as `DriveIntent`,
- reserve direct actuator actions for teacher/test escape hatches,
- sort merged parallel artifacts by `scenarioId`, `seed`, and `workerIndex`,
- reject cancellation, max-step, and wall-time limit termination as typed errors
  unless an explicit cancelled artifact contract is introduced later.

Shared `ManasMLXModelStore` is prohibited in parallel rollout. MLX parallel
policy execution requires M2 worker snapshots or an actor pool.

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

M2+ reproducibility artifacts MUST include:
- descriptor hash,
- code revision identifier,
- suite version,
- planner profile identifier (if planner is enabled),
- latency budget profile identifier (or explicit budget values hash).

## Output Artifacts
- Scenario logs per seed
- Validation summary with aggregate metrics
- Optional dataset export for MLX training

M2+ benchmark bundles SHOULD include:
- deterministic replay manifest,
- task completion summary (success/failure, time-to-complete),
- control quality summary (recovery/overshoot/safety-envelope violations),
- planner degradation test summary (normal vs delayed/disconnected).

## Dataset Export Format (JSONL)
Kuyu exports a training dataset as a directory containing:
- `meta.json`: dataset metadata (scenario, seed, dt, driveCount, channelCount)
- `records.jsonl`: one JSON object per time step

`TrainingDatasetMetadata.currentSchemaVersion` is `2` for M1.6. Readers MUST
continue to decode schema version 1 by defaulting absent optional fields.

Record fields:
- `time`: simulation time (seconds)
- `sensors`: array of `{channelIndex, value, timestamp}`
- `driveIntents`: array of `{driveIndex, value}`
- `reflexCorrections`: array of `{driveIndex, clamp, damping, delta}`
- M1.6 rollout records additionally MAY include `reward`, `done`, `truncated`,
  `episodeId`, and `policyId`.
- M2 world-model records additionally MAY include `physicsState`,
  `actualState`, `actionValues`, and `continueValue`. These fields are required
  for `StateWorldModel` residual training and remain optional for schema v1/v2
  backward compatibility.

`meta.json` MUST include:
- `failureReason` (nullable)
- `failureTime` (nullable)
- for rollout datasets: `episodeId`, `policyId`, `rewardSum`, `done`,
  `truncated`, `terminalReason`, and `rewardDescriptor`.

Implementation reference: `TrainingDatasetWriter` in Kuyu.

## M2 World-Model and Imagination Smoke
`train-world-model` trains two artifacts from rollout datasets:
- a Manas Core world-model checkpoint used by Manas training smoke paths,
- a Kuyu `StateWorldModel` residual checkpoint used as a validation gate.

`imagine-train` MUST validate the `StateWorldModel` checkpoint when it is
declared in the world-model manifest. Validation failure blocks publication of
the Manas imagination checkpoint and is treated as a typed error. Kuyu does not
own the imagination optimizer; it only validates the world-model artifact and
orchestrates the smoke path into Manas.

## Bundle Export
`TrainingDatasetExporter` writes one dataset per scenario (from `KuyAtt1RunOutput`
or `[ScenarioLogEntry]`) into a subdirectory named `<ScenarioId>_seed_<Seed>`.
