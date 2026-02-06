# KuyuUI Architecture (System/Profile aligned)

## Purpose
Define KuyuUI responsibilities under the System/Profile model. KuyuUI is a
**required** part of Kuyu and must provide full visual inspection of the world.
It must not mutate physics state directly. It issues commands via CommandSystem
and renders via RenderSystem.

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
- Default backend on Apple platforms: **RealityKit**
- Other backends (e.g., Unreal) must be reachable via view‑only adapters

### 1.3 CommandSystem (UI gateway)
- Accepts commands: RunSuite, Pause, ExportLogs, ExportDataset, Train
- Queues commands for scheduler/EventSystem
- Never touches physics state directly

### 1.4 KuyuUI (app)
- Issues commands only through CommandSystem
- Renders through RenderSystem
- Displays logs and metrics from SimulationLog
- Manual actuator override channels are generated from `RobotDescriptor.signals.actuator`
  (fallback: task default count).
- Manual actuator sliders operate in physical actuator units (descriptor limits/range),
  not normalized 0..1 UI values.

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

## 3.1 Visual Inspection Requirements (Mandatory)
- 3D viewport with plant, sensors, and environment visible at all times.
- Overlay toggles for axes, forces/torques, actuator values, and event markers.
- Timeline scrub/step controls for deterministic replay.
- Inspector panels for sensor streams and Manas internals
  (Bundle/Gating/Trunks/DriveIntent/Reflex).
- World state snapshot export (image or scene JSON) for debugging.

---

## 4. Command Types

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
