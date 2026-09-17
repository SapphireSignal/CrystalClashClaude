# Pre-match screens spec (loading / login / main menu / matchmaking)

Ground truth: `reference/rise-of-legions/BaseConflict.Classes.Gamestates*.pas` (state machine + view-models),
`Graphics/GUI/*.dui` (markup) + `Graphics/GUI/Stylesheets/*.scss` (pixel layout), same method as `docs/hud.md`.
Engine unit/anchor semantics: `reference/delphi3d-engine/Engine/Engine.GUI.pas`.

## 1. Client state flow

States are string-keyed singletons in `TGameStateManager` (`BaseConflict.Classes.Gamestates.pas:268-382`,
registered via `AddNewGameState`/`ChangeGameState`, ids `BaseConflict.Constants.Client.pas:51-58`):

| id (`GAMESTATE_*`) | class | value string |
|---|---|---|
| `GAMESTATE_INGAME` | `TGameStateCoreGame` (`:1589`) | `'Game'` |
| `GAMESTATE_LOADGAMESTATE` | `TGameStateLoadCoreGame` (`:1641`) | `'LoadGame'` |
| `GAMESTATE_MAINMENU` | `TGameStateMainMenu` (`:1412`) | `'MainMenu'` |
| `GAMESTATE_LOGINSTEAM` | `TGameStateLoginSteam` (`:1382`) | `'LoginSteamMenu'` |
| `GAMESTATE_LOGIN_QUEUE` | `TGameStateLoginQueue` (`:1348`) | `'LoginQueue'` |
| `GAMESTATE_RECONNECT` | `TGameStateReconnect` (`:1390`) | `'Reconnect'` |
| `GAMESTATE_SERVER_DOWN` | `TGameStateServerDown` (`:1328`) | `'ServerDown'` |
| `GAMESTATE_MAINTENANCE` | `TGameStateMaintenance` (`:1335`) | `'Maintenance'` |

`TGameStateServerDown`, `TGameStateMaintenance`, `TGameStateLoginQueue`, `TGameStateMainMenu` all derive from
`TGameStateMenu` (`:1317`), which owns the shared `TAnimatedImage` background used by every full-screen menu
state (`EnterState`/`LeaveState` at `:1317-1325`).

Transitions observed (`grep ChangeGameState`, `BaseConflict.Classes.Gamestates.pas`):
- Steam login success -> `GAMESTATE_MAINMENU` (`:7232`, `Account.IsConnected`).
- Login queue "go" -> presumably login continues into `GAMESTATE_MAINMENU` (queue component `:1348-1379`
  polls `FServerPollingRate`/`FALLBACK_POLLING_RATE = 10000` ms and a `TWebSocketClient` to a login-queue
  broker; `FFallbackLoginDelayWaited` falls back to polling the account API directly if the websocket doesn't
  respond) — entered from `:7595` (`ChangeGameState(GAMESTATE_LOGIN_QUEUE)`).
- Server reports maintenance -> `GAMESTATE_MAINTENANCE` (`:3045`); polls `SERVER_STATUS_POLL_INTERVAL = 5000`
  ms (`:1335-1343`) until maintenance ends, then back to main menu.
- Disconnect while ingame -> `GAMESTATE_RECONNECT` (`:2959`), which owns `IsReadyToReconnect` /
  `ForceBrokerFallback` published properties and a `Reconnect` action (`:1390-1411`); returns to
  `GAMESTATE_INGAME` on success or `GAMESTATE_MAINMENU` on give-up.
- Match found / play pressed -> matchmaking hands off a `TGameData` to `TGameStateLoadCoreGame`
  (`GameData := Game.Data` then `ChangeGameState(GAMESTATE_LOADGAMESTATE)`, `:4030-4033`), which loads assets
  and connects the game socket, then `ChangeGameState(GAMESTATE_INGAME)` (`:3143-3146`).
- Leaving a match (surrender, win/loss ack, disconnect-abort) -> `ChangeGameState(GAMESTATE_MAINMENU)`
  (`:2470`, `:3151`, `:4027`, `:7142`), each also clearing the finished game's statistics component.
- `TGameStateMainMenu` (`:1412-1447`) has its own sub-states as booleans, not separate `TGameState`s:
  `IsPreLoading` (asset preloader gate, closes `diPreloading` dialog via `SetIsApiReady`, `:2122-2128`),
  `IsLoading` (per-navigation loading spinner, queues a `TActionSetVariable` when `MainActionQueue` is
  active, `:2134-2153`), `IsLoadingSlow` (after `SLOW_LOADING_TIME = 40*1000` ms, `:1416`), and `CurrentMenu :
  EnumMenu` (`mtStart, mtGame, mtDeck, mtShop, mtCollection, mtTutorial, mtLeaderboards, mtInventory,
  mtGameRewards, mtGameStatistics`, `:1410`) which the dashboard/navbar/deckbuilder/shop/collection panels
  all gate on inside the single `MainMenu.dui`/`mainmenu` div — the "screens" are CSS-visibility toggles of
  siblings in one state, not separate `TGameState`s.
- Window mode changes with the state: `SetIngameWindow` (`:2077-2116`) resizes/borders the window for
  `wmIngame`; the menu states use the desktop window chrome instead (`SetClientWindow`, `:1967`).

Master-server-dependent features (absent in the public repo, which ships only the game client + game server,
per `README.md` "we only reveal our client and game server code. The master server code ... will remain closed
source"): account login/Steam auth (`TGameStateLoginSteam`), the login queue broker, matchmaking pairing
(`TGameStateComponentMatchMaking`, `:383-488`), the shop/purchases (`TGameStateComponentShop`, `:843-904`),
collection/inventory persistence (`TGameStateComponentCollection`/`Inventory`, `:1178-1213`, `:682-723`),
leaderboards (`:1214-1246`), quests (`:1247-1270`), friendlist (`:1271-1316`), player level/profile
(`:1028-1177`), notifications (`:979-1010`), server status/maintenance polling. None of these can run without
the closed-source master server; a from-scratch Godot client can only fake their data.

**Sandbox path** (works standalone, per `README.md` "Compile the game server and start it. Compile the client
and start it. The client should automatically connect to the game server and a sandbox game should be
running."): `HScenario.IsSandbox` (`BaseConflict.Constants.Scenario.pas:210`) matches scenario UIDs
`SCENARIO_SANDBOX_UID` / `_DUO_` / `_CLASSIC_` (`:316-318`, all using `Sandbox.dws` on `MAP_SINGLE` or
`MAP_DOUBLE`); `TGameInformation.IsSandbox` (`BaseConflict.Game.pas:324-327`) is also forced true by
`IsSandboxOverride`, which the **game server** reads from an ini flag `TESTSERVER_SANDBOX_CONTROLS`
(`BaseConflict.Classes.Gamestates.pas:2399`, default `False`) — i.e. the client that ships in the repo
auto-connects to `localhost`'s game server and the server decides to run the sandbox scenario; there is no
menu flow for it because it bypasses matchmaking entirely (`Game.IsSandbox`, `BaseConflict.Game.pas:263-265`).
`HUD.IsSandbox`/`IsSandboxControlVisible` are set from `Game.GameInfo.IsSandbox` when entering the core game
(`:2498-2499`) and toggle a sandbox-only GUI panel (`core_game_sandbox.scss`, `kbSandboxGUIToggle`
`Constants.Client.pas:92`) with free card play (`Commander.free_cards`, already noted in `CLAUDE.md`).
Our sandbox (`game/main.tscn`) already reproduces this: no login/menu, straight into a local match.

## 2. Screen layouts

Design space and unit conventions are the same as `docs/hud.md` (1920x1080, `Size : 100bw auto` etc.); values
below are quoted verbatim from the `.dui`/`.scss` files.

### LoadingScreen (`Graphics/GUI/LoadingScreen.dui`, in-match loading; not the menu's own loader)
Root: `<wrapper class="loading" :visible="client.State = csLoadCoreGame">`. Children:
- `.background > progress.loading-progress`: `bar` width bound to `{{ loading.Progress * 100 }}%`; `.loading-
  state` text = `{{ loading.State }}`; `.first-time-hint` shown while `loading.FirstLoading`
  (`§loading_first_time_hint`).
- `.tutorial` wrapper shown while `loading.Stage = lsHint`: full-bleed slide `Shared/Tutorial/tut{{
  loading.SlideIndex }}.png` with a `.logo` and `§loading_tutorial_text_{{ SlideIndex }}` caption.
- `.match` wrapper shown while `loading.Stage = lsMatch`: two `stack`s (`.left` team 1, `.right` team 2) built
  with `dxml-for:static="player in loading.GameData.players"` filtered by `player.team_id`; each row shows
  `{{ player.username }}` and a deck preview (`HClient.GetDeckIcon(player.deck_icon)` icon + `{{
  player.deckname }}`); `.vs-icon` between the stacks.
No matching `loading.scss` selectors were found beyond generic (`loading.scss` has no `.loading` block distinct
from the `.loading-main-page`/`.loading-generic` shared blocks below) — treat position/size as unspecified
(likely full-screen, art-driven) rather than guessing pixel numbers.

### `state_pages_shared.scss` `.state-page` (shared chrome for LoginQueue/Maintenance/ServerDown)
Used by all three "access block" pages below (`Graphics/GUI/Stylesheets/state_pages_shared.scss:1-33`):
- `Padding : 10`.
- `.game-logo`: `Position : 0 -15%`, `Anchor : caBottom`, `ParentAnchor : caCenter`, `Size : 30% auto`
  (bottom-anchored, horizontally centred, 15% of height above centre); nested `.banner` (the release banner)
  `Position : 0 -20%`, `Size : auto 100bh` (100% of its background's height), `Anchor : caTop`, `ParentAnchor :
  caBottom` (sits above the logo). `Shared/Logos/game_logo.png` is **1101x532 px**;
  `MainMenu/LoadingScreen/ReleaseBanner.png` is **432x48 px**.
- `.crunchy-logo` bottom-left, `Size : auto 8%`; `.broken-logo` bottom-left offset `Position : 7%`, `Size : 8%
  auto`; `.fmod-logo` bottom-left offset `Position : 17% -2.5%`, `Size : 8% auto`, `Opacity : 0.7` — three
  publisher/engine/audio logos in a row along the bottom-left, each 8% of screen width/height.
- Also in this file (used by the menu's own generic loading dialogs, not the in-match one):
  `.loading-main-page .opener` (centred wrapped headline, `FontSize : 24`, `FontWeight : 700`), `.status`
  (bottom-anchored spinner + text, `Size : 50% 7.5%`), and `.loading-generic` (centred spinner variant used by
  `MainMenu/GenericLoadingDialog.dui`).

### LoginQueue (`Graphics/GUI/LoginQueue.dui`)
`root.maingui` with 4 edge-darkening `div.black` bars (`left/right/top/bottom`, likely letterbox for non-16:9),
a `client-wrapper` including `SystemPanel`, `SettingsMenu`, `ErrorDialog`, `FeedbackDialog`, then
`wrapper.login-queue-page.access-block-page.state-page`:
- `.game-logo`/`.banner` as above, `state_pages_login_queue.scss:2-4` overrides `.game-logo Position : 0 -15%`
  (same as shared default).
- `stack.content` (`Position : 0 -10%`, `state_pages_login_queue.scss:5-6`) containing `.info-box`: `.title`
  = `§login_queue_caption`, `.text` = `§login_queue_text` (`Position : 0 30%`, `Padding : 5`, `Size : 100%
  45%`, `:9-12`), `.timer` with `.timer-text` = `§login_queue_position_text {{
  loginqueue.PositionInQueue if >= 0 else '-' }}` and `.time` = `{{ F.IntToLongTimeDetail(loginqueue.TimeInQueue)
  }}`.
- `stack.news-tile-split` with two `.news-tile`s (Discord `MainMenu/Dashboard/DiscordLogo.tga`, Steam forum
  `SteamLogo.png`) each `dxml-on:click="client.BrowseTo(...)"`, plus one `.news-tile.without-icon` linking the
  guide — identical pattern on Maintenance/ServerDown below (shared "external links while blocked" widget).
- `stack.social-media`: YouTube/Twitter/Facebook `.pop-out` icons, each `BrowseTo`.
- `ExitDialog` include, then the three logos again (duplicated per-page rather than hoisted, consistent with
  `state-page` being included by each root, not nested).
Published properties driving it: `TGameStateLoginQueue.InLoginQueue`/`PositionInQueue`/`TimeInQueue`
(`BaseConflict.Classes.Gamestates.pas:1370-1376`).

### Maintenance (`Graphics/GUI/Maintenance.dui`)
Same shell as LoginQueue (`root.maingui` -> black bars -> `client-wrapper`), page class
`.maintenance-page.access-block-page.state-page`. `.info-box`: `.title` = `§server_maintenance_title`, `.text`
= `§server_maintenance_text`, `.timer` = `§server_timer_text` + `{{
F.IntToLongTimeDetail(serverstate.MaintenanceRemainingTimeUntilEnd) }}`. `state_pages_maintenance.scss:1-8`
only re-states the shared `.text Position : 0 30% / Padding : 5 / Size : 100% 45%` (no page-specific deltas).
Same news-tile-split + social-media row (this one keeps a 4th icon, `discordLink.png`, unlike LoginQueue).
Backed by `TGameStateMaintenance` (`SERVER_STATUS_POLL_INTERVAL = 5000`, `FPollTimer`,
`BaseConflict.Classes.Gamestates.pas:1335-1347`); `serverstate.MaintenanceRemainingTimeToBegin` (used instead
in `Navbar.dui`'s pre-maintenance warning banner) vs `...UntilEnd` used here.

### ServerDown (`Graphics/GUI/ServerDown.dui`)
Same shell again, `.server-down-page.access-block-page.state-page`; `.info-box` has only `.title`
(`§server_down_title`) + `.text` (`§server_down_text`), no timer (no ETA to give). Same news-tile-split /
social-media / logos. Backed by `TGameStateServerDown` (`:1328-1334`, no extra fields — pure `TGameStateMenu`).

### ErrorDialog (`Graphics/GUI/ErrorDialog.dui`, 10 lines) — a modal, not a full state
`wrapper.error-dialog.backdrop.dialog.disabled :show="client.IsErrorDialogOpen"`: `.window-caption.small` =
`{{ client.ErrorCaption }}`, `.message` = `{{ client.ErrorMessage }}`, one confirm button `{{
client.ErrorConfirm }}` that sets `IsErrorDialogOpen := False`. Driven by `TGameStateManager.ShowError` /
`ShowErrorcode(Raw)` / `ShowErrorConfirm` (`:2164-2187`), settable from *any* state (it's included by
LoginQueue/Maintenance/ServerDown and presumably `Main.dui`).

### ExitDialog (`Graphics/GUI/ExitDialog.dui`, 14 lines) — modal
`wrapper.exit-dialog.backdrop.dialog :show="client.ExitDialogVisible"`, click-outside closes it. `§exit_dialog_
caption` / `§exit_dialog_message`; buttons: feedback (`btn-success`, only `:visible="feedback. <> nil"`),
`§exit_dialog_close_btn_caption` (`btn-danger`, calls `client.CloseNoPrompt`), cancel (`btn-primary`,
`:visible="feedback. = nil"`) — i.e. when the feedback dialog exists it replaces "Cancel" with a 3-button
layout (Feedback / Quit / — ) vs a 2-button layout (Quit / Cancel) otherwise. `TGameStateManager.Close` /
`CloseForcePrompt` / `CloseNoPrompt` / `CanProgramClose` (`:1757-1816`) implement the confirmation.

### `Main.dui` was not found in the repo
No `Graphics/GUI/Main.dui` file exists; the state machine's root document is `MainMenu.dui` itself plus the
per-state includes above (LoadingScreen/LoginQueue/Maintenance/ServerDown are their own top-level `.dui`s
switched by `:visible="client.State = ..."`, not nested under one `Main.dui` shell). Treat "Main.dui" in any
future spec as this set.

### MainMenu (`Graphics/GUI/MainMenu.dui`, 48 lines) — the shell for every logged-in screen
`wrapper.mainmenu.meta-client :visible="client.State = csMainMenu"` includes, in order:
1. `Mainmenu/SystemPanel/SystemPanel.dui`, `MainMenu/LoadingScreen/LoadingScreen.dui` (the *menu's own*
   loading screen, distinct from the in-match one above), `MainMenu/loading.dui`.
2. Everything else is gated on `client.IsApiReady and not menu.IsPreloading and not menu.IsLoading`:
   - an `.overlay` div (visible except during `mtGameRewards`/`mtGameStatistics`) with `Navbar/Navbar.dui`,
     `PlayerIconChooseDialog`, `FeedbackDialog`, `HoverMenu/HoverMenu.dui`, tutorial hint/starter-deck dialogs,
     refer-a-friend dialog;
   - a second always-visible `.overlay` with `Notifications/Notification.dui` and the two card detail dialogs;
   - `.fullscreen-content` wrapper: friendlist invite, start-tutorial-game, rewards, statistics, loot dialog,
     idle dialog, generic loading dialog, level-up dialogs, tutorial video dialog, shop purchase dialog;
   - `.main-content` wrapper: `Dashboard/Dashboard.dui`, `Teambuilding/Teambuilding.dui`,
     `Deckbuilding/Decklist.dui` + `Deckeditor.dui`, `Collection/Collection.dui`, `Leaderboards/Leaderboards.dui`,
     `Shop/Shop.dui` — these six are the "screens" selected by `menu.CurrentMenu`, all mounted simultaneously
     and shown/hidden by their own `:visible="menu.CurrentMenu = mt..."` root class (see Dashboard below), so
     switching screens is instant (no navigation/loading step once past the API-ready gate).

### Navbar (`Graphics/GUI/MainMenu/Navbar/Navbar.dui` + `navbar.scss`)
`.navbar-wrapper` (`Size : 100% auto`, `Background: NavbarBackground.png` — **1280x68 px** art, tiled/stretched
to `100% auto`, `ZOffset : 100` — always on top, `MouseEvents : mePass` so clicks fall through the empty
strip) contains `.navbar` (`Size : 100% $navbar-size` = **100% x 54 px**, `__constants.scss:108`, `Padding : 3
0`):
- `.issue-info` (centred, `Size : 10 100%`, horizontal position 6.5%-9.25% depending on
  `matchmaking.manager.CurrentTeam.Players.Count`, `navbar.scss:8-22`): holds `.maintenance-info` (background
  `Maintenance.png`) and `.server-issues` (background `ServerIssue.png`), each `Size : auto 70%`, popping a
  `.hint` tooltip on hover (`Size : 300 text`, `FontSize : 18`, word-wrap) or `$jello-horizontal` animation
  (`__animation.scss:8-16`, 2000 ms infinite) when `.important`.
- `.navbar-left` stack of nav buttons (`btn-nav`): Start (Home icon), Play (`btn-play`, label swaps to `{{
  F.IntToTime(matchmaking.Queue.TimeInQueue) }}` while `matchmaking.InQueue`, else `§navbar_menu_play`, has a
  `.highlight`/`.selection-indicator`/lock icon), Deck (`§navbar_menu_deckbuilding`, `.new-flag` if any new
  card/deck), Collection ("Legion", locked below player level 1, `player-level-lock` overlay opens
  `diPlayerLevelUpOverview`), Leaderboards (locked below level 5), Shop. Locks read
  `profile.Profile.DisableLevelUnlocks` / `.Level`.
- `.navbar-right > .player-panel`: `.boosts .premium` indicator (click -> Shop premium-time filter),
  `progress.user` (name truncated to 20 chars + level, `bar` width = `{{ profile.Profile.LevelProgress * 100
  }}%`, opens the level-up overview on click, includes `LevelHint.dui`), then `Navbar/Teampanel.dui` and
  `Navbar/ResourcePanel.dui` (the player's currency display in the menu, separate from the in-match
  `RessourcePanel` in `docs/hud.md`).
- Commented out: a feedback-panel toggle button (dead code, left in place).

### Dashboard (`Graphics/GUI/MainMenu/Dashboard/Dashboard.dui` + `dashboard.scss`)
`wrapper.dashboard :visible="menu.CurrentMenu = mtStart"`, `Padding : 20`:
- `.left` (`Size : 57% 100%`): `.title-image` (`Position : 0 -7`, `Size : 100bw auto`, background
  `Dashboard/Header.png`), `.players-online` (`{{ F._d(§misc_players_online,
  profile.Account.CurrentPlayersOnline) }}`, `Position : 0 72.2%`, `Size : 100% 3.5%`, centred text),
  `.beta-announcement` (`Position : 0 72%`, `Size : 100% 20.2%`, `BoxSizing : bsMargin`, `Margin : 20`,
  background `$AF236F7E`; `.title` on `$AF1D4D57` at 45% height, `.text` word-wrapped `FontSize : 16` below
  it) bound to `serverstate.ClientDashboardHeadline`/`Text`, and a disabled social-icon `.news-tile` (dead,
  `:enabled="False"`).
- `.divider` (`Size : 3 100%`, `Position : 59% 0`, colour `$FF1C2A2B`) separates `.left` from
- `.right` (`Size : 39% 100%`, `Position : 61% 0`): vertical `stack` of `.news-tile`s — Scill banner
  (`scill_banner_{{ dashboard.ScillBannerIndex }}.png`, highlighted class while
  `not profile.Profile.ScillHighlightDisabled`), Scill tournaments banner, Steam-chat link, Discord link, and
  a patch-notes tile (`§home_patch_notes_title {{ F.Date(profile.Profile.LatestPatchNotes) }}`). Several
  older tiles (Crystal Sunday event, translation-progress, wiki) are commented out — dead content, skip.
  Generic `.news-tile` base rule (`Size : 100% 80`, `dashboard.scss:60+`) is shared by all the tiles above.

### Teambuilding / matchmaking (`Graphics/GUI/MainMenu/Teambuilding/Teambuilding.dui` + `matchmaking.scss`)
`div.teambuilding :visible="menu.CurrentMenu = mtGame"`, `.disabled` (whole panel greyed + click-through) when
`not CurrentUserIsLeader or matchmaking.InQueue`. Structure:
- `.navbar.navbar-sub`: left `stack` of scenario-type buttons (`es1v1` PvP 1v1 — the only enabled slot in the
  public snapshot; `es3v3`/`es4v4`/ranked variants are commented-out dead code; `es2v2` PvP duo locked below
  level 2; `es1vE`/`es2vE` PvE solo/duo; `esDuel*`); right `stack`: Tutorial, and a `DEBUG` button visible only
  for staging/staff builds (`esSpecial`). Each sets `matchmaking.ChosenScenario`.
- Three dialogs included but not expanded here (summary level per the task): `ScenarioDialog.dui`,
  `DifficultyDialog.dui`, `ChooseDeckDialog.dui`.
- `.content-sub > .layout` (vertical stack, `Size : 0 auto`, each child `Margin-Bottom : 20`,
  `matchmaking.scss:11-19`): `.scenario-type-description` (`Size : 80vw 24`, centred text bound to
  `§scenario_type_description_{{ ChosenScenario }}`, with a jello-animated league hint if
  `matchmaking.HasAutoLeague`), then `.scenario-options-section` (`Margin-Top : 20`) holding
  `.scenario-options` buttons: "choose scenario" (opens `diMatchmakingScenario`) and, for PvE, a difficulty
  picker showing the league icon + `§scenario_difficulty_{{ League }}`. Below (not fully read, summary level):
  deck selection and an "enter queue" button family (`enter_queue_tier_0..3[_hover].png`) with
  `queue_button_glow.png`, backed by `Deck_Hover.tga`/`ChooseDeck.png` art and `Queue.dui`/`Teamlist.dui` for
  the party/queue state once in queue.
- Sizes read from `Graphics/GUI/MainMenu/Teambuilding/*`: `Scenario.tga` 372x208, `DecisionBG.png` 1682x132.

### SettingsMenu (`Graphics/GUI/SettingsMenu.dui`, 58 lines)
`wrapper.settings-dialog.dialog.backdrop :show="dialogs.IsDialogVisible(diSettings)"`, hidden during
`csLoadCoreGame`. `.menu > stack.categories`: two headline groups — "Menu" (Graphics/Sound for the *menu*,
`otMenu`/`otSoundMeta`, disabled while `hud. <> nil` i.e. only outside a match) and "Ingame" (Graphics, Sound,
Gameplay, Keybinding — `otGraphics/otSound/otGameplay/otKeybinding`, always available). `.content` mounts one
of six includes by `settings_menu.Category`: `GameplaySettings.dui`, `GraphicsSettings.dui`,
`MenuSettings.dui`, `SoundSettings.dui`, `MenuSoundSettings.dui`, `KeybindingSettings.dui` (not expanded here,
summary level per the task). Footer `stack.window-buttons`: Save (`DeactivateAndSaveSettings`) / Cancel
(`DeactivateAndDiscardSettings`).

### Other screens (summary level, per the task)
- **Collection** (`MainMenu/Collection/Collection.dui`) and **Deckbuilding** (`Decklist.dui`+`Deckeditor.dui`,
  `deckbuilding.scss`+`deckbuilding_dialogs.scss`) share the card-grid pattern from `Shared/Card/*` (card
  frame + icon atlas, same `.tga` mip layout as the in-match deck slots, `docs/hud.md` DeckPanel section).
- **Shop** (`MainMenu/Shop/*`, `shop.scss`/`shop_tabs.scss`/`shop_shared.scss`/`shop_dialogs.scss`) is
  tab-based (currency/premium/card packs), needs the closed-source purchase backend to function.
- **Quests** (`MainMenu/Quests`, `quests.scss`), **Leaderboards** (`MainMenu/Leaderboards`,
  `leaderboards.scss`), **Loot** (`MainMenu/Loot`, `loot.scss`), **PlayerLevel** (`MainMenu/PlayerLevel`,
  `player_level.scss`) are all read-only presentational panels over master-server data.
- **Idle** (`MainMenu/Idle`) shows an AFK/idle-timeout dialog; **Notifications** (`MainMenu/Notifications`,
  `notifications.scss`) is a toast stack; **SystemPanel** (`MainMenu/SystemPanel`) hosts FPS/build-id/exit
  controls parallel to the in-match `TechnicalPanel`.
- **Shared** (`MainMenu/Shared/*`): `Card/CardHUD.dui`/`CardDetailDialog.dui`/`CardTemplateDetailDialog.dui`
  (the card visual template reused everywhere above and by the in-match `CardHint` in `docs/hud.md`),
  `CardIcons/*`, `LeagueIcons/League<n>.tga` (already used by the in-match info panel).

## 3. GUI engine unit/anchor semantics (`reference/delphi3d-engine/Engine/Engine.GUI.pas`)

- `EnumComponentAnchor = (caTopLeft, caTop, caTopRight, caLeft, caCenter, caRight, caBottomLeft, caBottom,
  caBottomRight, caAuto)` (`Engine.GUI.pas:44`): both `Anchor` (which point of *this* component the
  `Position` is measured from) and `ParentAnchor` (which point of the *parent's* content box that
  `Position` is relative to) use this enum; `AnchorToVector`/`InverseAnchor` (`:1288-1330`) convert an anchor
  to a `-1..1` offset vector and its opposite.
- `EnumBoxSizing = (bsContent, bsMargin, bsPadding)` (`:63`): controls which box `Margin`/`Padding` are applied
  against when computing the component's rect — `bsMargin` (used throughout the lobby scss, e.g.
  `dashboard.scss` `.beta-announcement`) insets the content rect by both `Margin` and `Padding`
  (`Engine.GUI.pas:2879-2953`, the `case FBoxSizing of bsMargin: Result := FRect.Inflate(-FPadding).Inflate(
  -FMargin)` branches).
- `ZOffset` / `ParentOffset`: `TGUIComponent.ZOffset` (`:809`) and the dirty-flag application at `:2264,
  :2344-2358` — each component's actual draw order is `ZOffset * 2` (fill quad) with blur quad at `-1`, font at
  `+1`, scrollbar parts at `+2..+3` (so text always draws after its own background, and children are
  interleaved by `HighestChild.ZOffset`, `:3232-3239`). `.navbar-wrapper { ZOffset : 100 }` is why the navbar
  paints above the dashboard/teambuilding content beneath it.
- Value/unit parsing lives in `RGSSSpaceData.CreateFromString` (`Engine.GUI.pas:7069-7089`): a size/position
  token is classified by suffix, all relative units store a normalized `0..1` value (`Value / 100`) with a
  distinct `SpaceType`:
  - `auto` -> `Auto`; `text` -> `Text(...)` (size to font-measured text + `FONT_WEIGHT_EPSILON`, `:7072`).
  - `%` -> `CreateRelative` — relative to the component's own box (matches `docs/hud.md`'s use of `%`).
  - `cw`/`ch` -> relative to **container** width/height (`CreateRelativeContainerWidth/Height`, i.e. the
    scrollable content area, not the raw parent rect) — this is almost certainly the unit `docs/hud.md`
    describes as "tiny... treat as 0.1 px": `230ch` is 230% of the *container height*, not a special small
    unit; it only looks tiny relative to a much larger container (worth re-deriving numerically later since
    the true meaning is now known precisely, unlike the placeholder note in `docs/hud.md`).
  - `pw`/`ph` -> relative to **parent** width/height (`CreateRelativeParentWidth/Height`, `:7083-7084`).
  - `vw`/`vh` -> relative to the **view** (viewport) width/height (`:7081-7082`).
  - `sw`/`sh` -> relative to the **screen** width/height (`:—`, same file, listed alongside `vw`/`vh`).
  - `bw`/`bh` -> relative to the component's **background image's** native width/height
    (`CreateRelativeBackgroundWidth/Height`, `:7085-7086`) — this is the `100bw auto` pattern noted in
    `docs/hud.md` ("panels are drawn at their texture's native size"): `100bw` means "100% of the background
    art's own pixel width", so the element sizes itself to its art regardless of container.
  - `as` -> `CreateAbsoluteScreen` (absolute screen pixels regardless of DPI scale, `:7087`, `:7052-7058`).
  - bare number -> `CreateAbsolute` (absolute pixels in the component's own space, `:7088`).
  - `inherit` -> `Inherit` (`:7089`).
- `EnumStackOrientation = (soHorizontal, soVertical)` (`:54`) plus `FStackAnchor`
  (`:1181-1183`) drive `<stack>` elements (used everywhere above: navbar buttons, dashboard tiles, teambuilding
  layout) — children are laid out sequentially along the orientation axis from the stack anchor, each
  still positioned by its own `Anchor`/`ParentAnchor`/`Margin` for the cross axis.
- Visibility bindings (`:show="..."` vs `:visible="..."`) are both plain style/property bindings evaluated by
  the DXML binder (outside `Engine.GUI.pas`, in the client's GUI script binder) that toggle the same underlying
  `Visibility`/`Enabled` style keys the engine consumes per-frame (`gtVisibility` is one of the `EnumGSSTag`
  set members enumerated at `Engine.GUI.pas:77` alongside `gtPosition/gtSize/gtAnchor/...`); `:show` additionally
  drives the animated open/close transition (`AnimationName`/`AnimationDuration` in `__animation.scss`) while
  `:visible` is an instant cut — consistent with dialogs (`:show`) vs plain panel toggles (`:visible`) in the
  `.dui` files above.

## 4. Build order proposal

For a playable single-player loop (load -> menu -> play sandbox/vs AI -> match -> result -> back), in order:

1. **Loading screen (menu's own)** — `MainMenu/LoadingScreen/LoadingScreen.dui` + `MainMenu/loading.dui`, gated
   by a fake `IsApiReady`/`IsPreLoading` (no master server, so these can just be "assets imported" flags).
   Needed first because everything else in `MainMenu.dui` is gated behind it.
2. **Main menu shell + Navbar + Dashboard** — enough of `Navbar.dui` to switch `menu.CurrentMenu`, and
   `Dashboard.dui` as the default `mtStart` screen (can stub the news tiles / player-online counter, since
   those need the master server; the layout and Play button do not).
3. **Teambuilding (matchmaking) screen, sandbox/vs-AI only** — reuse `es1vE`/`esSpecial`-style single-scenario
   entry: skip real matchmaking/queueing (`TGameStateComponentMatchMaking` needs the master server) and instead
   let Play jump straight into the existing sandbox (`game/main.tscn`), matching how the reference client
   itself bypasses menus for `Sandbox.dws`. Scenario/difficulty dialogs can be a single hard-coded choice for
   now.
4. **LoadingScreen (in-match, `Graphics/GUI/LoadingScreen.dui`)** — the vs/team display while the map and
   units load; straightforward once `game/main.tscn` startup has a loading phase to show it during.
5. **Ingame** — already built (`docs/hud.md`).
6. **Final screen** — already built (`docs/hud.md`, "victory/defeat banner"); wire its "Continue" to return to
   `GAMESTATE_MAINMENU`/dashboard (step 2), closing the loop.
**GUI canvas (verified, checkpoint 66).** `TGameStateManager.SetClientWindow` sets `GUI.VirtualSize :=
CLIENT_DEFAULT_DIMENSIONS` in every branch: the whole menu is authored on a fixed **1280x720** canvas and scaled to
the client window, so at 1920x1080 every element is 1.5x larger with an identical layout. `SetGameWindow` instead
sets `GUI.VirtualSize := ZERO`, so the in-match HUD is absolute pixels (with the `.small` switch below 1710).
Measured against `reference/rolmedia/lobby`: the navbar edge sits at y=54 in the 1280x720 shot and y=81 in the
1920x1080 one (both virtual 54), and the 1280 shot upscaled 1.5x matches the 1920 one about four times better than
an absolute-pixel overlay. `game/ui/menu/menu_layout.gd` holds the canvas; every menu control lays out against
`MenuLayout.layout_size()`. Window sizing (`ClientSettings.menu_window_size`) ports SetClientWindow's arithmetic:
`ScaledWindowSize` fits the screen to the canvas' 16:9, msDownscaling resolves to msDisabled when the screen holds
the canvas and to msFullscreen otherwise.

7. **SettingsMenu** — built (checkpoint 65): `game/settings.gd` (`ClientSettings`, the TOptionManager options with
   the original defaults, `user://Settings.ini` in the original's section/key layout, snapshot on open, Save/Cancel,
   RevertCategory, the TSettingsWrapper quality presets) and `game/ui/menu/settings_menu.gd` (SettingsMenu.dui +
   settings.scss: 800x580 window, category column with the Menu categories disabled in a match, Gameplay/Sound/
   Graphics rows, revert button, Save/Cancel). `game/ui/menu/ingame_menu.gd` is HUD/Menu.dui (Settings / Surrender
   / Exit to desktop / Back to game), opened by Escape or the minimap's menu button. Not built: the Keybindings rows
   and KeybindingDialog, the two Menu categories' content (menu resolution/scaling/language, menu mixer), the
   SystemPanel button that opens the dialog from the main menu.
8. **SystemPanel** (`MainMenu/SystemPanel/SystemPanel.dui`, menu.scss `.system-panel`) — built (checkpoint 66):
   the three 16x16 buttons at -4/4 top-right (Position -4 4, Size auto 16, `100ch 100%` each with Margin-Left 5),
   above the shell like its ZOffset 20000. Minimize minimizes the window, options opens the settings dialog on the
   Menu category (`OnDialogOpen`: `IsClientWindow` -> otMenu), close opens the **ExitDialog** (`ExitDialog.dui`,
   450x160, Quit / Cancel - the feedback button needs a feedback service, so the `feedback. = nil` layout is used).
   The in-game menu's Quit uses the same dialog (`client.CloseForcePrompt`).

Can wait (all need the closed-source master server or are non-essential polish): login/Steam auth,
LoginQueue, Maintenance, ServerDown (no server to go down), real matchmaking/ranked/2v2v-queue, Shop,
Collection persistence beyond what `deck.gd` already covers, Leaderboards, Quests, Loot, PlayerLevel/XP,
Friendlist, Notifications, ExitDialog/ErrorDialog polish (a plain confirm/alert is enough meanwhile).
