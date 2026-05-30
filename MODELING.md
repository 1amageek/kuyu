# Modeling Formats

Kuyu uses native contracts as authority and external formats as compatibility
adapters.

| Responsibility | External compatibility | Kuyu authority |
|---|---|---|
| Robot body structure | URDF / expanded Xacro | `KuyuBodyModel` (`.kuyubody.json`) |
| Simulation world | SDF | `KuyuWorldModel` (`.kuyuworld.json`) |
| Manas control boundary | Shared JSON schema | `EmbodimentContract` (`.embodiment.json`) |
| Robot package entry | N/A | `KuyuRobotManifest` (`.kuyurobot.json`) |
| Rendering | glTF/GLB, OBJ, USDZ/USDC, STL, URDF render assets | `SceneState` consumed read-only |

## Workflow

1. Import or author the body model.
2. Import or author the world model.
3. Bind signals, actuators, latency budgets, and MotorNerve stages in the
   embodiment contract.
4. Reference the native files from the robot manifest.
5. Run the readiness gate for the required training level.

Missing physical values are fail-closed unless explicitly declared as
supplemented values in the native model and compatibility report.

## Readiness Levels

| Level | Meaning |
|---|---|
| `visualPreview` | Geometry and render inspection only. |
| `kinematicPreview` | Joint topology and control-shape inspection. |
| `dynamicSimulation` | Deterministic rigid-body simulation without contact-rich tasks. |
| `contactTraining` | Contact/friction/manipulation training. |
| `hardwareParity` | Calibrated comparison with real hardware. |

RoArm M1 currently passes `dynamicSimulation`. `hardwareParity` requires a
measured `HardwareCalibrationReport`; inferred or placeholder values are
rejected. `contactTraining` additionally requires a contact-enabled world and
calibrated contact/material evidence for the target manipulation task.
