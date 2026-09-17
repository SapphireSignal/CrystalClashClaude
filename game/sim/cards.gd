class_name Cards
## Card registry (game/data/cards.json from BaseConflict.Constants.Cards.pas) and the cost / charge
## formulas of Scripts/HelperScripts/CardTemplate.dws.

const CARDS_PATH := "res://game/data/cards.json"

static var _by_uid: Dictionary = {}
static var _by_script: Dictionary = {}


class CardDef:
	var uid: String
	var type: String          # ctDrop, ctSpawner, ctBuilding, ctSpell
	var colors: Array
	var unit_id: String       # e.g. Units/White/FootmanDrop (key into units.json)
	var tier: int
	var name: String
	var legendary: bool = false

	func is_spawner() -> bool:
		return type == "ctSpawner"

	func is_spell() -> bool:
		return type == "ctSpell"

	func is_drop() -> bool:
		return type == "ctDrop"

	func is_building() -> bool:
		return type == "ctBuilding"


static func load_cards() -> void:
	if not _by_uid.is_empty():
		return
	var file := FileAccess.open(CARDS_PATH, FileAccess.READ)
	assert(file != null, "missing %s, run tools/extract_units.py" % CARDS_PATH)
	for raw in JSON.parse_string(file.get_as_text()):
		var c := CardDef.new()
		c.uid = raw["uid"]
		c.type = raw["type"]
		c.colors = raw["colors"]
		c.unit_id = raw["script"]
		c.tier = int(raw["tier"])
		c.name = raw["name"]
		if not c.is_spell() and UnitDb.has_unit(c.unit_id):
			c.legendary = UnitDb.raw(c.unit_id).get("legendary", false)
		_by_uid[c.uid] = c
		_by_script[c.unit_id] = c


static func by_uid(uid: String) -> CardDef:
	load_cards()
	return _by_uid.get(uid)


static func by_script(unit_id: String) -> CardDef:
	load_cards()
	assert(_by_script.has(unit_id), "unknown card %s" % unit_id)
	return _by_script[unit_id]


static func all() -> Array:
	load_cards()
	return _by_uid.values()


## GetCardBaseCost (CardTemplate.dws:3-20). Gold for drops/buildings/spells, wood for spawners.
static func base_cost(tier: int, legendary: bool, is_spell: bool, is_spawner: bool) -> float:
	var cost := 100.0
	if tier == 2:
		cost += 50.0
	elif tier == 3:
		cost += 100.0
	if legendary:
		cost += 100.0
	if is_spell:
		cost -= 20.0
	if is_spawner:
		cost *= [8, 10, 12][clampi(tier, 1, 3) - 1]
	return cost


## GetCardBaseChargeCooldown (CardTemplate.dws:22-46), milliseconds. league and level are 1..5.
static func charge_cooldown(tier: int, league: int, level: int, legendary: bool, is_spawner: bool) -> int:
	const TABLE := [
		[37000, 36250, 35500, 34750, 34000],
		[34000, 33250, 32500, 31750, 31000],
		[31000, 30250, 29500, 28750, 28000],
		[28000, 27250, 26500, 25750, 25000],
		[25000, 24250, 23500, 22750, 22000]]
	var result: int = TABLE[clampi(league, 1, 5) - 1][clampi(level, 1, 5) - 1]
	if tier == 2:
		result = result * 3 / 2
	elif tier == 3:
		result = result * 2
	if legendary:
		result = result * 5 / 2
	if is_spawner:
		result *= [6, 7, 8][clampi(tier, 1, 3) - 1]
	return result


## Charge count per tier and league (CardTemplate.dws:52-62).
static func charge_count(tier: int, league: int, legendary: bool) -> int:
	var l := clampi(league, 1, 5) - 1
	if legendary:
		return [1, 1, 1, 1, 2][l]
	match tier:
		1: return [1, 2, 3, 4, 5][l]
		2: return [1, 1, 2, 3, 4][l]
	return [1, 1, 1, 2, 3][l]
