# Reference material (outside this repo)

Two read-only places hold real-game references. Nothing here is copied into the repo; later phases read
from these paths directly. Rights: the developers gave the owner permission to use everything.

## `reference/rolmedia/` inventory (2026-09-17)
Steam community screenshots of the Rise of Legions client (uploaded 2019-2021, native resolution, no overlays):
`ingame/` 15 files (8 with the HUD at 1920x1080: red nexus fights, lane fights by the water and the wall, base
spawner fight with the unit panel, blue base; 1280x720 and 1600x900 variants; 4 `nohud_*` capture-mode shots for
camera/lighting; a Victory banner) and `lobby/` 10 files (leaderboards de/fr/ru, collection ru, queue en, victory
summaries 1v1 ru and 2v2 es, deck-unlocked pt, maintenance splash "Rise of Legions Crystal Dawn"). The HUD is the
*normal* layout at 1920x1080 (window >= 1710 wide), unlike the owner's Crystal Clash shots (small layout).
Added 2026-09-17 by the owner: `lobby/menu_loading_screen.png`, a phone photo of the menu's own loading page
(Early Access build, window ~1640x924). Checked against `MenuLoadingScreen` (checkpoint 60): logo width, logo bottom,
opener text block start (~49 % down), line spacing, status text (83 %), spinner (88 %) and the three bottom-left logos
all match. Deltas are the older build only: the green `EARLY ACCESS` banner (the repo ships the `CRYSTAL DAWN`
ReleaseBanner.png) and the opener says "Over 3 years" (the repo's lang says 4). Nothing to change.

## Screen coverage (2026-09-17): what defines each screen, and which shots verify it
The ground truth for **every** screen is the repo: 139 `.dui` layouts + 57 `.scss` in `Graphics/GUI` (loading
screen, login queue, maintenance, server-down, main menu: dashboard, deckbuilding, collection, shop, loot, quests,
leaderboards, friend list, statistics, player level, notifications, tutorial; settings menu with gameplay /
graphics / keybinding / sound tabs; HUD: deck, resources, minimap, game info, info panel, announcements, final
screen, scoreboard, in-game menu, reconnect, sandbox, commander switch, technical panel), plus all their images
and the Lang tables. Screenshots only verify rendering.

| Screen | Rise of Legions shots (`rolmedia`) | Crystal Clash shots (`ccmedia`, later client) |
|---|---|---|
| In-game HUD normal layout 1920 | 17 (fights, unit panel, spawner panel; 4 `press_*` official shots from gamepressure.com with the card hover hint, lane towers, spawner tooltip) | - |
| In-game HUD small layout | - | 21 (1679x1079) |
| Capture-mode (no HUD) | 4 | - |
| Victory banner / summary | 3 | 1 |
| Leaderboards | 4 languages | yes |
| Deck builder / card detail (Ascend) | 2 (2019 Steam store shots, 1280x720, `store2019_*`: early navbar DECKBUILDER / LEGIONS / SHOP) | deck builder, card vendor, shop, tabs |
| Collection / deck unlocked / queue | 1 each | - |
| Maintenance splash | 1 | - |
| Loading screen, login queue, dashboard/home, shop, quests, settings, loot, friends, scoreboard, in-game menu | **none found online** (Steam community shots are almost all victories/fights) | lobby set covers home, play tabs, deck builder, shop, vendor trees, tooltips, loading |
For screens without a Rise of Legions shot: build from the `.dui`/`.scss`/images (exact), use the `ccmedia` lobby
shots only as a structural sanity check (later client, may differ), never copy their look.

## `reference/ccmedia/` (Crystal Clash) and `reference/rolmedia/` (Rise of Legions), gitignored
`reference/rolmedia/` is the reference for the current build (the 2022 Rise of Legions). `reference/ccmedia/` was
`reference/media/` until 2026-09-17:
The owner's screenshots of the live Crystal Clash client, sorted by the owner: `lobby/` (36 files: loading,
home, play tabs, deck builder, card vendor trees, leaderboards, shop, tooltips) and `ingame/` (21 files: match
loading, warm-up, HUD, economy tooltips, unit / nexus / tower panels, capture point, combat). Files are
`image-<timestamp>.png|webp`. The facts read from them are in the sections below. Only the owner adds files
here; never copy from the owner's Pictures folders. Check it before the HUD (phase 4) and asset (phase 5) work.

## Codex's earlier project: `D:\Games\CrystalClash` (read-only)
Its research folders are worth reusing; its game code is not (see CLAUDE.md Decisions).

| What | Path (under `D:\Games\CrystalClash\`) | Use in |
|---|---|---|
| Steam news archive, 104 posts 2019-09-30 .. 2024-11-12, many titled "Balance Update" / "New patch" | `research/sources/news-index.csv` (index), `research/sources/raw/steam-news.json`, `raw/official-patch-notes.html`, `raw/rise-of-legions-news.json` | Patch-notes audit (CONTINUE.md step 3): everything newer than the repo snapshot 2022-01-19 |
| Steam app metadata for both app ids (Rise of Legions 748940, Crystal Clash 1839660) | `research/sources/raw/steam-app-748940.json`, `steam-app-1839660.json` | Naming, faction display names, store text |
| Player guides (basics, deckbuilding, first wave, gameplay) as html + txt | `research/sources/raw/*.txt` | Deck rules (phase 3), sanity checks of mechanics |
| 7 official Steam screenshots (HUD, card bar, spawner grid, card inspection with numbers, minimap, pings) | `references/pictures/crystal-clash/official/steam-0N.jpg`, index `references/pictures/INDEX.md` | HUD layout (phase 4) |
| UI study captures: 81 + 30 screens of the real client (startup, loading, home, lobby, shop, ...) | `references/pictures/ui-study-r15/`, `ui-study-r16/`, `lobby-study-r11/` | Menus, lobby, deck builder (phase 4 / 7) |
| Unit study images (artist model sheets per faction) | `references/pictures/unit-study/` | Asset check (phase 5) |
| Official release trailer, 48 s 1080p MP4 | `references/videos/crystal-clash/official/crystal-clash-release-trailer.mp4`, index `references/videos/INDEX.md` | VFX / animation reference (phase 5) |
| Video links + two transcripts (strategy interview 2022, unit types guide) | `references/videos/links/*.url`, `references/videos/transcripts/*.txt` | Mechanics cross-check; not balance truth |
| Menu / hover / window sound recordings of the real client | `local-data/audio-references/*.mp3` | UI audio (phase 5) |
| Codex's own research write-ups (repository study, card catalog, animation study, mechanics register) | `docs/research/*.md`, `docs/research/*.csv` | Secondary; our `docs/original-architecture.md` and extractor are authoritative |
| Media provenance (source URLs, hashes) | `references/media-register.csv` | If a file's origin is ever in question |

Codex's design docs (`docs/design/*`) describe a different game of its own ("Siegefront" directions,
five-faction roster proposals) and must not influence the replica.

## Owner screenshots of the live Crystal Clash client (2026-09-16, files in `reference/ccmedia/lobby` and `ingame`)
These are current and take precedence over Codex's older captures. Facts read from them:
- Top bar: PLAY, DECKBUILDER, CARD VENDOR, LEADERBOARDS, SHOP, CHAT; currencies gold (coin) and crystals (pink gem);
  player badge with level (e.g. "sorrow (141)"). Loading screen: "Loading main menu...", credits "Soundeffects by
  Michael Klier, Music by Julian Colbus", Crunchy Leaf and FMOD logos. Home: news panel, "9 players online",
  patch notes button (e.g. "11-12"), guide button, weekly sales (skins at -50 % / -75 %), Discord/YouTube/Twitter/Facebook.
- PLAY tabs: 2V2 MATCH, CO-OP CHALLENGE, GOLEM CHALLENGE, CUSTOM GAME, TUTORIAL. Ranked text: "Play together with a
  partner or command two decks from Level 6 on in a ranked match", "you are only matched against decks of the same
  tier", "The highest card in your deck determines in which tier you play". Co-op/Golem challenge have a Difficulty
  selector starting at "Stone (+0%)". Custom game: Gamemode Duel 1v1 / 2v2 / 3v3 / 3v3 Two Lanes / 4v4 Two Lanes
  (2/4/6/6/8 players) and Tier selector.
- **Tiers are Stone, Bronze, Silver, Gold. "Crystal" still appears in the tier list and leaderboard tabs but is a
  leftover from Rise of Legions and is not a real tier any more (owner's note).** Leaderboards: 2v2 match (Bronze,
  Silver, Gold ranked, monthly), co-op and golem challenge (times per tier).
- **Factions in the card vendor: Black Legion, Green Legion, White Legion, Blue Legion, Crystal Legion.** The Crystal
  Legion is the source's `Golems` faction; tooltip: "All cards of the crystal legion can be put in any deck without
  regarding the color restrictions." Card vendor = unlock tree per legion (nodes with tier badges stone/bronze/silver/gold).
- Deck builder: 12 slots at the bottom (each shows a level number, e.g. 5), card grid with name, attack / defense
  values, trait keywords (e.g. Void Bane: 14 / 240, "Cleave, Voidhunter, Soulgatherer, Feast, Deathcry: Energy
  Supply"; Frostgoyle Fountain: - / 375, "Dismantlement, Soulgatherer, Soul Enhancer, Ritual Summon"; Gatling Turret
  24 / 260 "Limited: Gadget, Ammunition, Searching Fire, Armor-Piercing, Surefire, Energy Flow"; Relocate "Teleports up
  to 5 allies to another location. Buildings are healed and replenished."), cost (e.g. 1500 / 150 / 100 / 80 / 130 / 800)
  and card tier badge; right-side filters: legion, tier, Summoning / Spawner / Building / Spell, tier I-III, sort "Received".
  Card names seen: Granite Vanguard Spawner (30 / 440, Tremor), Crystal Enforcer Spawner (23 / 280, Siege, Crystal
  Artillery), Footmen Spawner (26 / 184, "Raise your shield!"), Light Pulse ("Stuns and blinds up to 14 target enemy
  units."), Surge of Light. Those numbers are the live balance and may differ from the 2022 source.
- Shop tabs: SKINS, ICONS, BUNDLES, PREMIUM, CRYSTALS, REDEEM BONUS CODE; skins are renamed/recolored units
  (e.g. "BRR4, Replacement of Nature" = Brratu skin, "Hellfire Turret", "Spring Gunner", "Hermit").
- Shop details: ICONS (player icons for 950-2000 crystals), BUNDLES (Bronze $5.99: all bronze cards + 3 days premium +
  2,000 crystals + 1 deck slot; Silver $14.99: 30 days premium, 5,000 crystals, 2 deck slots; Gold $29.99: 60 days,
  10,000 crystals, 4 deck slots), PREMIUM (1/3/7/30/180/360 days for 600/1000/1500/4000/22000/41000 crystals;
  "150% credits and experience after each match, two additional rerolls for daily quests"), CRYSTALS
  (2,500 $4.99 .. 50,000+10,000 bonus $99.99), REDEEM BONUS CODE (XXXX-XXXX-XXXX-XXXX-XXXX, Refer a friend:
  30 premium days each, friend must reach level 5; friend id is a 7-digit number).
- Friends panel (top-right icon): friend id, online/offline list, Refer a friend / Add a friend. Quests panel:
  Weekly (6 days) "Win 25 Matches" 6000 gold; Daily (3/3) e.g. "Win 3 matches using white cards" 1200 gold chest,
  "Play 50 white cards", "Win 1 match using a single-colored deck", one reroll (1/1).
- Level Up Rewards: per level 5000 gold + 100 crystals; every 10 levels (150) 12000 gold + 2000 crystals + icon.
- Queue: PLAY button turns into a timer, "In Queue. Please be patient... 00:00, 9 players online, Leave queue".
  "Choose your deck!" modal lists decks with icon + name + tier badge. Tutorial tab: "Learn the basics of the game in
  a quick guided tutorial", Start.
- Tooltips: every lobby button has a hover tooltip (e.g. "- Deckbuilder - Build your own Decks and upgrade your
  cards!"); hovering the username shows the experience bar "105705 / 320000" and "Click to preview Rewards!".
  The original repo ships its text tables in `reference/rise-of-legions/Lang/*.csv` (cards, cards_abilities,
  cards_meta, collection, collection_quests, ...; several languages per row). Use them for all in-game text and
  verify against the screenshots for wording that changed after 2022.
- In-game (match) screenshots: loading screen with both teams' names, avatars and deck names ("You might have
  longer loading times on your first game..."); top bar with team health percentages and the clock; warm-up
  banner "9 / Game is about to begin"; bottom-left economy panel: gold "300 / 400 (+10)", essence "1600",
  income progress "0 / 1500", tier stone with the tech timer (04:00); card bar with 12 cards (charge counts under
  each), tier-up buttons "04:00 / 08:00" with locks, spawner grid at the right of the card bar, minimap bottom-right
  with three ping icons, "Activate Chat (Enter)". The build grid (8x3 cyan tiles) shows rows darkening over time
  (owner: "spawners in the back fading away one by one") - verify against the scenario scripts in the HUD phase.
- Card tooltip in game (Mirror Slime Spawner, 26 / 500, 1500): "- Absorb - Whenever this unit is affected by a
  certain status effect for the first time, it permanently increases its health by 200." (source: 250, 495 HP ->
  a live balance change), "- Status Adaptation - Whenever this unit attacks, it copies all status effects of its
  target.", "- Status Reflector - Whenever this unit is attacked, it copies all of its status effects to the
  attacker. (0.5 seconds cooldown)" (source: 200 ms), "Status effects: banished, bleeding, blinded, frozen,
  grounded, lifted, petrified, rooted, silenced, stunned."
- Economy tooltips (live names: Mana = source reGold, Essence = source reWood): "Mana is used to Summon units and
  cast spells. Your Mana regenerates over time. If you reach the cap, Mana is automatically converted into
  Essence." / "Essence is used to build Spawners. Generate more Essence by spending more Mana." / "You generate
  more Mana once you've spent enough Essence to fill the bar." (income bar 0 / 1500).
- Card hover in game is two-stage: first the small card summary (name, attack / health, keywords, charges, cost),
  about a second later the ability detail box (e.g. Relocate: "Teleports up to 5 allies to another target location.
  Recently teleported targets can't be teleported for 19 seconds and units are stunned for 1s (legendary units
  for 2s). Buildings are prioritized, healed and replenished after reappearing based on their stage. Stage I - 40%
  health and 35% energy, Stage II - 35% / 25%, Stage III - 20% / 20%"). Clicking a unit on the field outlines it
  white and opens a unit panel top-right: portrait with card level, name, health bar "500 / 500", attack "26.1",
  armor "0%", keywords. After tier II: mana "436 / 500 (+12)", income bar "1500 / 1750" (thresholds grow).
- Hovering a building outlines it: the live client outlines the player's own nexus red and the enemy's blue.
  **Owner decision (2026-09-16): in our version own = blue, enemy = red**, consistent with the team colors
  (blue = player, red = enemy in the top bar and minimap).
- Clicking the nexus (stage II, card level 5): panel "Nexus", health "8000 / 8000", ammo "25 / 25", attack "96.0",
  armor "0%", keywords "Primary Target, Monumental, Spell Immune, Crystal Ammunition Refill, Crystal Ammunition,
  Doubleshot, Radiating Shot, Upgrade"; a white range circle is drawn on the ground while selected.
- **Balance warning for the audit:** live Guard Tower (stage II) panel: "862 / 2800", ammo "9 / 23", attack "80.0",
  keywords "Monumental, Crystal Ammunition Refill, Crystal Ammunition, Doubleshot, Radiating Shot, Nexusbuster,
  Upgrade"; it fires two shots at two enemies. The 2022 source lanetower has 800-1400 HP by league/level, 100 damage,
  6-18 ammo and a single target. Nexus live: 8000 HP, 25 ammo, 96 damage (source: 110-120 damage, 8-20 ammo).
  Towers and bases were reworked after the repo snapshot; the patch-notes audit must cover them first.
- Camera (2026-09-17, final): our scene was rendered at the reference's 1679x1079 window for grids of pitch /
  yaw / distance / FOV around the blue nexus and scored against `image-1789614749130.webp` (game start) by
  *per-block* alignment (6x4 blocks, each block's own best shift, HUD rectangles masked). Best of 180:
  pitch 54 / yaw 47 / distance 38 / original FOV = the 2022 `CAMERAOFFSET` (4.8 px mean block error; weighted
  top-15 54.2 / 47.5 / 37.7). Narrower FOV + farther, or flatter + closer variants score 5.6-12 px. A whole-frame
  correlation with the frame bottom masked had wrongly preferred pitch 48 / distance 34 (the lower-left
  ground then sat 15 % too far from the centre: the owner's "left side lifted" remark). The client starts
  looking at the own nexus. The reference HUD is the client's *small* layout (window < 1710 wide).
  The minimap keeps the 2022 angle: its painted image is not rotated in the live client (whale shadow
  middle-left, trees top-right / left match the unrotated `map_minimap_single.png`).
  The game-start shot (blue nexus, "Game is about to begin") shows the own base
  top-right with the lane leaving to the bottom-left, and the minimap has blue top-right: the live client puts
  Blue at +x (2022 scripts: -x). Applied as `SimMap.side()`; the tests keep the 2022 layout.
- Handedness (2026-09-17): rendering the sim/map coordinates directly in Godot with the original camera side
  gives the exact mirror image of the reference (lane top-left to bottom-right). Flipping only the camera to
  the other side made the symmetric shapes match but left shadows (rock wall shadow on the wrong lane side),
  texture details (the arrow marking's line) and wall pieces mirrored. Fix: mirror the world (`Main/World`
  scale z -1) and keep the camera mirrored; verified at the lane node and the base (`.tmp/mirror_fixed.png`).
- Water (2026-09-17, lane node shot): deep water (0,95,134) / (0,106,137), beach at (1500,1000) = (215,211,160).
  The 2022 `.wat` colour (45,93,113) with 33 % see-through renders pale grey-green; `MapView.LIVE_WATER_*`
  (colour (0,0.33,0.48), opaque, fresnel 0.1) reproduces the deep water. The beaches outside the lane walls
  do not exist in the 2022 heightmap (12 units under water there): live map delta.
- Spawner tiles: reference teal (120,206,204) from diffuse ~(101,114,113): 0.6 x diffuse + cyan/white
  emission (0.27,0.60,0.60) (`BuildGrid._apply_glow`), i.e. the post-effect glow adds a white bloom.
- Nexus crystal: reference (203,234,237) top / (54,100,105) shadowed; its diffuse at the crystal UVs is
  (193,222,250) and the glow alpha only ~0.13, so the whiteness comes from the gamma-space lighting
  saturation (not ported yet: units use Godot's PBR with the scaled lights).
- Lighting (2026-09-17, game-start shot): patch medians ref vs ours after `MapView` ambient x0.35 / sun x1.06:
  sand SW 157/159, sand W 228/219, shadowed jungle 65/58, platform 174/172. The original's gamma-space
  `colour * (NdotL * sun + ambient)` makes shadow 63 % of lit on screen; the linear scales reproduced that.
  Superseded at checkpoint 73: the lighting is now the source formula itself (`game/maps/gamma_lit.gdshader`),
  no fitted scales.
- Top bar in the live client: red bar left, blue bar right for both the blue and the red player (own team is
  not on the left). Ours puts blue (own) left: check the original `.dui` before changing.
- Capture point (lane node): a white disc on the lane with a blue progress ring while a team captures it.
  The big capture arcs (radius 16.5, `RangeLine.tga`) look *lighter* than the floor in the live client; the
  2022 source tints them with the node's own team colour, neutral grey `404040` (never changes: the node is
  replaced by a tower). We keep the source's grey; with the texture's 13 % peak alpha it is a faint dark arc.
- Lane node effect (2026-09-17, mid-lane shot `image-1789614715701.webp`): the 2022 `LaneNode.pfx` is a white
  `FieldBorder` ring pulse (3 quads, size 10 x 0.3, alpha 0.74, every 250 ms) plus a faint point light; ours
  renders the ring (the light is skipped like all `ptLight`). The live client additionally draws a filled white
  disc with floating sparkles: a newer effect not in the repo (live delta). The blue progress ring is the capture
  progress (`TResourceDisplayComponent` team power) and appears only while units stand on the node: not built yet.
- Camera distance re-check (2026-09-17, identical edge-correlation fits on both shots): game-start shot vs ours
  scale 1.00 (exact), mid-lane shot 0.93 (our middle platform 7 % larger). The original's camera is fixed
  (target on y=0, eye 38 units along CAMERAOFFSET, no wheel zoom in the live client per the owner), so the
  mid-lane difference is the live map's reworked causeway/middle platform (see the beaches delta above), not
  the camera. Not fixable without the live map geometry.
- Lane node after a tower dies: the losing team cannot recapture for a while (owner: ~20 s live; source
  LaneNode_Red/_Blue block 40 s). Selecting an enemy squad: panel "Thistles", "40 / 40", attack "8.8", armor "0%",
  "Doubleshot, Evasion" (source Thistle: 27 HP, 14 damage x2). Enemy nexus is drawn red. Floating combat text
  such as "DODGED" appears above units.

## Asset inventory of the public repo (checked 2026-09-16)
`reference/rise-of-legions/Graphics` (6260 files): 204 `.FBX`/`.fbx` unit and building models (e.g.
`Graphics/Units/Black/VoidSkeleton_Crusader/VoidSkeleton.FBX`, one folder per unit and skin), 204 `.msh` (engine
mesh format), 1717 `.tex` (engine texture format) plus 913 `.png` and 797 `.tga`, 366 `.pfx` particle effects
(`Graphics/Effects/ParticleEffects/<Faction>/*.pfx`), 139 `.dui` GUI layouts + 53 `.scss`, 86 `.fx` shaders;
`Sound`: 10 FMOD `.bank` files; `Maps`: 312 files; `Lang`: text tables. Unit scripts name the model
(`TMeshComponent ... .xml`), animation frame ranges (`CreateNewAnimation(ANIMATION_WALK, 0, 26)`), particle
effects and FMOD events per ability. Converters needed for `.tex`, `.msh`, `.pfx`, `.dui` and the FMOD banks
(phase 5); FBX and png/tga import directly. Frostgoyle spawn: dark burst on the fountain, then the goyle rises
into its flying height (owner observation).
- Card bar keybinds: under each card slot the charge count (left) and the player's configured key label (right,
  e.g. 1 2 3 ... and 0 - = for the spawner slots, "-" when unbound). Rebindable in settings; the HUD must show
  the user's own binding. Locked tier slots show "02:48 / 05:48" with a lock icon.

## Animations and effects in the repo (checked 2026-09-16)
Skeletal animations are inside the FBX files (VoidSkeleton.FBX carries hundreds of animation curves); each unit
script declares the clips as frame ranges: ANIMATION_STAND, ANIMATION_ATTACK, ANIMATION_WALK, ANIMATION_SPAWN,
ANIMATION_ABILITY_*, ATTACK_LOOP, ATTACK_AIR, UNLEASH. Deaths, spawns, hits, projectiles, casts and the nexus
destruction are particle effects (`Graphics/Effects/ParticleEffects/**/*.pfx`, e.g. `black_death.pfx`,
`NexusDie0-5.pfx`, `tower_nexus_shot_charge.pfx`, `SpawnerImpact.pfx`) plus mesh effects declared in the scripts
(`TMeshEffectComponent`: ghost, glow, ice, dissolve). Projectiles have their own meshes (`.xml` + FBX). Godot
imports the FBX clips directly; `.pfx` needs a converter to GPUParticles / CPUParticles (phase 5).
- Sides are assigned per match (the loading screen shows your team on the left or right); the camera is set up
  from the player's own base, so the lane runs bottom-left to top-right for the SW team and the mirror for the
  NE team. The sandbox always plays the SW (blue) side.
