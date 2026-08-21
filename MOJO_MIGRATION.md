# Kuyu Mojo Migration Ledger

Status: active, non-released destructive migration.

This ledger records implementation state. Normative behavior remains in
`SPEC.md` and `LEARNING_SYSTEM_SPEC.md`; package ownership remains in
`../KUYU_PACKAGE_ARCHITECTURE.md`.

## Completion Claim

Kuyu is not Mojo-backed yet. The current application and training runtime still
execute through `kuyu-mlx`. KuyuPhysics now owns a closed, validated canonical
dynamics program and a Swift Float64 reference executor, while `swift-mojo`
provides borrowed-buffer, synchronous opaque-session, session-owned
Float32-buffer, and schema-5 Linux artifact foundations. These are not a Kuyu
Mojo training runtime or proof of accelerator execution. Cross-executor
numerical parity, learning qualification, native Jetson Swift/CUDA execution,
and hardware-in-the-loop behavior remain unverified until their gates are
executed and recorded here.

## Final Usage Contract

The conforming application depends on a backend-neutral training API. Backend
selection is explicit deployment configuration, not a runtime fallback chain.

```swift
let request = try TrainingRunRequest(project: project, plan: plan)
let executor: any TrainingRunExecuting = try KuyuRuntimeFactory.mojo(
    deployment: deployment,
    capabilities: requiredCapabilities
)
let handle = try await executor.start(request)
```

The application never imports a concrete accelerator module. A worker receives
an immutable request and checkpoint snapshot, creates one Mojo session, owns its
device buffers for the attempt lifetime, and publishes only validated Kuyu
artifacts.

```mermaid
flowchart LR
  UI["CLI / UI intent"] --> API["KuyuTraining API"]
  API --> Worker["Attempt-owned worker"]
  Worker --> Runtime["KuyuMojoTrainingRuntime"]
  Runtime --> Bridge["swift-mojo ABI"]
  Bridge --> Device["CPU / Metal / CUDA"]
  Runtime --> Artifacts["KuyuDataset v7 + evidence"]
  Artifacts --> Gates["Validation and promotion gates"]
```

## Confirmed Current Facts

| Fact | Evidence | Consequence |
|---|---|---|
| The application directly consumes `KuyuMLX` | `../kuyu-app/Package.swift` and `../kuyu-app/Sources` imports | App cutover is blocked until a backend-neutral runtime facade exists |
| The backend package exposes fourteen MLX products | `../kuyu-mlx/Package.swift` | Migration must classify semantic ownership before moving code |
| The reference quadrotor force, derivative, and observable equations are closed SSA operation graphs with validated layouts, shapes, units, differentiability propagation, fidelity partitions, integration stages, and a stable digest | `../kuyu-physics/Sources/KuyuPhysics/Canonical`, `../kuyu-physics/Sources/KuyuPhysics/Plant/ReferenceQuadrotorCanonicalProgram.swift` | The Swift Float64 path is the semantic reference consumed by Plant and IMU; Mojo executors must consume this program rather than copy equations |
| The canonical integrator selects the declared integration scheme and evaluates graph-derived RK4 derivatives; RK4 stage arithmetic remains the Swift Float64 reference implementation | `../kuyu-physics/Sources/KuyuPhysics/Plant/ReferenceQuadrotorCanonicalIntegrator.swift` | P3 must match every declared projection stage and the reference trace before accelerator promotion |
| `swift-mojo` proves scalar/borrowed calls, synchronous session, and session-owned host Float32-buffer lifecycle with exact-count synchronous host copies on universal macOS; it also cross-generates a schema-5 aarch64 Linux static artifact bundle | `/Users/1amageek/Desktop/swift-mojo/docs/REQUIREMENTS.md`, `docs/ADR-0007-OPAQUE-RUNTIME-SESSION-ABI.md`, and `docs/ADR-0008-NON-APPLE-STATIC-LIBRARY-ARTIFACTS.md` | Attempt-owned CPU session/resource composition, transfer ABI, and Linux packaging are available; native Jetson link/run and MAX-backed Metal/CUDA allocation/synchronization still precede Kuyu cutover |
| Manas exposes MLX-specific model/runtime/training products | `../manas/Package.swift` | Manas model structure must gain a portable Mojo implementation without moving model ownership into Kuyu |

## Source Ownership Migration

| Current source target | Final owner | Action |
|---|---|---|
| `KuyuMLXCore` | `swift-mojo` and `KuyuMojoCore` | Move generic ABI/ownership/artifact logic upstream; keep only Kuyu capability and session composition downstream |
| `KuyuManasMLXAdapter` | `manas` and `KuyuManasMojoAdapter` | Keep Manas model/bundle structure in Manas; keep Kuyu v7 conversion and model-store gates in the adapter |
| `KuyuMLXEvolution` | `KuyuMojoEvolution` | Port mutation, crossover, inference, and scoring compute behind `kuyu-training` protocols |
| `KuyuMLXReinforcement` | `KuyuMojoReinforcement` | Port policy distributions and optimizer kernels without reconstructing scenario semantics |
| `KuyuMLXWorldModel` | `KuyuMojoWorldModel` | Port compute only; authoritative physics remains in `kuyu-physics` |
| `KuyuMLXCampaignContracts` | `kuyu-training` | Move generic campaign contracts; do not create backend-prefixed replacements |
| `KuyuMLXCampaignValidation` | `kuyu-training` | Move generic artifact and gate validation |
| `KuyuMLXCampaignRuntime` | `kuyu-training` plus `KuyuMojoTrainingRuntime` | Separate lifecycle semantics from concrete compute composition |
| `KuyuMLXReferenceQuadrotor` | `kuyu-physics`, `kuyu-scenarios`, `kuyu-training`, and `kuyu-mojo` | Move equations/scenario meaning/contracts to their authorities; port only compute execution |
| `KuyuMLXRoArmM1` | `kuyu-physics`, `kuyu-scenarios`, `kuyu-training`, and `kuyu-mojo` | Apply the same split through descriptor-driven robot boundaries |
| `KuyuMLXTrainingRuntime` | backend-neutral runtime facade plus `KuyuMojoTrainingRuntime` | Preserve one lifecycle path while replacing its compute implementation |
| `KuyuMLX` | none | Delete after app cutover; do not ship a compatibility facade |
| `KuyuMLXTrainingProbe` | test and diagnostic targets | Remove from the production public API |

## Ownership and Lifetime Contract

| Resource | Creator | Owner | Lifetime | Isolation and failure contract |
|---|---|---|---|---|
| Training request | CLI/UI adapter | Kuyu runtime | One submitted run | Immutable and digest-bound; invalid input fails before worker launch |
| Attempt context | Worker service | Worker actor | One attempt | Ordered lifecycle transitions; cancellation is explicit |
| Checkpoint snapshot | Launcher | Attempt context | One attempt | Read-only and digest-verified; mutable sharing across workers is prohibited |
| Mojo ABI session | `KuyuMojoCore` | Attempt context | Worker attempt | Explicit `shutdown`; capability mismatch is a typed failure |
| Prepared executable artifact | `swift-mojo` | ABI session | Session or verified cache lease | Target triple and digest must match; no path-only trust |
| Device buffers | Mojo session | Mojo session | Bounded operation/session scope | Owner-retained views only; pointers do not escape their borrow scope |
| Canonical world program | `kuyu-physics` | Immutable value | Program revision | Closed opcodes and validated layouts; stable digest identifies semantics |
| Scenario execution plan | `kuyu-scenarios` | Immutable value | Scenario revision | Backends consume one plan; unsupported capabilities fail closed |
| Progress journal | Training runtime | Attempt artifact store | Durable attempt history | Monotonic, attempt-bound, synchronized before live publication |
| Accepted model bundle | Manas publisher | Immutable artifact store | Published revision | Reloaded bytes must reproduce evaluated inference before atomic promotion |

## Implementation Gates and Critical Path

The estimates are engineering time ranges, not elapsed promises. P1 through P8
form the critical path because each establishes a contract consumed by the next
stage. Semantic relocation in P6 can overlap late P4/P5 after its destination
contracts are frozen.

```mermaid
flowchart LR
  P0["P0 Boundary freeze\n1-2 d"] --> P1["P1 swift-mojo ABI v2\n4-6 d"]
  P1 --> P2["P2 Canonical programs\n5-8 d"]
  P2 --> P3["P3 CPU/Metal/CUDA executors\n7-10 d"]
  P3 --> P4["P4 Manas Mojo models\n8-12 d"]
  P4 --> P5["P5 GA/RL/world-model compute\n8-12 d"]
  P4 --> P6["P6 Semantic relocation\n5-8 d"]
  P5 --> P7["P7 Runtime/app cutover\n5-8 d"]
  P6 --> P7
  P7 --> P8["P8 Parity + golden + Jetson\n5-8 d"]
  P8 --> P9["P9 Delete MLX runtime\n2-4 d"]
```

| Gate | Deliverable | Exit condition | State |
|---|---|---|---|
| P0 | Authority freeze and migration ledger | Specs agree; legacy callable gaps are marked or removed; no new MLX production features | Complete |
| P1 | `swift-mojo` ABI v2 | Owned buffers/state, scoped borrows, typed capabilities, shutdown, Linux ARM64 artifact verification | In progress: host borrows, session/resource ownership, exact-count synchronous host transfer, host Float32-buffer lifecycle, and Linux ARM64 cross packaging are verified; native Jetson link/run and MAX-backed Metal/CUDA allocation/synchronization remain |
| P2 | Canonical dynamics and sensor programs | Closed opcodes, layouts, units, differentiability, integration/projection stages, stable digest | Complete for the reference quadrotor program and Swift Float64 semantic executor; digest `6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310` |
| P3 | Mojo world executors | CPU `Float64`, Metal, and CUDA consume the same program without copied equations or fallback | Not started |
| P4 | Manas Mojo implementation | Core/Reflex model structure remains Manas-owned; runtime and training satisfy bundle contracts | Not started |
| P5 | Kuyu Mojo compute | Vectorized world, GA, PPO/SHAC, and world-model protocols have real production conformers | Not started |
| P6 | Semantic ownership cleanup | Scenario, campaign, and artifact semantics no longer live in a backend package | Not started |
| P7 | Single runtime cutover | CLI/UI use one backend-neutral API and no concrete backend imports | Not started |
| P8 | Qualification | CPU/Metal/CUDA parity, v7 integrity, golden learning, and Jetson native CUDA evidence pass | Not started |
| P9 | Destructive cleanup | `kuyu-mlx`, duplicate equations, v3-v6 runtime readers, aliases, and selectors are absent | Not started |

## Iterative Verification Loops

```mermaid
flowchart TD
  H["Hypothesis: one program is semantically portable"] --> O["Observe differential trace\n15-45 min per fixture"]
  O --> U["Update confidence by state/observable/boundary residuals"]
  U --> Q{"All declared fixtures and boundaries pass?"}
  Q -->|no| N["Choose highest-information mismatch fixture"]
  N --> O
  Q -->|yes| C["Record parity evidence for the program digest"]
```

The loop converges only when every declared fixture, projection boundary,
failure classification, and device class meets its tolerance. A time or run
limit does not count as convergence; remaining uncertainty must be recorded.

The learning loop similarly converges only when a reloaded candidate improves
held-out task quality and passes safety/failure gates. A non-empty dataset,
finite loss, changed weights, or successful process exit is insufficient.

## P0 Work Log

| Change | State | Evidence |
|---|---|---|
| Mojo authority and package graph frozen | Committed | `SPEC.md`, `LEARNING_SYSTEM_SPEC.md`, `../KUYU_PACKAGE_ARCHITECTURE.md` |
| Canonical buffer, instruction, graph, fidelity, integration, and digest contracts | Implemented and validated | `../kuyu-physics/Sources/KuyuPhysics/Canonical`, `CanonicalBufferLayoutTests.swift`, and `CanonicalDynamicsProgramTests.swift` |
| Stable digest value validation | Implemented with decode-time recomputation and a fixed reference golden | `CanonicalProgramDigest.swift`; reference digest `6c6773c5a824508fd683390aa7a4acdc1636e8c8483f6ac9ee9667bf62d54310` |
| Closure/RK4 canonical gap | Removed from the production path | Closure-backed force-term types and duplicated `ReferenceQuadrotorDynamics` were deleted; Plant and IMU consume the canonical program through `ReferenceQuadrotorScalarDynamicsExecutor`; the integrator dispatches the declared RK4 scheme |
| Full `KuyuPhysicsTests` target | Passed | 119 of 119 tests passed under bounded `xcodebuild test`, including differentiability propagation and the strict 400-step/s canonical-kernel budget |
| Source-risk audit | Executed | `unconscious/scripts/audit-dangerous-code.sh --verbose`: 0 blockers; 44 existing oversized-production-file review findings retained for separate review |
| Full reference canonical opcode program | Implemented | Nine force terms, derivative, observables, full/single-prop fidelity partitions, and RK4 projection stages share one validated program |
| Mojo package and complete ABI v2 | Partially implemented upstream | Caller-owned mutable host-buffer, synchronous session, session-owned Float32-buffer create/copy/shutdown, and schema-5 Linux ARM64 cross artifact are implemented; native Jetson and accelerator execution remain P1 blockers |
| Build/test/benchmark/device evidence | Partially executed | KuyuPhysics 119/119, KuyuScenarios 127/127, strict 400-step/s scalar budget, focused `swift-mojo` `xcodebuild test`, real Mojo universal macOS session/resource/transfer acceptance, and aarch64 Linux cross-artifact inspection executed. Mojo parity, sanitizer, native Jetson, GPU, and HIL evidence remain; the Kuyu aggregate test target is environment-blocked because the installed Xcode lacks its optional Metal Toolchain component |

## P1 Work Log

| Change | State | Evidence |
|---|---|---|
| `([Float], inout [Float]) throws -> Void` semantic IR and macro | Implemented and tested | `swift-mojo/Sources/MojoBindingCore`, `MojoMacros`, and package-wide `xcodebuild test` |
| Scoped immutable/mutable C and Mojo pointer ABI | Implemented and real-runtime verified on arm64 macOS | Generated `const float *` / `float *` dispatcher; real Mojo 1.0 changed `[1, 2, 3]` to `[2, 4, 6]` |
| Recoverable Mojo invocation status | Implemented and real-runtime verified | status `0` succeeds; status `7` produced `MojoInvocationError.invocationFailed` |
| Empty input/output failures | Implemented and real-runtime verified | distinct `emptyBorrowedBuffer` and `emptyMutableBuffer` paths |
| Static consumption | Verified locally | four bridge symbols present; final consumer had no Mojo dynamic dependency |
| Ownership scope | Caller-owned host buffers only | Both pointers end with the synchronous nested borrow; no device/session ownership is claimed |
| Opaque session binding IR and macro | Implemented and tested | factory requires a paired shutdown; use binding names its Swift factory and must remain in the same external package |
| Versioned create/use/shutdown ABI | Implemented and real-runtime verified on arm64 macOS | flat schema-v1 request/response, `void *` handle, session-bound mutable-buffer dispatcher, and paired shutdown symbols |
| Session ownership and isolation | Verified locally | `Mutex<State>` owner, factory-domain identity, single synchronous lease, typed reentrant/concurrent `busy`, typed use-after-shutdown, idempotent explicit shutdown, and deinit fallback |
| Creation cleanup and capability failure | Verified locally | nonzero status/schema/device/ordinal/capability rejection destroys every returned handle exactly once; no device fallback |
| Session-owned Float32 resource | Verified locally on universal macOS host memory | generated factory/create/destroy/copy ABI, required post-copy synchronization binding, typed host/device/pinned-host memory kind, capability/size/count validation, round-trip transfer, nonzero transfer/create and missing-handle cleanup, parent-before-child rejection, idempotent child shutdown, exactly-once child-before-parent destruction |
| Static session/resource consumption | Verified locally | ten bridge symbols present; final consumer had no Mojo or KGEN dynamic dependency |
| Standalone Mojo 1.0 GPU API probe | Explicitly unavailable in current author environment | Official `DeviceContext` semantics were reviewed, but the installed standalone package does not expose the host module; device implementation requires the explicit MAX runtime adapter or native Jetson environment and cannot be inferred from cross-compilation |
| Linux ARM64 static artifact | Cross packaging verified | real Mojo `aarch64-unknown-linux-gnu` ELF object/archive, schema-5 SE-0482 artifact bundle, platform-conditioned package graph, tree/archive verification, and no KGEN undefined symbols |
| Native Jetson acceptance | Not verified | Swift import/link/run, CUDA capability negotiation, device allocation/transfer/synchronization, success/failure paths, and dynamic dependency evidence are required before P1 completion or Kuyu runtime integration |

## Immediate Next Slice

1. Create `kuyu-mojo`, compile the reference canonical program for Mojo CPU
   Float64, and converge differential force, derivative, observable, RK4,
   boundary, and typed-failure traces against the fixed program digest.
2. Supply the MAX-backed `DeviceContext` package on the exact deployment and
   implement Metal/CUDA allocation, transfer, synchronization, and compiled
   program caching behind the existing session-owned buffer contract.
3. When the Jetson is reachable, link and run the schema-5 Linux ARM64 artifact
   natively and record capability negotiation, success, failure, cancellation,
   and dynamic dependency evidence before CUDA qualification.
