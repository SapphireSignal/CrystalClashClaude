class_name HudStyle
## Shared HUD look: fonts, textures, card icon atlases, colours and the original's formatting helpers
## (docs/hud.md). Everything is loaded from the 1:1 copies in assets/ui and assets/fonts.

const UI := "res://assets/ui/"
const FONT_REGULAR := preload("res://assets/fonts/ProzaLibre-Regular.ttf")
const FONT_MEDIUM := preload("res://assets/fonts/ProzaLibre-Medium.ttf")
const FONT_SEMIBOLD := preload("res://assets/fonts/ProzaLibre-SemiBold.ttf")
const FONT_BOLD := preload("res://assets/fonts/ProzaLibre-Bold.ttf")
const FONT_EXTRABOLD := preload("res://assets/fonts/ProzaLibre-ExtraBold.ttf")

# scss colours are ARGB ($AARRGGBB)
const WHITE := Color(0xE9 / 255.0, 0xFE / 255.0, 0xFF / 255.0, 0xEF / 255.0)
const BLACK := Color(0x40 / 255.0, 0x40 / 255.0, 0x40 / 255.0, 0xEF / 255.0)
const CYAN := Color(0x49 / 255.0, 0xA7 / 255.0, 0xAC / 255.0, 1.0)
const DARKEN_SOFT := Color(0x26 / 255.0, 0x3D / 255.0, 0x42 / 255.0, 0xAC / 255.0)
const DARKEN := Color(0x26 / 255.0, 0x3D / 255.0, 0x42 / 255.0, 0xCC / 255.0)
const COOLDOWN := Color(0x26 / 255.0, 0x3D / 255.0, 0x42 / 255.0, 1.0)
const COOLDOWN_READY := Color(0x26 / 255.0, 0x3D / 255.0, 0x42 / 255.0, 0x30 / 255.0)
const HEALTH_RED := Color(0xC0 / 255.0, 0x40 / 255.0, 0x40 / 255.0, 0xDF / 255.0)
const HEALTH_BACK := Color(0, 0, 0, 0x40 / 255.0)
const MANA_CYAN := Color(0x5D / 255.0, 0xCD / 255.0, 0xCF / 255.0, 0xDF / 255.0)
const TEAM_COLORS := [Color("404040"), Color("0090FF"), Color("FF0000")]
const COLOR_ORDER := ["Colorless", "Black", "Green", "Red", "Blue", "White"]   # EnumEntityColor order

static var _cache: Dictionary = {}
static var _blur_material: ShaderMaterial


## Texture by path under assets/ui (e.g. "HUD/DeckPanel/lock_icon.png"), null when the file is missing.
static func tex(rel: String) -> Texture2D:
	if _cache.has(rel):
		return _cache[rel]
	var path := UI + rel
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[rel] = t
	return t


## The card icon .tga files are 512x256 atlases with the icon in the left 256x256 square. File names
## differ in case from the script names (BlackVoidbane.tga for VoidBane), so the folder is matched case-insensitively.
static func card_atlas(rel: String) -> Texture2D:
	var key := "atlas:" + rel
	if _cache.has(key):
		return _cache[key]
	var base := tex(_real_name(rel))
	var t: AtlasTexture = null
	if base != null:
		t = AtlasTexture.new()
		t.atlas = base
		t.region = Rect2(0, 0, 256, 256)
	_cache[key] = t
	return t


static var _folder_index: Dictionary = {}   # folder -> {lowercase file name -> real file name}


static func _real_name(rel: String) -> String:
	var folder := rel.get_base_dir()
	if not _folder_index.has(folder):
		var index := {}
		for file in DirAccess.get_files_at(UI + folder):
			var name := file.trim_suffix(".import").trim_suffix(".remap")
			index[name.to_lower()] = name
		_folder_index[folder] = index
	return folder + "/" + _folder_index[folder].get(rel.get_file().to_lower(), rel.get_file())


## "GreenBlack" for the card colours in enum order (golems are Colorless).
static func color_string(colors: Array) -> String:
	var names := []
	for c in colors:
		names.append(str(c).trim_prefix("ec"))
	var out := ""
	for name in COLOR_ORDER:
		if names.has(name):
			out += name
	return out if out != "" else "Colorless"


## Shared/CardIcons/<Colors><Name>.tga: Name = script file without Drop/Spawner/Building/Spell.
static func card_icon(card: Cards.CardDef) -> Texture2D:
	var name := card.unit_id.get_file().get_basename()
	for suffix in ["Drop", "Spawner", "Building", "Spell"]:
		name = name.trim_suffix(suffix)
	return card_atlas("Shared/CardIcons/%s%s.tga" % [color_string(card.colors), name])


static func card_frame(card: Cards.CardDef) -> Texture2D:
	if card.is_spawner():
		return card_atlas("Shared/CardIcons/Card_Spawner.tga")
	return card_atlas("Shared/CardIcons/Card_%s%s.tga" % [color_string(card.colors), "_Spell" if card.is_spell() else ""])


## Icon of a battlefield unit: <Color><Name>.tga, base buildings carry the displayed team as suffix
## (ColorlessNexusLevel1Blue.tga).
static func unit_icon(unit_id: String, displayed_team: int) -> Texture2D:
	var name := unit_id.get_file().get_basename()
	var color := unit_color(unit_id)
	var plain := card_atlas("Shared/CardIcons/%s%s.tga" % [color, name])
	if plain != null:
		return plain
	var team_name := "Blue" if displayed_team == 1 else "Red"
	return card_atlas("Shared/CardIcons/Colorless%s%s.tga" % [name, team_name])


static func unit_frame(unit_id: String) -> Texture2D:
	return card_atlas("Shared/CardIcons/Card_%s.tga" % unit_color(unit_id))


static func unit_color(unit_id: String) -> String:
	if not UnitDb.has_unit(unit_id):
		return "Colorless"
	var values: Dictionary = UnitDb.raw(unit_id)["values"]
	var identity: Variant = values.get("eiColorIdentity", {}).get("*", "ecColorless")
	return str(identity).trim_prefix("ec")


static var _stats_cache: Dictionary = {}


## A unit's blackboard stats (health, damage, cooldown, armor) for tooltips, built once per league / level.
static func unit_stats(unit_id: String, league: int, level: int) -> SimEntity:
	var key := "%s:%d:%d" % [unit_id, league, level]
	if not _stats_cache.has(key):
		var e := SimEntity.new()
		e.setup(unit_id, league, level)
		_stats_cache[key] = e
	return _stats_cache[key]


## units.json `ability_details`: the script's TTooltipUnitAbilityComponents (name, keywords, vars).
static func ability_details(unit_id: String) -> Array:
	if not UnitDb.has_unit(unit_id):
		return []
	return UnitDb.raw(unit_id).get("ability_details", [])


## coGameplayFixedTeamColors: the own team is shown as 1 (blue), the enemy as 2 (red), neutral 0.
static func displayed_team(team: int, own_team: int) -> int:
	if team == 0:
		return 0
	return 1 if team == own_team else 2


static func team_color(team: int, own_team: int) -> Color:
	return TEAM_COLORS[displayed_team(team, own_team)]


## HString.IntToTime: seconds -> "mm:ss" (minutes capped at 99).
static func int_to_time(seconds: int) -> String:
	seconds = maxi(0, seconds)
	return "%02d:%02d" % [mini(seconds / 60, 99), seconds % 60]


## HGUIMethods.FloatToCooldown: tenths below 2 s ("1.5"), whole seconds above.
static func float_to_cooldown(seconds: float) -> String:
	var tenths := roundi(seconds * 10.0)
	if tenths < 20:
		return "%d.%d" % [tenths / 10, tenths % 10]
	return str(tenths / 10)


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


static func label(text: String, size: int, color: Color = WHITE, font: Font = FONT_REGULAR,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func outline(l: Label, px: int, color: Color = Color(0, 0, 0, 0.9)) -> Label:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", color)
	return l


static func picture(texture: Texture2D, rect: Rect2) -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # before texture/size: otherwise the minimum size sticks
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture = texture
	r.position = rect.position
	r.size = rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## `Blur : True` area: the scene behind it blurred and tinted (game/ui/blur_backdrop.gdshader), drawn behind
## the panel art (ZOffset -1), so translucent panel images show a soft teal version of the world.
static func blur(r: Rect2) -> ColorRect:
	if _blur_material == null:
		_blur_material = ShaderMaterial.new()
		_blur_material.shader = preload("res://game/ui/blur_backdrop.gdshader")
	var c := ColorRect.new()
	c.material = _blur_material
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func rect(color: Color, r: Rect2) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size


## Shrinks the font until the text fits the label's width (the original's auto-shrink captions).
static func fit(l: Label, max_size: int, min_size: int = 8) -> void:
	var font: Font = l.get_theme_font("font")
	var size := max_size
	while size > min_size and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > l.size.x:
		size -= 1
	l.add_theme_font_size_override("font_size", size)
