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
| GUI | `.dui` + `.scss` + GUI textures | 139 / 53 | Control scenes built in code, textures copied 1:1 to `assets/ui/` | `tools/copy_ui_assets.py` (254 HUD images, card icons are 512x256 mip atlases: left 256 square is the icon), layout spec in `docs/hud.md` | HUD in progress |
| Fonts | `.ttf` ProzaLibre + fontawesome | 6 | `assets/fonts/` | `tools/copy_ui_assets.py` | done (fontawesome not needed yet) |
| Sound | FMOD `.bank` + `GUIDs.txt` | 10 | `.ogg` | python-fsb5 or FMOD GDExtension | todo |
| Lang | `Lang/*.csv` (`;`) | 23 | `game/data/lang/<locale>.json` (keys lowercased, `§` refs resolved, HTML stripped) | `tools/extract_lang.py` | en done, other locales on demand |
| Shaders | `.fx` HLSL, `PostEffects.fxs` | 58 + 28 | `.gdshader`, WorldEnvironment | manual port | todo |

Hand-redone assets (conversion impossible): none yet.
