class_name MainMenu
extends Control
## The logged-in menu shell (MainMenu.dui, mainmenu.scss): the `.overlay` with the Navbar over the `.main-content`
## screens, of which one is shown by `menu.CurrentMenu` (EnumMenuType mtStart/mtGame/mtDeck/mtCollection/
## mtLeaderboards/mtShop). Built so far: the Dashboard (mtStart). Choosing Play (mtGame) asks the app to start
## the sandbox until the Teambuilding screen exists; the other screens are still empty.
##
## There is no master server or account: PROFILE and SERVER_STATE hold the local player's stand-in values
## (name/level/currencies, players online, the announcement, the patch-notes date = the repo snapshot's).

signal play_requested

enum Menu { START, GAME, DECK, COLLECTION, LEADERBOARDS, SHOP }

const PROFILE := {"name": "Player", "level": 1, "level_progress": 0.0, "credits": 0, "crystals": 0}
const SERVER_STATE := {
	"players_online": 1,
	"dashboard_headline": "Rise of Legions",
	"dashboard_text": "Godot port of the 2022 source. Choose Play to start a sandbox match against the AI.",
	"scill_banner_index": 0,
	"latest_patch_notes": "01-19",   # F.Date (en: MM-DD) of the public snapshot's last commit, 2022-01-19
}

var current_menu: int = Menu.START
var navbar: Navbar
var dashboard: Dashboard


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	dashboard = Dashboard.new(SERVER_STATE)   # .main-content, below the overlay
	add_child(dashboard)
	navbar = Navbar.new(PROFILE)              # .overlay ZOffset 1000: drawn last
	navbar.menu_selected.connect(set_current_menu)
	add_child(navbar)
	set_current_menu(Menu.START)


func set_current_menu(menu: int) -> void:
	current_menu = menu
	navbar.select(menu)
	dashboard.visible = menu == Menu.START
	if menu == Menu.GAME:
		play_requested.emit()
