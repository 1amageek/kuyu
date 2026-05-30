# Body Model Spec

`KuyuBodyModel` describes the robot body.

| Section | Meaning |
|---|---|
| `links` | Mass, center of mass, inertia, visuals, collisions, material binding. |
| `joints` | Fixed/revolute/continuous/prismatic topology, limits, damping, friction. |
| `actuatorAttachments` | How actuators bind to joints for dynamic simulation. |
| `sensorMounts` | Sensor frame placement. |
| `provenance` | Source and supplemented-value notes. |

URDF or expanded Xacro can be imported into this model, but missing physical
values are not silently invented by the importer. Supplemental values must be
declared in the native body model and compatibility report.
