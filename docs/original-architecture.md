# Original Architecture — Rise of Legions (Crystal Clash)

Ground truth: `reference/rise-of-legions` (game client + match server) and `reference/delphi3d-engine`
(engine). Both are read-only clones. Paths below are relative to those roots. Line numbers are from the
pinned clone (Jan 2022 HEAD).

The client (`RiseOfLegions.dpr`) and the match server (`GameServer/RiseOfLegionsGameServer.dpr`) compile
the **same** simulation units (`BaseConflict.Entity.pas`, `BaseConflict.EntityComponents.Shared*.pas`,
`BaseConflict.Map.pas`) with `{$IFDEF SERVER}` / `{$IFDEF CLIENT}` selecting authority vs presentation.
The master/manage server (accounts, matchmaking, shop) is **closed source and not in the repo**.

---

## 1. Entity / Component / Event system

**Entity** — `BaseConflict.Entity.pas:323` `TEntity`: a bag of components + a local `Eventbus` + a
`GlobalEventbus` + a `Blackboard`. Fields: `ID`, `UID`, `ScriptFile`, `Position`/`Front` (2D vectors),
`CollisionRadius`, `TeamID`. Built from DWScript files via `CreateFromScript` (`Entity.pas:386-398`).

**Component groups** — `SetComponentGroup = set of Byte` (`Entity.pas:96`). A "Wela" (weapon/ability) is
*all components sharing one group byte*. Reserved groups (`Constants.pas:224-241`):
`GROUP_APPROACH_MAINWEAPON=0`, `GROUP_MAINWEAPON=1`, `GROUP_BUILDING_LIFETIME=10`, `GROUP_SOUL=11`.
Groups 2..9 are free per unit for abilities. Spells call `ReserveFreeGroup()`.

**Blackboard** — `Entity.pas:100-119`: values indexed by `(event id, group, sub-index)`.
`SetValue(eiWelaDamage, [1], 12.0)` = "group 1 damage is 12". `SetIndexedValue(eiResourceCap, [], reHealth, 200)`.
Serialized server to client.

**Eventbus** — `Entity.pas:141-209`. Three event kinds, seven priorities (`epFirst..epLast`):
- **Read** = pipeline: handlers run in priority order, each receives `Previous` and returns a new value.
  If nobody subscribes, the blackboard value is returned. Armor, buffs, auras all hook Reads
  (`eiWelaDamage`, `eiWelaRange`, `eiCooldown`, `eiSpeed`, `eiArmorType`, `eiTakeDamage`).
- **Trigger** = broadcast; a handler returning `False` consumes it (veto death, veto fire).
- **Write** = sets a value; some persist to the blackboard (`eiTeamID, eiPosition, eiFront, eiOwnerCommander, eiExiled, eiBuildgridBlockedFields`, `Constants.pas:1074-1081`).
- `ReadHierarchic` (`Entity.pas:240`): group value overrides entity-wide value.
- `SubscribeRemote` (`Entity.pas:204`): a component listens on *another* entity's bus (auras, links, projectiles).
- Subscriptions are RTTI attributes: `[XEvent(eiWelaDamage, epHigh, etRead)]`.

**Key event ids** (`Constants.pas:334-1019`): resources `eiResourceBalance/Transaction/Cap/Cost`;
lifecycle `eiNewEntity, eiAfterCreate, eiDeploy, eiKillEntity, eiFree`; loop `eiIdle` (every frame),
`eiGameTick`, `eiGameTickCounter`, `eiGameStart`, `eiGameEvent`, `eiWaveSpawn`, `eiIncome`, `eiLose`,
`eiSurrender`; AI `eiThink`, `eiThinkChain` (consumable); combat `eiTakeDamage, eiWillDealDamage,
eiDamageDone, eiHeal, eiArmorType, eiDamageType, eiDie, eiInstaDie, eiKill, eiKillDone`; wela
`eiIsReady, eiPreFire, eiFire, eiFireWarhead, eiWelaDamage, eiWelaRange, eiWelaTargetCount, eiWelaCount,
eiWelaChance, eiWelaActionpoint, eiWelaActionduration, eiCooldown, eiWelaTargetPossible,
eiWelaValidateTarget, eiWelaUnitPattern, eiEfficiency, eiAttentionrange`; movement `eiSpeed, eiMoveTo,
eiStand, eiSyncPosition, eiGetLane`; spatial `eiEntitiesInRange, eiClosestEntityInRange,
eiEnemiesInRangeEfficiency, eiCollisionRadius`.

**Wela taxonomy** (`EntityComponents.Shared.Wela.pas`, `GameServer/*.Server.Welas.pas`, `*.Warheads.pas`,
`*.Brains.pas`). One ability group is composed of:
1. **Brain** decides when to fire (`TThinkImpulseGameTickComponent` fires `eiThink` each game tick; `TBrainActionComponent`).
2. **Ready gates** answer `eiIsReady`: `TWelaReadyCooldownComponent`, `...CostComponent`, `...NthComponent.Nth(n)`, `...AfterGameEventComponent`, `...EnemiesNearbyComponent`, `...ResourceCompareComponent`, `...UnitPropertyComponent`.
3. **Target constraints** answer `eiWelaTargetPossible`: team, zone, unit property, resource, distance, blacklist.
4. **Targeting** fills the target list (`TWelaTargetingRadialComponent`).
5. **Effect** triggers `eiFireWarhead`: `TWelaEffectInstantComponent`, `...ProjectileComponent`, `...ReplaceComponent`, `...PayCostComponent`, `...FactoryComponent` (spawns).
6. **Warhead** applies damage/heal/buff/spawn per target.
7. **Modifiers** (`TModifier*Component`) intercept Reads of a value group.

## 2. Game loop and tick

Two clocks:
- **Simulation frame**: server thread heartbeat `TARGET_FRAMETIME = 32 ms` (`GameServer/BaseConflict.Game.Server.pas:67`). Each frame triggers `eiIdle`. Movement integrates `ZDiff * eiSpeed`, i.e. **variable dt** (`Shared.pas:713,764`).
- **Game tick**: `GAME_TICK_DURATION = 1000 ms`, `GAME_WARMING_DURATION = 10000 ms` (`Constants.pas:48-49`).
  `TGameTickComponent` (`Shared.pas:356, 1986-2038`): first tick after 10 s warm-up also fires `eiGameStart`.
  Status: `gsLoading` (10 s or more to first tick), `gsWarming` (>0), `gsPlaying`.
  Income, wave spawns, brain thinking, game director events all hang off the 1 s tick.
- `THINK_TIME_INTERVAL = 250 ms` (AI scripts). `UNITSYNCINTERVAL = 3000 ms` (server to client position resync).

**Sync model: server-authoritative, event replication, not lockstep.** `EventIdentifierToNetworkSend`
(`Constants.pas:1058-1071`) whitelists events. Client to server only: `eiUseAbility, eiSurrender, eiClientCommand`.
Server to client: `eiTeamID, eiMoveTo, eiStand, eiSyncPosition, eiDie, eiKillEntity, eiResourceBalance/Cap/Cost,
eiLose, eiPreFire, eiFire, eiCancelFire, eiFireWarhead, eiGameStart, eiGameTick, eiReplaceEntity,
eiWelaSetMainTarget, eiLinkEstablish/Break, eiExiled, eiUnitProperties, eiGameEvent, eiWaveSpawn, ...`.
The client runs the same shared movement components for smoothing; server corrects with `eiSyncPosition`.

**RNG**: not deterministic. Delphi global `random` on the server only (targets, AoE scatter, chance rolls).
**Port decision**: fixed 30 Hz tick + seeded per-match RNG (invisible to players; enables replays and tests).

## 3. Map, lanes, pathfinding

`BaseConflict.Map.pas`. `TMap` owns named polygon **zones** (`Camera`, `Walkzone`, `Drop`, each suffixed
with team id; `Constants.pas:116-118`), a `TBuildZoneManager`, a `TLaneManager`, and world entities loaded
from `Maps/<Map>/<Map>.bcm`. Two maps: `MAP_SINGLE='Single'` (one lane), `MAP_DOUBLE='Classic'` (two lanes).
Map bounds +/-150.

**Lanes** = lists of `RWaypoint` gates (cross-section line + center + direction vectors), hardcoded in
`TLaneManager.Create` (`Map.pas:520-560`) and `.Single` (`:645`):
```
LANE_POINT1 = (-60, -11)  LANE_POINT2 = (-60, -35)  LANE_CENTER = (-60, -23)
NEXUS_POINT = (-96, 0) [two-lane]  /  (-96, -23) [one-lane]
```
Units orient toward the nearest enemy Nexus (`GetLanePropertiesOfEntity`, `Map.pas:584-604`).

**Scenario placement** (`Scripts/Scenarios/PvPRed.dws`, `PvPBlue.dws` mirrored, `PvPBase.dws`):
two-lane: Nexus `(92, 0)`, lanetowers `(48, +/-23)`, lane nodes `(0, +/-23)`;
one-lane: Nexus `(96, -23)`, lanetower `(48, -23)`, lane node `(0, -23)`.

**Build grid**: `BUILDGRID_SIZE = (8, 3)`, `BUILDGRID_SLOTS = 20` (`Constants.pas:57-58`). The four corners
are always blocked (8x3-4 = 20 slots). Example red zone:
`SetPosition(102,17).SetSize(8,3).SetFront(-1,0).SetSpawnTarget(86,6,1,-1)`.

**Pathfinding** (`BaseConflict.Classes.Pathfinding.pas`): square grid, `PATHFINDING_TILE_SIZE = 0.8`,
8-neighbour A*, built from the `Walkzone` polygon. Tiles have **time-reserved** slots
(`TIMESLOTLENGTH = 150 ms`, 50-slot ring buffer) = collision avoidance in space-time, no steering.
`PATHFINDING_MAX_COMPUTED_PATH_LENGTH = 15` world units, so units constantly re-plan. Heuristic follows lane
waypoints. Buildings block tiles permanently.

Default unit speed `eiSpeed = 4/1000` units per ms = **4 u/s** (`Scripts/HelperScripts/UnitTemplate.dws:6`).
Attention range default `22.0`. Collision radii per unit (Rootling 0.45, Footman 0.55, Nexus 3.5).

## 4. Combat

**Armor** (`TArmorComponent.OnDamage`, `EntityComponents.Shared.pas:2043-2078`). Skipped if
`dtIgnoreArmor` in damage type or `Amount <= 1.0`. `Amount := Max(1.0, Factor * Amount - Offset)`:

| Armor | Factor | Offset |
|---|---|---|
| atUnarmored | 1.0 | 0 |
| atLight | 0.85 | 0 |
| atMedium | 0.8, **0.7 vs dtRanged** | 0 |
| atHeavy | 0.7 | **5** |
| atFortified | 1.0, **4.0 vs dtSiege** | 0 |

**Damage types** (`Constants.Cards.pas:31-36`): `dtSiege, dtTrue, dtIgnoreArmor, dtRanged, dtMelee,
dtSplash, dtSpell, dtAbility, dtReflected, dtIrredirectable, dtRedirected, dtAntiAir, dtHoT, dtDoT,
dtFlatHeal, dtOverheal, dtCharge`.

**Pipeline**: `eiWelaDamage` Read (modifiers), then warhead, then target `eiTakeDamage` Read chain (armor at
`epMiddle`, `THealthComponent.OnDamage` at `epLower`), then attacker `eiWillDealDamage`/`eiDamageDone`.
Health = resource `reHealth`; `reOverheal` capped at `OVERHEAL_LIMIT_FACTOR = 2.0`. Death: HP <= 0 polled
on idle, then `eiDie` (vetoable) / `eiInstaDie` when killed from full HP.

**Attack timing** (`Server.Brains.pas:2924-2941`): `eiPreFire`, wait `eiWelaActionpoint` ms (hit lands),
then `eiFire`; unit is locked for `Max(Actionpoint, Actionduration)`; `eiCooldown` gates re-fire.
E.g. Footman: cooldown 2000, Archer: actionpoint 350 of 833 ms.

**Targeting** (`Server.Welas.pas:1740-1790`): candidates from `eiEnemiesInRangeEfficiency`, sorted by
(1) higher efficiency, (2) `upLowPrio` last, (3) nearest; take `eiWelaTargetCount`. Efficiency is a Read
chain (`MissingHealth`, `MaxHealth`, `Created` variants) so healers/anti-air pick sensibly.

## 5. Economy and rules (`BaseConflict.Game.pas:222-236`, `Scripts/Scenarios/Game.dws`)

```
StartingGold 300   GoldCap 400   GoldCapPerTier 100   StartingWood 1600   StartingTier 1 (max 3)
StartingIncomeRate 10 gold/tick   IncomeRatePerIncomeUpgrade 2   IncomeUpgradeCap 10
StartingIncomeUpgradeCost 1500 wood   IncomeUpgradeCostPerIncomeUpgrade 250
GadgetCountCap 5   CharmCountCap 3
```
- Income paid each tick (`TWelaEffectIncomePayoutComponent`); gold above cap overflows into **wood**.
- Spawner wave every **2 s** (`Nth(2)` on the 1 s tick), one spawn per build-grid cell.
- Tech/showdown by league (`Game.dws:36-39`, ticks = seconds):
  `TECH_LEVEL_2 = [3,3,3,4,4] min`, `TECH_LEVEL_3 = [6,6,6,8,8] min`, `SHOWDOWN = [6,9,9,12,12] min`.
  Showdown enables lanetower anti-Nexus shots; no hard time limit.
- **Nexus** (`Scripts/Units/Neutral/Nexus*.ets`): atFortified, radius 3.5, HP by league
  `[2500,3250,3750,3750,3750]` (x2 in 2v2). Attack range 15, dmg `[110,110,120,120,120]` true+ranged,
  ammo cap `[8,16,16,20,20]`, cooldown 1000 ms, ammo recharge `[10000,9000,8000,6000,6000]` ms.
  Spawn-zone radius 31.5. Early-vulnerability ramp on incoming damage.
- Win: Nexus death fires `eiLose(TeamID)`; also surrender. Two teams; `PVE_TEAM_ID = 5`.
- Resources enum: `reGold, reWood, reHealth, reOverheal, reCharge, reTier, reSpawner, reIncomeUpgrade,
  reWelaCharge, reGadgetCount, reCharmCount, ...` (`Constants.pas:194-212`).

## 6. Cards, units, spells, factions

**Scripts** (`Scripts/`, DWScript): `.ets` entity, `.sps` spell card, `.dws` include/modifier.
Each defines `CreateData` (numbers only), `CreateMeta` (+client meshes/anims), `CreateEntity` (+server logic).
Folders: `Units/{White,Black,Blue,Green,Colorless,Golems,Neutral,Scenario}`, `Spells/*`, `HelperScripts`
(`UnitTemplate, CardTemplate, DropTemplate, SpawnerTemplate, BuildingTemplate, SpellTemplate, Globals`),
`Modifiers` (41 buffs), `Links` (37 auras), `Projectiles`, `Scenarios`, `Commander`.

**Card registry** — `BaseConflict.Constants.Cards.pas:879-1196`: **161 cards**
(`AddCard('<uuid>', TCardInfo.Create(type, [color], 'script path', tier))`).
`EnumCardType = (ctDrop, ctSpell, ctBuilding, ctSpawner)`; `EnumEntityColor = (ecColorless, ecBlack,
ecGreen, ecRed[unused], ecBlue, ecWhite)`; `EnumLeague = (leNone, leStone, leBronze, leSilver, leGold, leCrystal)`.
Color from folder name; type from filename (`Spawner`, `Building`, `.sps` = spell, else Drop).
Counts: White 23, Black 27, Blue 28, Green 29, Colorless 54 (27 + 27 PvE Golems mirrors).
Stats are read from the compiled script (`EntityDataCache.Read`): the script is the single source of truth.

**Cost / charges** (`Scripts/HelperScripts/CardTemplate.dws`):
```
GoldCost = 100 + (Tier2: +50 | Tier3: +100) + (Legendary: +100) + (Spell: -20)
Spawner: cost x [8,10,12][Tier], paid in Wood, tier cost forced to 1
Every card also costs 1 charge.
Charges by tier x league: T1 [1,2,3,4,5], T2 [1,1,2,3,4], T3 [1,1,1,2,3], Legendary [1,1,1,1,2]
Recharge ms [league][level]: L1 37000..34000, L2 34000..31000, L3 31000..28000, L4 28000..25000, L5 25000..22000
  x1.5 (T2), x2 (T3), x2.5 (Legendary), x[6,7,8][Tier] (Spawner)
One legendary unit alive per commander (upHasLegendaryUnit gate).
```
**Deck rules** (`BaseConflict.Api.Deckbuilding.pas`): 12 slots; no duplicate; at most 2 colors ignoring
colorless; at most 1 Epic.

**Playing a card**: HUD slot creates `TCommanderSpellData` (targets `ctCoordinate|ctEntity|ctBuildZone|...`),
fires `eiUseAbility` on the commander; server `TWelaReadyCostComponent`, `PayCost`, `FactoryComponent`
spawns, `SuicideComponent` removes the card entity. Drops: placement radius 3.0 in the team `Drop` zone
(expands with lane pushes, `dzNexus/dzDrop` dynamic zones); spawners: 1x1 build-grid cell; spells: `Walkzone`.
Produced units get `SummoningSickness` for 1000 ms.

**White (Order) full table** (main attack = group 1; squad from Drop card):

| Unit | Tier | Class | Armor | HP | Dmg | CD | Range | Squad |
|---|---|---|---|---|---|---|---|---|
| Footman | 1 | melee | Medium | 32 | 13 | 2000 | 1.0 | 4 |
| Archer | 1 | ranged | Unarmored | 19 | 20 | 2000 | 10.0 | 2 |
| Ballista | 1 | ranged | Light | 64 | 23 | 2800 | 14.0 | 1 |
| Priest | 1 | ranged support | Unarmored | 53 | 18 | 2000 | 8.0 | 1 |
| Monk | 1 | melee | Unarmored | 265 | 38 | 2800 | 1.0 | 1 |
| Marksman | 2 | ranged | Unarmored | 28 | 190 | 5000 | 13.5 | 1 |
| HeavyGunner | 2 | ranged ground-only | Light | 240 | 60 | 2800 | 6.0 | 1 |
| Suntower | 2 | building | Fortified | 465 | 50 | 2000 | 11.0 | - |
| Avenger | 3 | ranged flying | Light | 230 | 42 | 2000 | 6.0 | 2 |
| Defender | 3 | melee legendary | Heavy | 1050 | 270 | 1700 | 1.0 | 1 |
| PatronSaint | 3 | ranged legendary | Medium | 680 | 110 | 2300 | 4.0 | 1 |
| MonumentOfLight | 3 | building support | Fortified | 230 | - | - | - | - |

White spells: LightPulse T1, ShieldsUp T1, SurgeOfLight T1, HailOfArrows T2, PromiseOfLife T2, SolarFlare T3.
Other factions: Black 12 entities + 7 spells, Green 13 + 6, Blue 13 + 7, Golems 13 + 5. All stats are
in the `.ets` files; extract with `tools/` scripts, never hand-copy.

**Unit properties** (`Constants.pas:249-289`): classes `upGround, upFlying, upMelee, upRanged,
upRangedGroundOnly, upNoAutoAttack, upSupporter, upUnit, upBuilding, upLowPrio, upNexus, upLanetower,...`;
tiers `upTier1..3, upLegendary, upEpic`; states `upStunned, upRooted, upBlinded, upFrozen, upSoulless,
upGrounded, upLifted, upPetrified` (+ `upSilenced, upBleeding, upBefogged, upBanished`);
`PREVENT_THINKING = [SummoningSickness, Stunned, Frozen, Banished, Petrified]`,
`PREVENT_MOVEMENT = [Rooted, Grounded, Lifted, Immobilized]`; blessings `upBlessed*`; many `upImmuneTo*`.
Buff types: `btNeutral, btPositive, btNegative, btState, btDivine, btSummoningSickness`.

## 7. Networking and server

- One thread per match (`TGameThread`, `Game.Server.pas:185`), TCP only, port range 40000-40255.
- Frame: `SeqLen(2) | Magic(1) | Command(1) | Flags(1) | UniqueID(1) | DataCount(1) | Data`.
- Commands (`Constants.pas:159-177`): `NET_HELLO_SERVER=2, NET_NEW_ENTITY=3, NET_RECONNECT=4,
  NET_SERVER_FINISHED_SEND_GAME_DATA=7, NET_CLIENT_READY=10, NET_EVENT=31, ...`.
- `NET_EVENT` envelope: `EntityID, EventID, Group, ComponentID, IsWrite, params[]`; the entire gameplay
  protocol rides on this. Entity snapshots on join/spawn.
- Reconnect: per-client ring buffer of sent sequences; `RECONNECT_TIME = 60 s`; `MAX_CLIENTS = 16`.
- Handshake: hello(token), world snapshot, finished, client ready, all ready, game start.
- Backend needed for a match is only `RGameFoundData` (`Api.Types.pas:656`): game uid, secret, server
  ip/port, scenario uid, league, players. Testserver mode auto-creates a `sandbox` game.

## 8. Client states and HUD

States (`Constants.Client.pas:51-58`): `LoginSteamMenu, LoginQueue, MainMenu, LoadGame, Game`
(+ `Reconnect, ServerDown, Maintenance`). Main menu tabs: `Start, Game, Deck, Shop, Collection, Tutorial,
Leaderboards, Inventory, GameRewards, GameStatistics`.

HUD markup: `Graphics/GUI/**.dui` (dXML, Vue-like: `{{ }}`, `dxml-if`, `dxml-for`, `dxml-on:click`,
`§loca_key`), styled by `.scss`. Root `Graphics/GUI/Game.dui` includes: `GameInfoBar` (clock, nexus HP,
tier timers), `TechnicalPanel`, `CommanderSwitch`, `Sandbox`, `Tooltip`, `Minimap`, `RessourcePanel`,
`DeckPanel` (3 tier stacks + spawner stack), `Scoreboard`, `Announcements`, `Menu`, `ReconnectDialog`,
`FinalScreen`. View-model = `TIngameHUD` (`Classes.Gamestates.GUI.pas:148-352`): `Gold/GoldCap/GoldIncome,
Wood/WoodIncome, SpentWood, IncomeUpgrades, Tier, TimeToNextTier, DeckSlotsStage1..3, DeckSlotsSpawner,
Ping, FPS, IsBaseUnderAttack, Announcement*, HUDState (hsGame/hsVictory/hsDefeat)`.

**Scenarios** (`Constants.Scenario.pas:316-376`): `sandbox`, `1vs1..4vs4`, `two_lane_*`, `duel*`,
`ranked1vs1/2vs2` (Single), `ranked3vs3/4vs4` (Classic), `tutorial`, `pve_attack_solo` (leagues 1-5),
`pve_attack` (duo), mutators `highly_explosive`, `gigantic`. PvP always loads `PvPBase, PvPRed, PvPBlue, Game.dws`.

**Camera** (`EntityComponents.Client.pas:2061-2445`): offset `(-0.3947, 0.8121, -0.4297)`,
`CAMERAMOVEMENTWEIGHT 0.010`, `ZOOMSPEED 0.2`, rotation speed 0.008, edge-scroll border 10 px (bottom 2).
**Hotkeys** (`Constants.Client.pas:63-136`): `kbDeckslot01..12`, `kbSpellCast`, `kbPing*`, `kbNexusJump`,
`kbCamera*`, `kbScoreboardHold`, ...

## 9. Assets (details in `docs/assets.md`)

Every mesh has an **FBX source** + TGA/PNG textures (`<Name>Diffuse/Normal/Material/Glow`) + a material
`.xml`; `.msh`/`.tex` are compiled artifacts, ignore them. Animations are named frame ranges inside the FBX,
declared per unit in the `.ets` (`CreateNewAnimation(ANIMATION_STAND/ATTACK/WALK, first, last)`).
Particles `.pfx` (XML, mean/variance fields). Maps: `.bcm` zones (XML polygons), `.ter` 513x513 float
heightmap (base64+zlib), `.bcc` decorations, `.veg`, `.wat`, `.lig`. Sound: FMOD Studio `.bank` +
`GUIDs.txt`. Lang: 23 `;`-separated CSV files. GUI: `.dui` + `.scss`. Look: deferred renderer with per-material
`ShadingReduction` (toon), `MeshOutline`, anamorphic glow (`PostEffects.fxs`: Glow anamorphic 4.56,
kernel 4, spread 0.68, 2 iterations; UnsharpMasking 0.36).
