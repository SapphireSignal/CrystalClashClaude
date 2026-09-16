# Asset status and conversion plan

Sources live in `reference/rise-of-legions/Graphics`, `Maps`, `Sound`, `Lang`. Converted output goes to
`assets/`. Converters live in `tools/` (Python 3.14 at `python`, Blender to be located when needed).
Compiled artifacts `.msh` (mesh) and `.tex` (texture) are never parsed; their FBX/TGA/PNG sources exist.

| Asset | Source | Count | Godot target | Tool | Status |
|---|---|---|---|---|---|
| Meshes + skeletal anims | `*.FBX` + `<Mesh>.xml` | 204 | `.glb` | Blender headless or Godot FBX importer; animation frame ranges from `.ets` | todo |
| Textures | `.tga` / `.png` (`Diffuse/Normal/Material/Glow`) | 792 / 816 | `.png` | Pillow | todo |
| Material xml | `<Mesh>.xml` (German decimal commas) | 200 | `StandardMaterial3D` / toon shader `.tres` | Python | todo |
| Particles | `.pfx` XML (mean/variance) | 366 | `GPUParticles3D` `.tres` | Python | todo |
| Terrain | `<Map>.ter` 513x513 float32 heightmap (base64+zlib) | 2 | `ArrayMesh` + `HeightMapShape3D` | Python numpy | todo |
| Map zones | `<Map>.bcm` polygons | 2 | JSON resource | Python | todo |
| Decorations / vegetation / water / lights | `.bcc .veg .wat .lig` | 2 each | `.tscn` | Python | todo |
| GUI | `.dui` + `.scss` + GUI textures | 139 / 53 | Control scenes + Theme | manual, styles pre-dumped | todo |
| Fonts | `.ttf` ProzaLibre + fontawesome | 6 | copy | - | todo |
| Sound | FMOD `.bank` + `GUIDs.txt` | 10 | `.ogg` | python-fsb5 or FMOD GDExtension | todo |
| Lang | `Lang/*.csv` (`;`) | 23 | Godot translation CSV | Python | todo |
| Shaders | `.fx` HLSL, `PostEffects.fxs` | 58 + 28 | `.gdshader`, WorldEnvironment | manual port | todo |

Hand-redone assets (conversion impossible): none yet.
