# Asset status and conversion plan

Sources live in `reference/rise-of-legions/Graphics`, `Maps`, `Sound`, `Lang`. Converted output goes to
`assets/`. Converters live in `tools/` (Python 3.14 at `python`, Blender to be located when needed).
Compiled artifacts `.msh` (mesh) and `.tex` (texture) are never parsed; their FBX/TGA/PNG sources exist.

| Asset | Source | Count | Godot target | Tool | Status |
|---|---|---|---|---|---|
| Meshes + skeletal anims | `*.FBX` + `<Mesh>.xml` | 174 FBX | FBX copied 1:1 to `assets/units/` and imported by Godot (ufbx); `game/data/models.json` keeps each FBX's UnitScaleFactor | `tools/copy_unit_assets.py`; `game/units/unit_model.gd` builds the model: scale = (2/125 if ApplyLegacySizeFactor else 1) / (UnitScaleFactor/100) x eiModelSize of the mesh's wela group, clips cut from the FBX take by frame ranges at 30 fps (`units.json` `visuals`) | units, towers, nexus base work; open: single-bone skinned props (NexusCrystal) import far below the ground in Godot and Blender alike (the engine places them at the top; TBone root handling?), `BindTextureToTeam` team textures, walk-speed scaling of the walk clip, `Effects/Meshes` spell props |
| Textures | `.tga` / `.png` (`Diffuse/Normal/Material/Glow`) | 792 / 816 | `.png` | Pillow | todo |
| Material xml | `<Mesh>.xml` (German decimal commas) | 200 | `StandardMaterial3D` built at load (`unit_model.gd`): diffuse albedo, cull mode, alpha test, specular power -> roughness | - | basic; Material.tga channels (R spec intensity, G spec power, B tint, A shading reduction, `Standardshader.fx:394`), glow, outline, metal effect todo |
| Particles | `.pfx` XML (mean/variance) | 366 | `GPUParticles3D` `.tres` | Python | todo |
| Terrain | `<Map>.ter` 513x513 float32 heightmap (base64+zlib) | 2 | `ArrayMesh` + `HeightMapShape3D` | Python numpy | todo |
| Map zones | `<Map>.bcm` polygons | 2 | JSON resource | Python | todo |
| Decorations / vegetation / water / lights | `.bcc .veg .wat .lig` | 2 each | `.tscn` | Python | todo |
| GUI | `.dui` + `.scss` + GUI textures | 139 / 53 | Control scenes built in code, textures copied 1:1 to `assets/ui/` | `tools/copy_ui_assets.py` (262 HUD images incl. InfoPanel attack/armor icons, card icons are 512x256 mip atlases: left 256 square is the icon), layout spec in `docs/hud.md` | HUD in progress |
| Fonts | `.ttf` ProzaLibre + fontawesome | 6 | `assets/fonts/` | `tools/copy_ui_assets.py` | done (fontawesome not needed yet) |
| Sound | FMOD `.bank` + `GUIDs.txt` | 10 | `.ogg` | python-fsb5 or FMOD GDExtension | todo |
| Lang | `Lang/*.csv` (`;`) | 23 | `game/data/lang/<locale>.json` (keys lowercased, `§` refs resolved, HTML stripped) | `tools/extract_lang.py` | en done, other locales on demand |
| Shaders | `.fx` HLSL, `PostEffects.fxs` | 58 + 28 | `.gdshader`, WorldEnvironment | manual port | todo |

Hand-redone assets (conversion impossible): none yet.
