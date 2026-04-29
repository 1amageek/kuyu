# kuyu

Application layer for the Kuyu simulation environment. Integrates Kuyu sub-packages and Manas controllers into a unified UI, CLI, and MLX training bridge.

## Overview

Kuyu is a simulation environment for training and evaluating [Manas](https://github.com/1amageek/manas) controllers. This package is the top-level application that composes all sub-packages into a working system.

### Modules

| Module | Description |
|--------|-------------|
| **KuyuMLX** | Manas-MLX bridge on top of physics scenario runners |
| **KuyuUI** | SwiftUI-based GUI for simulation, training, and visualization |
| **KuyuCLI** | Command-line interface for headless simulation and training |

### Runtime Basis

Current `kuyu` runtime uses physics simulation as the source of truth.
The world-model package is not authoritative physics. In M2 smoke execution it
is used as a validated checkpoint and imagination-training gate, while
analytical physics remains the reference.

`AscendingChannelMapper` includes world-model-compatible channel layout helpers, but
runtime simulation and evaluation are currently physics-based.

Kuyu owns the training-world boundary: physics execution, scenarios, reward,
rollout, dataset export, visual inspection, and CLI/UI orchestration. Manas
control protocol internals, Manas model internals, and concrete RL optimizers
remain outside Kuyu.

### CLI Usage

```bash
# Run simulation with the teacher/reference baseline controller
swift run -c release kuyu run --controller baseline

# Run the sensor-only baseline controller
swift run -c release kuyu run --controller sensorBaseline

# Run with Manas MLX controller
swift run -c release kuyu run --controller manasMLX --model path/to/model.json

# Training loop
swift run -c release kuyu loop --iterations 10 --epochs 4 --lr 0.001

# RL environment rollout smoke
swift run -c release kuyu rollout --controller teacherBaseline --episodes 2 --workers 1
swift run -c release kuyu rollout --controller teacherBaseline --episodes 8 --workers 4

# M2 world-model and imagination-training smoke
swift run -c release kuyu rollout --controller teacherBaseline --episodes 2 --workers 1 --export-dataset /tmp/kuyu-rollout-dataset
swift run -c release kuyu train-world-model --dataset /tmp/kuyu-rollout-dataset --save-model /tmp/kuyu-world-model --epochs 1 --max-batches 1
swift run -c release kuyu imagine-train --world-model /tmp/kuyu-world-model --save-model /tmp/kuyu-imagination --horizon 2 --epochs 1

# SwiftPM release MLX smoke runs need the MLX Metal library next to the binary
./scripts/install-mlx-metallib.sh release
swift run -c release kuyu loop --iterations 1 --epochs 1 --lr 0.001 --save-model /tmp/kuyu-model-smoke
```

### M1.5 RL Environment Acceptance

M1.5 means Kuyu exposes a reinforcement-learning environment contract, not a complete RL algorithm. The accepted baseline is:

- `reset / step / reward / done / truncated / info` exist as typed environment values.
- The primary policy action is `DriveIntent`; direct actuator actions remain teacher/test escape hatches.
- Reward and terminal semantics are finite and deterministic for the ATT and lift reference scenarios.
- Serial and parallel rollout produce deterministic merged artifacts ordered by scenario, seed, and worker index.
- Parallel rollout uses independent environment and policy instances per worker. Shared `ManasMLXModelStore` execution is intentionally excluded until M2.
- `kuyu rollout --model <descriptor>` constructs the environment from the descriptor. Invalid descriptor paths fail closed and never fall back to baseline.

### M1.6 Runtime Reliability Acceptance

M1.6 fixes the execution boundary around descriptors, UI commands, and MLX/Metal preflight:

- A non-empty descriptor path must load successfully; descriptor load, inertial load, and parameter resolution failures are terminal errors.
- `ReferenceQuadrotorParameters.baseline` is allowed only for tests, empty descriptor reference runs, CLI smoke, and display-only preview fallback.
- KuyuUI user operations route through `SimulationViewModel -> CommandSystem -> Service`; views do not mutate simulation state directly.
- KuyuUI user operations log `kuyu.ui` with action/task/model descriptor context. Descriptor preflight errors include reason and error details.
- `manasMLX` and `kuyu loop` perform MLX metallib preflight before execution and do not fall back to baseline.

Dependency-order verification:

```bash
cd ../manas && python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)' 60 swift test
cd ../kuyu-core && python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)' 60 swift test
cd ../kuyu-physics && python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)' 60 swift test
cd ../kuyu-scenarios && python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)' 60 swift test
cd ../kuyu-training && python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)' 60 swift test
cd ../kuyu && python3 -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[2:], timeout=int(sys.argv[1])).returncode)' 120 swift test
swift run kuyu rollout --controller teacherBaseline --episodes 2 --workers 1
swift run kuyu rollout --controller teacherBaseline --episodes 8 --workers 4
```

### Verification Split

SwiftPM is the default path for non-MLX contracts: CLI parsing, descriptor loading, RL environment types, scenario execution, rollout harnesses, and dataset export.

Xcode is the authority for MLX and Metal-backed execution. Use it for `ManasMLXModelStore` load/train/save smoke tests, app-level MLX tests, and `kuyu-world-model` validation:

```bash
xcodebuild test -scheme kuyu -destination 'platform=macOS' -maximum-test-execution-time-allowance 60
cd ../kuyu-world-model
xcodebuild test -scheme kuyu-world-model -destination 'platform=macOS' -maximum-test-execution-time-allowance 60
```

SwiftPM release binaries can run MLX only when the MLX default metallib is installed next to the executable. Prefer `./scripts/install-mlx-metallib.sh release` for SwiftPM smoke runs, or use the Xcode-built binary when testing Metal resources.

### M2 World-Model Entry

M1.5 uses analytical physics as the source of truth. `kuyu-world-model` remains a separately verified model package and does not replace scenario physics.

M2 introduces a world-model adapter behind the environment/rollout boundary:

- Keep analytical physics as the reference validator.
- Train a `StateWorldModel` residual checkpoint from rollout dataset fields.
- Validate the `StateWorldModel` checkpoint before `imagine-train` publishes a Manas checkpoint.
- Reject missing, non-finite, high-uncertainty, or threshold-exceeding world-model predictions before imagination training continues.
- Use per-worker model snapshots or an actor pool; do not share a reentrant `ManasMLXModelStore` across parallel rollout workers.
- Compare imagined rollouts against physics replay before accepting world-model rewards or terminations.
- Keep `kuyu-world-model` acceptance in Xcode/Metal verification until SwiftPM can reliably provide the required MLX resources.

## Architecture

```
kuyu (this package)
  |
  +-- KuyuMLX
  |     depends: KuyuCore, KuyuPhysics, KuyuScenarios,
  |              KuyuTraining,
  |              ManasCore, ManasMLXModels, ManasMLXRuntime, ManasMLXTraining
  |
  +-- KuyuUI
  |     depends: KuyuCore, KuyuPhysics, KuyuScenarios,
  |              KuyuTraining, KuyuMLX, swift-log, swift-configuration
  |
  +-- KuyuCLI
        depends: KuyuCore, KuyuPhysics, KuyuScenarios,
                 KuyuTraining, KuyuMLX, swift-argument-parser
```

## Full Dependency Graph

```
KuyuCore ------------------- (zero dependencies)
  |
KuyuPhysics
  |
KuyuScenarios
  |
KuyuTraining
  |
kuyu (this package) + manas
```

## Requirements

- Swift 6.2+
- macOS 26+
- Apple Silicon (MLX Metal runtime)

## Related Packages

- [kuyu-core](https://github.com/1amageek/kuyu-core) — Core protocols and types
- [kuyu-physics](https://github.com/1amageek/kuyu-physics) — Physics engines and analytical models
- [kuyu-scenarios](https://github.com/1amageek/kuyu-scenarios) — Evaluation scenarios and logging
- [kuyu-training](https://github.com/1amageek/kuyu-training) — Training data collection and pipeline
- [manas](https://github.com/1amageek/manas) — CNS-style robotic control system

## License

See repository for license information.
