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
