# Kuyu Training Environment Specification (M1‑ATT)

## Purpose
Kuyu is the **learning simulator** for Manas. It generates data and injects
swappability and HF stress for Mojo-based learning. `kuyu-training` owns portable
training contracts and datasets but does not implement optimizer kernels;
concrete numerical algorithms live in Manas Mojo products and are composed by
`kuyu-mojo`. Scenario reward, cost, failure, and task-quality semantics remain
owned by `kuyu-scenarios`; derived analysis may be computed downstream. This
document defines the **M1-ATT reference suite**, not the only supported
morphology.

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

- **Supervised / BC data path**: runs scenarios and exports demonstration
  records. It is not an RL algorithm.
- **RL rollout harness**: exposes environment episodes through
  `reset / step / reward / done / truncated / info`, collects serial or
  parallel rollouts, and exports reward-aware artifacts. The harness is not PPO
  or another optimizer.

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
- treat one environment step as one control-period decision with the exact
  causal transition `O[k] -> A[k] -> O[k+1]`,
- preserve a unique policy decision ID, action-source observation/time, policy
  action, applied actuator command, and outcome for every decision,
- aggregate reward over physics ticks inside the control period and stop at the
  first failing physics tick,
- sort merged parallel artifacts by `scenarioId`, `seed`, and `workerIndex`,
- reject cancellation, max-step, and wall-time limit termination as typed errors
  unless an explicit cancelled artifact contract is introduced later.

Shared mutable model state is prohibited in parallel rollout. Each parallel
policy execution consumes an immutable checkpoint snapshot and owns its
recurrent state.

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
- Optional KuyuDataset v7 export for Mojo training

M2+ benchmark bundles SHOULD include:
- deterministic replay manifest,
- task completion summary (success/failure, time-to-complete),
- control quality summary (recovery/overshoot/safety-envelope violations),
- planner degradation test summary (normal vs delayed/disconnected).

## Persisted Dataset Contract

The normative persisted contract is `KuyuDataset` schema version 7, defined in
`LEARNING_SYSTEM_SPEC.md`. It contains `manifest.json` plus streamable
`records.jsonl` envelopes and uses purpose-specific record types instead of one
optional-field aggregate.

Runtime training accepts v7 only. Versions 3 through 6 are legacy inspection
inputs and may enter the current contract only through an explicit offline
migration command. A runtime loader MUST NOT decode a legacy dataset and infer
missing causal, action-space, terminal, trajectory, or behavior-policy facts.
The migrator either preserves a fully proved target record, downgrades a complete
causal transition to off-policy use, or rejects it with typed missing facts. It
never fabricates on-policy evidence.

The required record kinds are:

| Record kind | Record relation | Consumer contract |
|---|---|---|
| `demonstration` | `O[label] -> A[teacher]` | Supervised actor training only |
| `onPolicyTransition` | `O[k], A[k], E[behavior] -> O[k+1]` | PPO and constrained PPO |
| `offPolicyTransition` | `O[k], A[k] -> O[k+1]` | Replay algorithms and analysis |
| `worldTransition` | `X[k], U[actuator], events -> X[k+1]` | World-model residual training |

Policy action, realized DriveIntent/Reflex output, and actuator command are
different typed spaces. On-policy records require behavior-distribution
evidence from the action-producing forward pass. Trajectory continuity,
bootstrap permission, and trace continuation are explicit facts; file or array
order does not imply continuity.

Temporal policies also declare their execution context. A fixed-history policy
replays the exact bounded window; a recurrent policy records segment-initial
state, burn-in, and loss masks. GAE is computed over whole validated segments
before minibatch partition and bootstraps from `O[k+1]`, never the source state.

`timeStep` is the nominal control period. The manifest physics step and control
period tick count define it exactly. A fail-fast terminal interval may be
shorter and MUST record its actual duration and completed physics tick count.

Readers decode records incrementally. Writers stream records into a staging
directory, calculate count/digest, write the manifest last, validate the staged
artifact, and atomically rename it into place.

Implementation MUST NOT claim conformance until the v7 producer-consumer,
trajectory-boundary, and behavior-evidence gates in `LEARNING_SYSTEM_SPEC.md`
pass.

## Learned World-Model Admission

There is no active learned world-model product. A predictive model may be added
only after a measured planning or sample-efficiency requirement shows that the
authoritative Kuyu physics path is insufficient. Such a model belongs to Manas
as a Mojo model family; Kuyu may provide causal datasets and evaluate predictions
against physics replay, but it does not own the model or its optimizer.

## Bundle Export
`TrainingDatasetExporter` writes one dataset per scenario (from `KuyAtt1RunOutput`
or `[ScenarioLogEntry]`) into a subdirectory named `<ScenarioId>_seed_<Seed>`.

## RoArm M1 Arm and Gripper Smoke Training

RoArm M1's first supported manipulator training goal is
`roarm-m1-arm-gripper-target-tracking-v1`. It is a camera-free proprioceptive
task scoped to `ReadinessLevel.dynamicSimulation`.

The task records 25 observation channels:

| Channel group | Count | Meaning |
|---|---:|---|
| Position | 5 | Current arm axis angle or gripper clamp angle |
| Velocity | 5 | Current arm axis velocity or gripper clamp velocity |
| Target error | 5 | Target arm/gripper value minus current value |
| Lower-limit margin | 5 | Distance to each lower arm/gripper limit |
| Upper-limit margin | 5 | Distance to each upper arm/gripper limit |

Completion requires finite records, zero joint-limit violations, non-trivial
motion, and target-tracking error inside the smoke envelope. The command
`train-roarm-m1-arm-gripper` writes:

- `roarm-m1-arm-gripper-training-report.json`
- `dataset/meta.json`
- `dataset/records.jsonl`
- `manas/roarm-m1-arm-gripper.manasbundle`

The records include dense reward values, teacher arm/gripper target actions,
model-based state tuples, and optional achieved-goal relabel records. The Manas
bundle is a smoke supervised checkpoint for the 5-drive arm/gripper contract.
Full campaign orchestration remains `designOnly`; contact, grasping, and
hardware parity remain gated separately.
