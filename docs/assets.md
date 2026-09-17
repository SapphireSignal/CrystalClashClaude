# Asset status and conversion plan

Sources live in `reference/rise-of-legions/Graphics`, `Maps`, `Sound`, `Lang`. Converted output goes to
`assets/`. Converters live in `tools/` (Python 3.14 at `python`, Blender to be located when needed).
Compiled artifacts `.msh` (mesh) and `.tex` (texture) are never parsed; their FBX/TGA/PNG sources exist.

| Asset | Source | Count | Godot target | Tool | Status |
|---|---|---|---|---|---|
| Meshes + skeletal anims | the engine's `.msh` caches next to the `*.FBX` (Graphics/Units, 174) | 174 | `assets/units/<same path>/<name>.glb` | `tools/msh.py` (reader) + `tools/msh_to_gltf.py --all` (glb writer); `game/units/unit_model.gd` loads the glb, scale = (2/125 if ApplyLegacySizeFactor else 1) x eiModelSize of the mesh's wela group, clips cut at 30 fps (`units.json` `visuals`), `BindTextureToTeam` diffuse per displayed team | done for Units; open: glow textures, walk-clip speed formula (`Visuals.pas:3352`), `Effects/Meshes` spell props, Environment/Gameplay meshes (13 + 2 .msh) |
| Textures | `.tga` / `.png` (`Diffuse/Normal/Material/Glow`) | 792 / 816 | `.png` | Pillow | todo |
| Material xml | `<Mesh>.xml` (German decimal commas) | 200 | `StandardMaterial3D` built at load (`unit_model.gd`): diffuse albedo, cull mode, alpha test, specular power -> roughness | - | basic; Material.tga channels (R spec intensity, G spec power, B tint, A shading reduction, `Standardshader.fx:394`), glow, outline, metal effect todo |
| Particles | `.pfx` XML (mean/variance) | 366 | `GPUParticles3D` `.tres` | Python | todo |
| Terrain | `<Map>.ter` 513x513 float32 heightmap (custom base64 alphabet `0-9A-Za-z+/`, zlib, nested-array 5-byte headers), `FScale` 300/50/300 | 2 | `assets/maps/<Map>/terrain.glb` (16 chunk primitives, chunk id = row*4+col, chunk Diffuse/Normal png next to it) | `tools/convert_map.py` | done (Material.png splat/spec maps unused) |
| Map zones | `<Map>.bcm` polygons | 2 | `game/data/maps/<Map>.json` | `tools/extract_maps.py` | done |
| Decorations / vegetation / water / lights | `.bcc .veg .wat .lig` | 2 each | `assets/maps/<Map>/map.json` (vegetation instances with the engine's Delphi Random replayed per FRandSeed, decoration entities -> `Scripts/Environment/*.ets` meshes, water plane, directional lights + ambient) + `assets/environment/**` (msh -> glb via `tools/msh_to_gltf.py --environment`, textures) rendered by `game/maps/map_view.gd` | `tools/convert_map.py` | done except the water shader (flat colour plane now) and the vegetation grass type (skipped entries) |
| GUI | `.dui` + `.scss` + GUI textures | 139 / 53 | Control scenes built in code, textures copied 1:1 to `assets/ui/` | `tools/copy_ui_assets.py` (262 HUD images incl. InfoPanel attack/armor icons, card icons are 512x256 mip atlases: left 256 square is the icon), layout spec in `docs/hud.md` | HUD in progress |
| Fonts | `.ttf` ProzaLibre + fontawesome | 6 | `assets/fonts/` | `tools/copy_ui_assets.py` | done (fontawesome not needed yet) |
| Sound | FMOD `.bank` + `GUIDs.txt` | 10 | `.ogg` | python-fsb5 or FMOD GDExtension | todo |
| Lang | `Lang/*.csv` (`;`) | 23 | `game/data/lang/<locale>.json` (keys lowercased, `§` refs resolved, HTML stripped) | `tools/extract_lang.py` | en done, other locales on demand |
| Shaders | `.fx` HLSL, `PostEffects.fxs` | 58 + 28 | `.gdshader`, WorldEnvironment | manual port | todo |

Hand-redone assets (conversion impossible): none yet.
