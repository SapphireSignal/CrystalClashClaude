class_name Lang
## Text tables: game/data/lang/en.json (tools/extract_lang.py). Keys are case-insensitive (stored lowercase).

const PATH := "res://game/data/lang/en.json"

static var _table: Dictionary = {}


static func _load() -> void:
	if not _table.is_empty():
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	assert(file != null, "missing %s, run tools/extract_lang.py" % PATH)
	_table = JSON.parse_string(file.get_as_text())


static func has_key(key: String) -> bool:
	_load()
	return _table.has(key.to_lower())


## Text for a key, the key itself when unknown.
static func t(key: String) -> String:
	_load()
	return _table.get(key.to_lower(), key)


## First existing key of several candidates, else the fallback.
static func first(keys: Array, fallback: String) -> String:
	for k in keys:
		if has_key(k):
			return t(k)
	return fallback


## Script identifier used by the lang keys: file name without folder / extension, lowercased
## (Units/White/FootmanDrop -> footmandrop, Spells/White/LightPulse.sps -> lightpulse).
static func identifier(unit_id: String) -> String:
	return unit_id.get_file().get_basename().to_lower()


## TCardInfo name rule: card_name_<ident>_drop / _spawner for the card kinds, else card_name_<ident>.
static func card_name(card: Cards.CardDef) -> String:
	var ident := identifier(card.unit_id)
	var base := ident.trim_suffix("drop").trim_suffix("spawner").trim_suffix("building")
	var keys := []
	if card.is_drop():
		keys.append("card_name_%s_drop" % base)
	elif card.is_spawner():
		keys.append("card_name_%s_spawner" % base)
	keys.append("card_name_%s" % base)
	keys.append("card_name_%s" % ident)
	return first(keys, card.name)


## Name of a battlefield unit (Units/White/Footman -> "Footman", Units/Neutral/NexusLevel1 -> "Nexus").
static func unit_name(unit_id: String) -> String:
	var ident := identifier(unit_id)
	return first(["card_name_%s" % ident], ident.capitalize())
