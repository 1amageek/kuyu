# kuyu

Application layer for the Kuyu simulation environment. Integrates all Kuyu sub-packages and Manas controllers into a unified UI, CLI, and MLX training bridge.

## Overview

Kuyu is a simulation environment for training and evaluating [Manas](https://github.com/1amageek/manas) controllers. This package is the top-level application that composes all sub-packages into a working system.

### Modules

| Module | Description |
|--------|-------------|
| **KuyuMLX** | Fused environment assembly, Manas-MLX bridge, ascending channel mapping |
| **KuyuUI** | SwiftUI-based GUI for simulation, training, and visualization |
| **KuyuCLI** | Command-line interface for headless simulation and training |

### Fused Environment

KuyuMLX assembles the fused environment that combines physics and learned world models:

```
FusedEnvironment<QuadrotorAnalyticalModel, MLXWorldModelController, SensorField>
```

**`AscendingChannelMapper`** converts `FusedState` into Manas ascending channels:

| Channel Type | Source | Description |
|---|---|---|
| Type S | SensorField | Raw sensor observations |
| Type P | AnalyticalModel | Physics predictions |
| Type R | WorldModel | Residual corrections |
| Type E | WorldModel | Latent extensions |

### CLI Usage

```bash
# Run simulation with baseline controller
swift run -c release kuyu run --controller baseline

# Run with Manas MLX controller
swift run -c release kuyu run --controller manasMLX --model path/to/model.json

# Training loop
swift run -c release kuyu loop --iterations 10 --epochs 4 --lr 0.001
```

## Architecture

```
kuyu (this package)
  |
  +-- KuyuMLX
  |     depends: KuyuCore, KuyuPhysics, KuyuScenarios,
  |              KuyuTraining, KuyuWorldModel,
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
  |           |           |
KuyuPhysics  KuyuWorldModel  (independent of each other)
  |           |
KuyuScenarios |
  |           |
KuyuTraining  |
  |           |
  +-----+-----+
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
- [kuyu-world-model](https://github.com/1amageek/kuyu-world-model) — DreamerV3-based learned world model
- [manas](https://github.com/1amageek/manas) — CNS-style robotic control system

## License

See repository for license information.
