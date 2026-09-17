# Reference material (outside this repo)

Two read-only places hold real-game references. Nothing here is copied into the repo; later phases read
from these paths directly. Rights: the developers gave the owner permission to use everything.

## `reference/media/` (this repo, gitignored)
Drop folder for screenshots and videos the owner records from the real game. Empty except its README as
of 2026-09-16. Check it before the HUD (phase 4) and asset (phase 5) work.

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

## Owner screenshots of the live Crystal Clash client (2026-09-16, sent in chat; files to follow in `reference/media/`)
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
