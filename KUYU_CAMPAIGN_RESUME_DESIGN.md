# Kuyu Learning Campaign — Pause / Resume Design

Crash-safe pause and in-place resume for the GA learning campaign
(`run-learning-campaign` / `evolve-manas`).

## 0. Goal State (Definition of Done)

The feature is **done** when ALL of the following hold. Partial delivery is not
acceptable — every item below is in scope for this work.

1. **Crash recovery.** A campaign killed by `SIGKILL` / power loss / Mac restart
   mid-run can be resumed in place and continues from the last *durably committed*
   generation. No artifact-index dependency on a graceful finalize.
2. **Graceful stop.** `SIGINT` / `SIGTERM` (CLI) and the UI pause control stop the
   campaign at a generation boundary, mark it `paused`, and exit cleanly.
3. **Tier-0 exact resume.** A resumed run produces **bit-identical** candidates and
   fitness from the resume point onward, compared to an uninterrupted run with the
   same plan. Proven by an automated determinism-equivalence test.
4. **Fail-closed integrity.** A corrupt or torn checkpoint never silently rolls back
   or silently diverges. It fails with an explicit, named error; the caller chooses
   the recovery (`--resume-from-generation N`, `--allow-divergent-resume`, `--force`).
5. **Multi-seed.** A multi-seed campaign resumes by skipping committed seeds and
   continuing the first non-terminal seed from its last committed generation.
6. **No regressions / rule compliance.** `kuyu verify` (Tier-0 determinism + A1
   baseline) passes unchanged. No `try?`, no silent fallback, typed errors,
   one-type-per-file. `xcodebuild` builds; new tests pass.

Explicitly **out of scope** (documented future work, performance-only, does not
affect the goal above):

- Intra-generation candidate-level resume (re-using already-evaluated candidate
  bundles from an abandoned in-flight generation). At most one generation of
  recompute is accepted by design.

## 1. Why the current state is insufficient

`EvolutionRunOrchestrator.runGenerations` accumulates `allCandidates` / `allFitness`
/ `allGenerations` in memory and only writes `candidates.jsonl` / `fitness.jsonl` /
`generations.jsonl` / `learning-campaign-summary.json` at **finalize**
(`EvolutionArtifactWriter.write`). A hard kill before finalize leaves no index, so
`LearningCampaignContinuationResolver` (which reads those files) cannot resume.
Per-candidate model bundles are written incrementally, but the fitness index needed
to pick "where we were" is lost.

```
current: [gen0][gen1]...[genN]──finalize──► candidates/fitness/summary written
                      ▲ SIGKILL here ⇒ nothing resumable
```

## 2. Key enabler — RNG is re-derived per generation

`runGenerations` seeds each generation's variation with
`commonRandomSeed(config:, generationIndex: generationIndex + 1)` — a value derived
**deterministically from the generation index**, not from a live, evolving PRNG.

Consequence: we do **not** need to serialize RNG state. Restoring the GA *control
state* at a generation boundary and re-entering the loop at `N+1` reproduces the
exact same randomness, hence Tier-0 exact resume.

## 3. Granularity — generation boundary is the commit barrier

```
gen N evaluated ─┬─ ① write generation-N slice (candidates/fitness/traces) atomically
                 ├─ ② write resume/generation-N.state.json atomically  ◄── COMMIT POINT
                 └─ ③ early-stop check / produceNextGeneration(N+1)   (deterministic)
```

- A generation `N` is **durably committed** iff `resume/generation-N.state.json`
  exists, validates, and its referenced slice files and population bundles validate.
- Anything after the highest committed generation (a torn slice, half-written
  candidate bundles from an in-flight `N+1`) is **discarded and recomputed**. Because
  generation randomness is re-derived, the recomputation is bit-identical.
- Reuses the existing atomic-write primitive (`ManasMLXTemporaryBundleURL`,
  temp-dir → `moveItem`). No new durability infrastructure.

## 4. State to persist at each generation boundary

From the live variables of `runGenerations`, persist only what cannot be re-derived:

| State | Persist | Reason |
|---|---|---|
| `currentPopulation` (genome refs) | ✅ required | seeds generation `N+1`; stored as bundle relative paths |
| `mutationRate` / `mutationNoiseScale` | ✅ required | adaptive, generation-dependent (`nextMutationSchedule`) |
| `earlyStoppingState` | ✅ required | depends on fitness trajectory (requires `Codable`) |
| `incumbentCandidateID` / `incumbentFitness` | ✅ required | sticky |
| `bestAcceptedFitness` | ✅ required | running best |
| `allFitness` | ✅ via `fitness.jsonl` | novelty / QD archive input; restored by re-reading |
| `allCandidates` / `allGenerations` / `allTraces` | ✅ via jsonl | restored by re-reading |
| RNG state | ❌ not needed | re-derived from `commonRandomSeed(generationIndex)` |
| gateReport / parent IDs | ❌ not needed | recomputed from restored `allFitness` + generation record |

### `resume/generation-<n>.state.json` schema (v1)

```jsonc
{
  "schemaVersion": 1,
  "seedValue": "1", "campaignSeed": 1,
  "lastCommittedGeneration": N,            // next generation to run is N+1
  "population": [ { "candidateID", "genomeID", "parentCandidateIDs",
                    "checkpointRelPath", "isIncumbent" } ... ],
  "mutationRate": 0.12, "mutationNoiseScale": 0.03,
  "earlyStopping": { "bestFitness": …, "generationsWithoutImprovement": … },
  "incumbentCandidateID": "…", "incumbentFitness": …,
  "bestAcceptedFitness": { … FitnessSummary … },
  "planHash": "…", "buildFingerprint": "…",   // §8 integrity guard
  "contentHash": "…"                           // self-integrity
}
```

## 5. Artifact layout additions

```
<artifact-root>/
  learning-campaign-plan.json                 (existing)
  RUN_CONTROL/                                 NEW
    STOP                                       NEW external stop sentinel
    status.json                                NEW running|paused|completed|failed + per-seed progress
  seeds/seed-<s>/evolution/
    candidates.jsonl / fitness.jsonl / generations.jsonl    (existing; committed per generation)
    generations/generation-<n>/<candidateID>/               (existing: candidate bundles)
    generations/generation-<n>/_slice/{candidates,fitness,traces}.jsonl   NEW per-generation slice
    resume/generation-<n>.state.json                        NEW control-state snapshot (= commit point)
```

## 6. Stop mechanism (cooperative cancellation)

Existing checkpoints already exist: `Task.isCancelled` (loop top) and
`Task.checkCancellation()` (before `produceNextGeneration`).

```
trigger              propagation                         behavior
─────────────────────────────────────────────────────────────────────────
Ctrl-C / SIGTERM     signal handler cancels root Task    detected at gen boundary
(CLI)                 + writes RUN_CONTROL/STOP            → durable up to last committed gen
UI Pause             TrainingLoopController (existing)    → terminalState = .paused
                      → same cancel                        → status.json = paused, exit 0
Mac restart (KILL)   no handler, instant death            → not finalized, but
                                                            resume/*.state.json already committed
                                                            → resume from highest committed gen
```

- New terminal state `EvolutionRunTerminalState.paused` (distinct from `.cancelled`;
  `paused` ⇒ resumable).
- On stop, the in-flight generation is abandoned (recomputed deterministically on
  resume — at most one generation lost). `--stop-after-generation` finishes the
  current generation first.

## 7. Resume mechanism

```
kuyu run-learning-campaign --artifact-root <root> --resume
   │
   ├─ read status.json / manifest → resumable? (paused | running-but-dead with ≥1 state.json)
   ├─ per seed: resolve highest committed generation N (state.json + slices + bundles validate)
   ├─ re-read fitness/candidates/generations.jsonl → restore archives
   ├─ load control state + population bundles from state.json
   └─ re-enter loop at generationIndex = N+1
        → commonRandomSeed(N+1) matches the uninterrupted run → bit-identical onward
```

- `LearningCampaignContinuationResolver` gains a third mode
  `.inPlaceLatestGeneration` (alongside `bestCandidate` / `finalCheckpoint`).
- `TrainingResumeRequest.source` gains `.inPlace(artifactRoot)`.
- Writing into an existing root without `--resume` is **fail-closed**: "artifact root
  contains an incomplete run; pass --resume to continue or --force to discard".

## 8. Integrity & no-silent-fallback policy

| Event | Behavior (no silent fallback) |
|---|---|
| Highest committed `state.json` / bundle fails validation | **explicit throw** naming the corrupt file; never silently roll back. `--resume-from-generation N` selects an explicit rollback point. |
| Slice jsonl torn-write | Inside a committed generation → **explicit failure**. In an uncommitted generation → discard & recompute (normal path). |
| Binary / plan changed between pause and resume | `buildFingerprint` / `planHash` mismatch is **detected and fails**. `--allow-divergent-resume` explicitly downgrades to Tier-1 with a logged warning. |

## 9. Determinism contract

A resumed run is bit-identical from `N+1` onward iff: (a) same build, (b) same
plan/config, (c) `commonRandomSeed` derivation unchanged, (d) restored bundles
bit-identical, (e) evaluation deterministic (existing Tier-0 requirement). (a)/(b)
are guarded by the fingerprints in §8; violations fail closed or downgrade
explicitly, never silently.

## 10. Multi-seed

`status.json` carries a per-seed terminal state. Resume skips terminal seeds
(completed / rejected / failed), resumes the first non-terminal seed from its highest
committed generation, then runs the remaining seeds fresh.

## 11. Test plan

```
T1 [Tier-0 equivalence] run G generations uninterrupted → record canonical jsonl.
     Run with a forced pause at gen K, then resume → assert resumed jsonl is
     bit-identical to canonical. (This is the acceptance line.)
T2 [crash injection] simulate kill mid-generation → resume → bit-identical;
     recompute ≤ 1 generation; no corruption.
T3 [torn-write] truncate trailing slice / state.json → resolve highest VALID
     committed generation, or fail closed if corruption is within a committed gen.
T4 [multi-seed] pause during seed 2 → resume finishes seed 2 + seeds 3..N; seed 1 intact.
T5 [stop semantics] SIGINT → terminalState .paused, status paused, exit 0, resume works.
T6 [fail-closed] corrupt committed bundle → explicit named error, no silent rollback.
```

## 12. Implementation phases

```
Phase 1  per-generation resume checkpoint (state.json + slices, atomic)
         + --resume in-place + SIGKILL recovery (highest committed gen)
         + single & multi seed + T1/T2 determinism tests
Phase 2  SIGINT/SIGTERM graceful → .paused / UI pause integration / T5
Phase 3  fingerprint guards / --resume-from-generation / --allow-divergent-resume / T3,T4,T6
Phase 4  (out of scope) intra-generation candidate-eval cache — performance only
```

## 13. Touch points (existing code)

- `kuyu-training/Sources/KuyuTraining/EvolutionRunOrchestrator.swift` — `runGenerations`
  loop body (checkpoint hook), `finish` (paused finalize), cancellation paths.
- `kuyu-training/Sources/KuyuTraining/EvolutionArtifacts.swift` — incremental slice
  writer; `EvolutionRunTerminalState` (+ `.paused`).
- New: `EvolutionGenerationResumeState` (Codable state), `EvolutionResumeCheckpointStore`
  (atomic write/read/validate), `EvolutionRunControl` (STOP sentinel + status.json).
- `kuyu-mlx/Sources/KuyuMLX/LearningCampaignContinuationResolver.swift` —
  `.inPlaceLatestGeneration` mode.
- `kuyu-mlx/Sources/KuyuMLX/ManasMLXTrainingRunExecutor.swift` /
  `TrainingResumeRequest` — `.inPlace` source.
- `kuyu/Sources/KuyuCLI/KuyuCLI.swift` — `--resume`, `--resume-from-generation`,
  `--allow-divergent-resume`, `--force`, signal handling.
