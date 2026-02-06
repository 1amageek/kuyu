# Robot Descriptor Specification

## Purpose (Normative)
Define a robot in JSON so KuyuProfiles can build a runnable plant, sensor suite, actuator suite, and MotorNerve mapping, and KuyuUI can enumerate and visualize signals without any per-robot UI schema.

## Descriptor-First Entry Point (Normative)
`RobotDescriptor` is the canonical entry point for loading a robot in Kuyu.
The physics model (URDF) MUST be referenced from the descriptor, not loaded
directly by KuyuUI or Kuyu CLI. This keeps the robot definition, signals, and
MotorNerve mapping coherent and reproducible.

## Format (Normative)
- File format is JSON only.
- Recommended extension: `.robot.json`.
- All numeric values are IEEE-754 `number`.

## Top-Level Object (Normative)
Required keys:
- `robot`
- `physics`
- `signals`
- `sensors`
- `actuators`
- `control`
- `motorNerve`

Optional keys:
- `render`

## Common Types (Normative)
- `Vector3`: array of 3 numbers `[x, y, z]` in meters for positions, or in SI for velocities/forces where applicable.
- `Range`: array of 2 numbers `[min, max]`, with `min <= max`.
- `SignalRef`: string that references a `signals.*.id`.

## robot (Normative)
Fields:
- `robotID` (string, required): globally unique ID for the robot.
- `name` (string, required): human-readable name.
- `category` (string, required): high-level class (e.g., aerial, legged, manipulator).
- `manufacturer` (string, optional)
- `tags` (array of string, optional)

## physics (Normative)
Fields:
- `model` (PhysicsModel, required)
- `engine` (EngineBinding, required)

PhysicsModel:
- `format` (string, required): `urdf` only.
- `path` (string, required): relative or absolute path.

EngineBinding:
- `id` (string, required): engine identifier for the profile runtime.
- `parameters` (object, optional): engine-specific parameters.

## render (Optional)
Fields:
- `assets` (array of RenderAsset, required if render is present)

RenderAsset:
- `id` (string, required)
- `name` (string, required)
- `format` (string, required): `gltf`, `glb`, `obj`, `usdz`, or `usdc`.
- `path` (string, required)
- `scale` (Vector3, optional)

## signals (Normative)
Signals define the canonical catalog for logging and UI selection.

Fields:
- `sensor` (array of SignalDefinition, required)
- `actuator` (array of SignalDefinition, required)
- `drive` (array of SignalDefinition, required)
- `reflex` (array of SignalDefinition, required)
- `motorNerve` (array of SignalDefinition, optional): intermediate MotorNerve signals.

SignalDefinition:
- `id` (string, required): globally unique across all signal categories.
- `index` (number, required): non-negative integer index for logging.
- `name` (string, required): display label.
- `units` (string, required)
- `rateHz` (number, optional): sampling or update rate.
- `range` (Range, optional)
- `group` (string, optional): semantic grouping for UI filtering.

## Signal Contract (Normative)
Signals follow `SIGNAL_CONTRACT.md`.
All samples must be finite, timestamps must be non‑negative, and missing samples
are represented by absence rather than NaN.

## sensors (Normative)
Array of SensorDefinition.

SensorDefinition:
- `id` (string, required)
- `type` (string, required): profile runtime sensor type identifier.
- `channels` (array of SignalRef, required): references `signals.sensor` IDs.
- `rateHz` (number, required)
- `latencyMs` (number, required)
- `noise` (object, optional): noise parameters.
- `dropout` (object, optional): dropout parameters.
- `swapProfile` (object, optional): swap parameters.

noise object fields:
- `bias` (number, required)
- `std` (number, required)
- `randomWalkStd` (number, required)

dropout object fields:
- `prob` (number, required)
- `burstMs` (number, required)

swapProfile object fields:
- `gainRange` (Range, required)
- `biasRange` (Range, required)
- `delayMsRange` (Range, required)

## actuators (Normative)
Array of ActuatorDefinition.

ActuatorDefinition:
- `id` (string, required)
- `type` (string, required): profile runtime actuator type identifier.
- `channels` (array of SignalRef, required): references `signals.actuator` IDs.
- `limits` (object, required): limit parameters.
- `dynamics` (object, optional): actuator dynamics parameters.
- `swapProfile` (object, optional): swap parameters.

limits object fields:
- `min` (number, required)
- `max` (number, required)
- `rateLimit` (number, required)

dynamics object fields:
- `timeConstant` (number, required)
- `deadzone` (number, required)

swapProfile object fields:
- `gainRange` (Range, required)
- `maxRange` (Range, required)
- `lagMsRange` (Range, required)

## control (Normative)
Fields:
- `driveChannels` (array of SignalRef, required): references `signals.drive` IDs.
- `reflexChannels` (array of SignalRef, required): references `signals.reflex` IDs.
- `constraints` (object, optional): clamp ranges.

constraints object fields:
- `driveClamp` (Range, optional)
- `reflexClamp` (Range, optional)

## motorNerve (Normative)
MotorNerve defines the output protocol between DriveIntent/Reflex and actuator values.
It specifies mapping and constraints, but does not define safety logic.

Fields:
- `stages` (array of MotorNerveStage, required)

MotorNerveStage:
- `id` (string, required): unique stage ID.
- `type` (string, required): `direct`, `matrix`, `mixer`, or `custom`.
- `inputs` (array of SignalRef, required): ordered inputs for mapping.
- `outputs` (array of SignalRef, required): ordered outputs for mapping.
- `mapping` (object, optional): used by `direct` and `matrix`.
- `parameters` (object, optional): used by `mixer` and `custom`.

Mapping rules:
1. `direct`: `inputs.count` must equal `outputs.count`; index-wise passthrough.
2. `matrix`: `mapping.matrix` has shape `[outputs.count][inputs.count]`.
3. Matrix output equation: `output[i] = sum_j matrix[i][j] * input[j] + bias[i]`.
4. `mapping.bias` length must equal `outputs.count`.
5. `mapping.clip` clamps outputs to range.
6. `mixer`: `parameters` interpreted by a profile-specific mixer implementation.
7. `custom`: `parameters` interpreted by a profile-specific implementation.
8. For KuyuProfiles `mixer`, outputs are normalized and scaled by actuator limits.

Execution semantics:
- Stages execute in the listed order.
- `signals.motorNerve` entries are intermediate and may feed later stages.
- `signals.actuator` outputs are final and must cover all actuators.

## Validation Rules (Normative)
- `robot.robotID` MUST be globally unique.
- Signal IDs MUST be globally unique across all signal categories.
- Signal indices MUST be unique within each signal category.
- All `SignalRef` values MUST reference existing signal IDs.
- `physics.model.format` MUST be `urdf`.
- MotorNerve stage inputs MUST reference `signals.drive` or `signals.motorNerve`.
- MotorNerve stage outputs MUST reference `signals.motorNerve` or `signals.actuator`.
- MotorNerve stages MUST be ordered so motorNerve inputs are produced earlier.
- MotorNerve outputs to `signals.motorNerve` MUST be consumed by later stages.
- If any stage references `signals.motorNerve`, the catalog MUST be present.
- All actuator signals MUST be produced by MotorNerve stages.
- All `Range` values MUST satisfy `min <= max`.
- All required numeric fields MUST be finite.

## UI Behavior (Informative)
- KuyuUI enumerates signals from `signals.*` and allows the operator to select which signals to display.
- `group` is used only for filtering and sorting; it does not affect runtime behavior.
