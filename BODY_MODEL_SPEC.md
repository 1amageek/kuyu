# Body Model Spec

`KuyuBodyModel` describes the robot body.

| Section | Meaning |
|---|---|
| `links` | Mass, center of mass, inertia, visuals, collisions, material binding. |
| `joints` | Fixed/revolute/continuous/prismatic topology, hard/soft limits, home position, damping, friction. |
| `actuatorMounts` | Physical actuator output frames, parent links, output axes, and optional housing geometry. |
| `actuatorAttachments` | Transmission from mounted actuator output to joint: ratio, reduction, command direction, zero offsets, efficiency, and torque limit. |
| `sensorMounts` | Sensor frame placement. |
| `provenance` | Source and supplemented-value notes. |

URDF or expanded Xacro can be imported into this model, but missing physical
values are not silently invented by the importer. Supplemental values must be
declared in the native body model and compatibility report.
