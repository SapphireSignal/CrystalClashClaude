# In-game HUD spec (phase 4)

Ground truth: `reference/rise-of-legions/Graphics/GUI/Game.dui` + `HUD/**/*.dui` (markup) and
`Graphics/GUI/Stylesheets/core_game*.scss` (pixel layout), view-model `TIngameHUD`
(`BaseConflict.Classes.Gamestates.GUI.pas`), values pushed from `BaseConflict.EntityComponents.Client.pas:1700-1830`.
Owner screenshots in `reference/ccmedia/ingame/` are in the client's **small** layout (window < 1710x816):
`core_game_scaling.scss` `.core-game.small` = resources / minimap / game-info / tooltip at 80 % of their art,
deck panel 64 high with 66x64 slots (spawner margin 48, locked groups shifted 38 %), card hint 267 wide with its
top 208 px above the bottom, hint text 12 px. `Hud._layout` applies this below that window size; the HUD is
drawn in absolute pixels at every resolution like the original (project stretch mode disabled). Images are copied 1:1 by `tools/copy_ui_assets.py` into
`assets/ui/<same path as under Graphics/GUI>`; fonts (Proza Libre) into `assets/fonts/`.
Text: `tools/extract_lang.py` -> `game/data/lang/en.json` (keys lowercased, `§key` references resolved, HTML stripped).

## Blur backdrops
`Blur : True` (`.game-info`, `.resources .content`, `.minimap .content`, `.tooltip .content`, all ZOffset -1 =
behind the panel art): the engine blurs the scene (`TTextureBlur`, kernel 4) and GUIBlur.fx recolours it to
`BlurColor` ($blur-color `$FFAFFFFF`): hue/saturation of the colour, value = (0.5 x blurred value + 0.2) x
colour value. Port: `HudStyle.blur(rect)` with `game/ui/blur_backdrop.gdshader`. Without it the half-transparent
panel and map images show the sharp world (the owner saw tree shadows through the minimap).

## Units and colours
- Design space 1920x1080, panels are drawn at their texture's native size (`Size : 100bw auto`).
- scss `ch` unit is tiny (`230ch` moves the lock icon ~23 px): treat `ch` as 0.1 px and tune by eye.
- Font colours: white `$EFE9FEFF` (ARGB), black `$EF404040`, progress cyan `$FF49A7AC`; darken overrides
  `$AC263D42` (soft, not-ready cards) and `$CC263D42`; cooldown fill `$FF263D42` (`$30263D42` when ready).
- Team colours `TEAMCOLORS`: 0 grey `404040`, 1 blue `0090FF`, 2 red `FF0000`. `coGameplayFixedTeamColors`
  defaults to on: `GetDisplayedTeam` shows the own team as 1 (blue), the enemy as 2 (red) everywhere
  (top bar, minimap, `minimap_icon_*_%d.png`). Matches the owner's own=blue / enemy=red decision.

## GameInfoBar (top centre, `top_panel.png` 570x56)
- Clock `hud.SpawnTimer`: before the first game tick `ceil(ms_to_first_tick/100)`: `<= 9` shows `0.x`, else
  seconds; after that `IntToTime(tick_counter)` = `mm:ss`. Width 19.3 %, font 53 % of the height, centred.
- Nexus bars 200x42 (`blue_shield_hp.png` / `red_shield_hp.png`): left bar's right edge at 37.5 %, anchored
  right (shrinks leftwards); right bar starts at 62.5 %. Left = displayed team of team 1, right = of team 2.
  Health % = `ceil(hp / max * 100)` but 99 if damaged and the ceil says 100. Captions `NN%` 111x20 bold with a
  1 px border sit 16 px above the bottom, left and right. `top_panel.png` is drawn again on top as overlay.

- Nexus bars: left = team 1, right = team 2 (fixed, `GameInfoBar.dui` `hud.LeftTeamID`), each coloured by its
  displayed team (own blue / enemy red), health % ceil with 99 for any damage.

## RessourcePanel (bottom left, `ressource_panel.png` 302x302)
Content 281x281 bottom-left aligned (y offset 21). Rows x 49, width 214, height 31, y 38 / 83 / 128
(the art already has the three dark rows with the icon square at the right and the book for the tier):
- Gold row: `{{Gold}} / {{GoldCap}}` + ` (+{{GoldIncome}})`, icon `mana.png` (live name "Mana").
- Wood row: `{{Wood}}` + ` (+{{WoodIncome}})` only when wood income > 0 (`RIncome.Wood`: gold overflow at the
  cap), icon `essence.png` ("Essence").
- Income row: `{{SpentWood}} / {{SpentWoodToIncomeUpgrade}}` with a cyan progress fill, "Max" at
  `INCOME_UPGRADE_CAP` (10), icon `income_upgrade.png`. Captions right-aligned, font 70 % of row height.
- Tech: roman tier at (88, 198) 56x56, font 60 % extra-bold, over the book; `tech-timer` `IntToTime(TimeToNextTier)`
  to the right (x 147, 18 high), hidden at tier 3. `TimeToNextTier` = seconds until `tech_level_2` / `tech_level_3`
  (`TECH_LEVEL_x_SECONDS[league]` - `tick_counter`).
- Tooltips: `core_gold_hint`, `core_wood_hint`, `core_income_hint`, `gui_ingame_tech_hint`.

## DeckPanel (bottom centre)
`RegisterDeckSlot`: spawners go to `DeckSlotsSpawner`, others to stage 1/2/3 by `Techlevel`; slot order is the
deck order (`Deck` sort). Layout = horizontal stack: `instant` (stage 1, 2, 3 groups) then `spawner` group
with `Margin-left 80`. Height 75, slots (`build-slot-wrapper`) 85x90 with 1 px padding each side (pitch 85; measured 85 on the 1920 Rise of Legions shots).
- Deco behind each stack at 80 % height: `deck_main_left/mid/right.png` (66/82/125 x 63, mid stretched) and
  `deck_spawner_left/mid/right.png` (73/55/67 x 63).
- Group 2/3 while locked (`.disabled`): slots shifted down 55 %, a `tier-timer` plate above
  (`tier_block_multi_end.png` 41x75 both ends, `tier_block_multi_mid.png` repeated; `tier_block_single.png`
  84x75 for a one-card group) with the countdown (`IntToTime`, top 7 %, font 25 % of height, white) and
  `lock_icon.png` (19x26) to its right. Timer = time to that tech level.
- Slot: `icon-frame` = `Shared/CardIcons/Card_<Spawner|Colors>[_Spell].tga`, icon = `<Colors><Name>.tga`
  (`Name` = script file name without `Drop/Spawner/Building/Spell/Golems`; colours in enum order
  Colorless, Black, Green, Red, Blue, White, golems are `Colorless`). These `.tga` are 512x256 mip atlases:
  the icon is the left 256x256 square (use `AtlasTexture`). Ready glow behind: `highlight_drop.png` 113 % width,
  centre 13.5 % up (`highlight_spawner.png` 215 % width, 24 % up for spawners). Not ready: darken-soft.
- Cooldown: radial fill (`ProgressMask*.tga` circle) covering `1 - ChargeProgress` while charges < cap;
  numeric seconds (`FloatToCooldown`) centred when charges < 1 (not for epics), font 50 %.
- Small layout (verified on the owner's screenshots, 2026-09-17): slot pitch 66, frame 66 at the wrapper top (2 px below
  the window edge), badges anchored to the 64 px wrapper bottom. The hotkey badge is hidden unless `coGameplayShowDeckHotkeys` (default false, `DeckCard.dui` `hud.ShowCardHotkeys`): `DeckPanel.show_hotkeys`.
- `charge-text` bottom-left (-2,-2) 22 % high on `charge_background.png` (22x22); `hotkey` bottom centre 20 %
  high on `hotkey_background.png` (46x41), text = the user's binding for slot N (defaults `1`..`9`, `0`, `-`, `=`
  on a US layout; German `ß` / `´` in the source), alt bindings Shift+1..6 for slots 7-12.
- `btn-spawner-jump` (`nexus_jump_btn.png` 67x61, hover variant) right of the spawner stack, 80 % height:
  `core_spawner_jump` = "Switch between current position and base".
- Hover over a slot shows `CardHint.dui` (`MainMenu/Shared/Card/CardHUD.dui`) at 334 wide, 260 px above the
  bottom: the small card summary, later the ability box (two-stage in the live client).

## Minimap (bottom right, `map_panel.png` 302x302)
Content 281x281 bottom-right; `map_minimap.png` (281x281, `map_minimap_single.png` for the one-lane map).
Menu button (`menu_button*.png` 62x58) centred at 10.5 % / 9.8 % from the bottom-right, 17 % wide. Pings
(`ping_generic/attack/defense.png`) only in team mode, top-left of the map, 19 % high.
`TMiniMap.WorldToMiniMap`: GUI rect = map rect inflated by -38 px, translated (3, -1); world rect =
`Map.MapBoundaries` (`game/data/maps/*.json` `bounds`); map x from world X, y from world Z (our `Vector2.y`);
centre, rotate by `angle(UNITZ, CAMERAOFFSET.xz) - PI / 37.25` (= 137.4 - 4.8 deg), mirror along x=y (swap),
scale 1.8, back to the centre, clamp to the GUI rect (not for the camera view quad). Icons
(`SizeToMinimapSize` = `2 * (4 + size * 1.8)` px, bigger drawn behind): units `MinimapUnitIcon.png` and
buildings `MinimapBuildingIcon.png` tinted with the team colour, size = collision radius; nexus
`minimap_icon_nexus_<team>.png` size 5; lanetowers and lane nodes `minimap_icon_tower_<team>.png` size 2.5
(neutral = 0); charm fields `MinimapCharmIcon.png` radius x 0.25; bosses `MinimapBossIcon.png` 3.
The camera frustum's four ground hits are drawn as a white outline (`IdleViewQuad`).

## Tooltip / unit panel (`info_panel_background.png` 257x371, right edge, centre at 40 % height)
Shown for the selected entity (click; `Selection.png` / `SelectionBuilding.png` 512x512 decals on the ground
under the selection). Content 99 % x 79 %, 6 % down. Portrait (card frame + icon, 48 % wide) hangs above the
name plate: bottom at 10 % of the content; league icon (`Shared/LeagueIcons/League<n>.tga` 91x91, 36 % of the
portrait) with the card level at 85 % / 98 % of the portrait. Name (`card_name_<identifier>[_drop|_spawner]`,
league-suffixed keys first) 11 % high, bold, auto-shrink. Info block at 21 %: health bar 94 % x 15 % (red
`$DFC04040` on `$40000000`, overheal white, caption `hp / max` bold with border), mana bar at +16 % (cyan
`$DF5DCDCF`, uses `reWelaCharge` = ammo when there is no mana), weapon at 25 % and armor at 75 % (30 % wide,
`InfoPanel/Attack/DamageType<Melee|Ranged|Siege>.png`, `InfoPanel/Armor/Armor<Type>.png`, captions: DPS =
damage / cooldown s (`96.0`), armor `armortype_<atX>_caption` = a percentage like `15%`). Spawners show the
produced unit's stats. Abilities line at 71 %: `unitability_name_<name>` of the script's
`TTooltipUnitAbilityComponent`s joined by ", " (now in `units.json` as `abilities`); spells show
`card_description_<name>` instead. Hovering the text shows the ability hints (`unitability_hint_*`) and
keyword descriptions (`effect_<keyword>_description`).

## Other panels
- TechnicalPanel top-left 158x34: `59 FPS` (x 0), ping icon (x 62), `NN ms` (x 78), black font.
- Announcements (`AnnouncementBackground.png` 1189x206, 150 px from the top, content padding 29 % 10 %, title
  uppercase bold 70 %, subtitle 32 % at the bottom): `core_announcement_title/subtitle_<uid>`; `stage_1` on the
  first game tick, `stage_2` / `stage_3` (league > 2) on the tech events, `showdown`, each for 2000 ms
  (`TClientGUIComponent.OnGameEvent`). The live client shows a warm-up countdown ("9 / Game is about to begin");
  that subtitle is not in the 2022 Lang tables (`Lang.LIVE_CLIENT_TEXT`).
- Unit bars (`TEntityDisplayWrapperComponent` + `TResourceDisplay*Component`, `EntityComponents.Client.GUI.pas`):
  a GUI stack in world-screen space at `bounding top + 1 + udHealthbarOffset`, anchored at its centre. Health bar
  63x8: background `$99000000`, 1 px inset black border, 1 px padding, fill gradient by displayed team (blue
  `$FF51A2FF`/`$FF2850A0`, red `$FFE66868`/`$FF723333`, grey `$FFDEDEDE`/`$FF404040`), overheal white
  `$FFFFFFFF`/`$FF808080` fills the whole bar behind, progress = `hp / (max + overheal)`. Shown only while damaged
  or with overheal (`coGameplayHealthbarMode` default `hmDamaged`) or while Alt is held; hidden when exiled.
  Extra bars come from the scripts (`units.json` `unit_bars`, extracted from `TResourceDisplayIntegerProgressBar`
  / `TResourceDisplayProgressBarComponent` chains): 63x6, integer bars split into `cap` chunks with 1 px black
  outlines (mana yellow `$FFFAF800`/`$FF8B8A00`, `reWelaCharge` cyan `$FF63D9DB`/`$FF377D7D`), `HideIfEmpty`,
  `FixedCap`, `SizeY`. Chunk in/out animations (200 ms) are not replicated yet. No floating combat text exists
  in the original.
- Card hint ability box (`.skill-hint`, `shared_card.scss`): 250 wide, `$frame` (2 px `$FF5c8989` border, bg
  `$FF3C5757`), each skill = uppercase name on `$FF273A3C` + hint (15 px, `$FFA9DCE7`), then the keyword
  descriptions (`effect_<keyword>_description`) in a lighter box. The 2022 source shows it on hovering the
  description; `hud.CardHintTextVisible` turns true after `CARD_HINT_DELAY` = 800 ms of hover
  (BaseConflict.Classes.Gamestates.GUI.pas:153).
  Tooltip variables (`%(key)`) come from `units.json` `ability_details` (`PassInteger` etc., per-league arrays).
- Chat button "Activate Chat (Enter)" left edge, scoreboard (hold key), menu, final screen (`Victory.png` /
  `Defeat.png` on `banner.png`) come with multiplayer / polish.
