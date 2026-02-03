# KuyuUI Architecture — v2.4 (System/Plugin aligned)

## Purpose
Define KuyuUI responsibilities under the System/Plugin model. KuyuUI must not
mutate physics state directly. It issues commands via CommandSystem and renders
via RenderSystem.

---

## 1. Components

### 1.1 WorldEngine (core runtime)
- Owns PhysicsSystem, SensorSystem, ActuatorSystem, EventSystem
- Deterministic; runs at fixed Δt
- Produces SceneState + SimulationLog

### 1.2 RenderSystem (UI consumer)
- Read‑only consumer of SceneState
- Renders frames at independent FPS (30–120Hz)
- Must not mutate physics or sensors

### 1.3 CommandSystem (UI gateway)
- Accepts commands: RunSuite, Pause, ExportLogs, ExportDataset, Train
- Queues commands for scheduler/EventSystem
- Never touches physics state directly

### 1.4 KuyuUI (app)
- Issues commands only through CommandSystem
- Renders through RenderSystem
- Displays logs and metrics from SimulationLog

---

## 2. Data Flow

```
KuyuUI -> CommandSystem -> Scheduler/EventSystem -> WorldEngine
WorldEngine -> SceneState -> RenderSystem -> KuyuUI
WorldEngine -> SimulationLog -> KuyuUI (charts/logs)
```

---

## 3. Required View Responsibilities

### ContentView
- Run/Train/Export actions -> CommandSystem only
- Shows live/last SceneState in RenderSystem view
- Shows SimulationLog in terminal

### ScenarioDetailView
- Uses SimulationLog snapshots for charts
- Does not call physics directly

### Terminal/LogConsole
- Append‑only view of log stream
- Text must be selectable

---

## 4. Command Types (v2.4)

- RunSuite(suiteId, determinism, cutPeriod, modelDescriptor)
- ExportLogs(path)
- ExportDataset(path)
- TrainCore(datasetPath, epochs, lr, useAux, useQualityGating)
- Stop (optional for long runs)

---

## 5. RenderSystem Contract

- Input: SceneState (poses + model render ids)
- Output: UI‑only frames
- Frame rate decoupled from physics
- If SceneState missing, RenderSystem must show placeholder

---

## 6. Determinism Policy

- All deterministic state belongs to WorldEngine
- RenderSystem and KuyuUI are not part of deterministic replay

