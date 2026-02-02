# Modeling Formats

Kuyu uses different formats for physics, rendering, and printing. This keeps the simulation deterministic
and fast while preserving compatibility with external tools.

## Formats by Purpose
- Physics model: **URDF** or **SDF**
  - Contains links, joints, mass, inertia, sensors, and frame definitions.
- Render mesh: **glTF/GLB** (preferred), **OBJ** (fallback), **USDZ** (Apple tooling)
  - Used only for visualization in KuyuUI.
- Print mesh: **STL** or **3MF**
  - Used for fabrication; may be simplified from the render mesh.

## Recommended Workflow
1) Author a physics model (URDF/SDF) as the source of truth for mass, inertia, and frames.
2) Attach a render mesh (glTF/GLB or USDZ) for visualization.
3) Provide a print mesh (STL/3MF) derived from the same CAD source.

## Descriptor
Use `RobotModelDescriptor` to bind the three artifacts together.
Example JSON:
```json
{
  "id": "quadref-v0",
  "name": "Quadrotor Reference",
  "physicsFormat": "urdf",
  "physicsPath": "Models/QuadRef/quadref.urdf",
  "renderFormat": "glb",
  "renderPath": "Models/QuadRef/quadref.glb",
  "printFormat": "3mf",
  "printPath": "Models/QuadRef/quadref.3mf"
}
```

The descriptor is optional for pure simulation runs, but recommended for KuyuUI and tooling.

## Quadrotor Example
Example files are placed under `Models/QuadRef/`:
- `quadref.urdf`
- `quadref.model.json`

Mesh files (`quadref.glb`, `quadref.3mf`) are referenced but not included yet.

## KuyuUI Integration
KuyuUI reads the descriptor path from the Configuration panel and loads:
- **Mass and inertia** from the URDF
- Remaining parameters from the baseline quadrotor defaults

Rendering meshes are not required for running the simulation.

`KuyuUI` bundles the example descriptor and URDF under
`Sources/KuyuUI/Resources/Models/QuadRef/` so the default path works in app builds.
