"""Copy the original GUI images and fonts the HUD needs into assets/ (phase 4).

Sources: reference/rise-of-legions/Graphics/GUI (png/tga, the .tex compiled copies are ignored) and
Graphics/Fonts. Output keeps the relative path under assets/ui/ so a .dui/.scss reference such as
HUD/DeckPanel/deck_main_left.png maps to res://assets/ui/HUD/DeckPanel/deck_main_left.png.
Run: python tools/copy_ui_assets.py
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUI = ROOT / "reference" / "rise-of-legions" / "Graphics" / "GUI"
FONTS = ROOT / "reference" / "rise-of-legions" / "Graphics" / "Fonts"
OUT = ROOT / "assets" / "ui"
OUT_FONTS = ROOT / "assets" / "fonts"

# folders copied whole (png + tga), relative to Graphics/GUI
FOLDERS = [
    "HUD/DeckPanel", "HUD/GameStatePanel", "HUD/InfoPanel", "HUD/MinimapPanel", "HUD/RessourcePanel",
    "HUD/InfoPanel/Attack", "HUD/InfoPanel/Armor", "HUD/TechnicalPanel", "HUD/Announcements", "HUD/FinalScreen", "Shared/CardIcons", "Shared/LeagueIcons",
    "Shared/FactionIcons", "MainMenu/Shared/Card",
    "Shared/Logos", "Shared/AnimatedBackground", "MainMenu/LoadingScreen",
    "MainMenu/Navbar", "MainMenu/Dashboard", "Shared/CurrencyIcons",
]
FILES = ["Shared/Spinner.png", "HUD/Selection.png", "HUD/SelectionBuilding.png", "Shared/button_xl.tga", "Shared/button_xl_hover.tga",
         "Shared/Lock.png", "Shared/Icons/UnknownPlayer.png", "MainMenu/Deckbuilding/new_flag.png"]
FONT_FILES = ["ProzaLibre-Regular.ttf", "ProzaLibre-Medium.ttf", "ProzaLibre-SemiBold.ttf",
              "ProzaLibre-Bold.ttf", "ProzaLibre-ExtraBold.ttf"]


def copy(src: Path, rel: Path) -> None:
    dst = OUT / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
        shutil.copy2(src, dst)


def main() -> int:
    if not GUI.is_dir():
        print(f"missing {GUI}", file=sys.stderr)
        return 1
    count = 0
    for folder in FOLDERS:
        for src in (GUI / folder).iterdir():
            if src.suffix.lower() in (".png", ".tga"):
                copy(src, src.relative_to(GUI))
                count += 1
    for rel in FILES:
        copy(GUI / rel, Path(rel))
        count += 1
    OUT_FONTS.mkdir(parents=True, exist_ok=True)
    for name in FONT_FILES:
        shutil.copy2(FONTS / name, OUT_FONTS / name)
    print(f"copied {count} images and {len(FONT_FILES)} fonts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
