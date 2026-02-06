# Modeling Formats

Kuyu uses different formats for physics, rendering, and printing. This keeps the simulation deterministic
and fast while preserving compatibility with external tools.

## Formats by Purpose
- Physics model: **URDF** (required)
  - Contains links, joints, mass, and inertia.
- Render mesh: **glTF/GLB** (preferred), **OBJ** (fallback), **USDZ** (Apple tooling)
  - Used only for visualization in KuyuUI.
- Print mesh: **STL** or **3MF**
  - Used for fabrication; may be simplified from the render mesh.

## Recommended Workflow
1) Author a physics model (URDF) as the source of truth for mass and inertia.
2) Attach a render mesh (glTF/GLB or USDZ) for visualization.
3) Provide a print mesh (STL/3MF) derived from the same CAD source.

## Descriptor
Use `RobotDescriptor` (JSON) to bind physics, render, and signal catalogs together.
The canonical schema is defined in `ROBOT_DESCRIPTOR.md`.
The descriptor is the canonical entry point for KuyuUI and CLI, and it must
reference the physics model (URDF) instead of loading URDF directly.

## ReferenceQuadrotor Example
Reference assets are placed under `Models/QuadRef/`. Descriptor files are in the
`RobotDescriptor` format described in `ROBOT_DESCRIPTOR.md`. Mesh files referenced
by the descriptor are not bundled by default.

## KuyuUI Integration
KuyuUI reads the descriptor path from the Configuration panel and loads:
- **Mass and inertia** from the URDF
- Remaining parameters from the baseline quadrotor defaults

Rendering meshes are not required for running the simulation.

`KuyuUI` bundles the example descriptor and URDF under
`Sources/KuyuUI/Resources/Models/QuadRef/` so the default path works in app builds.
