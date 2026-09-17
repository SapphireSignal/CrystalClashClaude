class_name Deck
## Deckbuilding rules (BaseConflict.Api.Deckbuilding.pas TDeck). 12 slots; a card may appear once;
## at most 2 colors counting all card colors except ecColorless (Crystal Legion fits any deck);
## at most 1 epic card; deck league = max card league (1 if empty). Slot order is TCardInfo.Compare.

const SLOT_COUNT := 12


class DeckCard:
	var card: Cards.CardDef
	var league: int = 1        # TCardInstance.League: the card's own league 1..5
	var level: int = 1         # card level 1..5 within the league

	func _init(p_card: Cards.CardDef, p_league: int = 1, p_level: int = 1) -> void:
		card = p_card
		league = p_league
		level = p_level


var name: String = ""
var icon: String = ""
var slots: Array = []          # SLOT_COUNT entries, DeckCard or null


func _init() -> void:
	slots.resize(SLOT_COUNT)


## TDeck.Colors minus ecColorless, as TDeck.ColorCount counts them.
func colors() -> Array:
	var result: Array = []
	for dc in slots:
		if dc != null:
			for color in dc.card.colors:
				if color != "ecColorless" and not result.has(color):
					result.append(color)
	return result


func color_count() -> int:
	return colors().size()


## TDeck.League: max card league, 1 when empty.
func league() -> int:
	var result := 1
	for dc in slots:
		if dc != null:
			result = maxi(result, dc.league)
	return result


func contains_card(card: Cards.CardDef) -> bool:
	for dc in slots:
		if dc != null and dc.card == card:
			return true
	return false


## TDeck.ColorCheckCard: adding the card must keep the non-colorless color count <= 2.
func color_check(card: Cards.CardDef) -> bool:
	var new_colors := colors()
	for color in card.colors:
		if color != "ecColorless" and not new_colors.has(color):
			new_colors.append(color)
	return new_colors.size() <= 2


## TDeck.EpicCheckCard: only one epic card per deck.
func epic_check(card: Cards.CardDef) -> bool:
	if not card.epic:
		return true
	for dc in slots:
		if dc != null and dc.card.epic:
			return false
	return true


func can_add_card(card: Cards.CardDef) -> bool:
	return not contains_card(card) and color_check(card) and epic_check(card)


func is_full() -> bool:
	for dc in slots:
		if dc == null:
			return false
	return true


func is_empty() -> bool:
	for dc in slots:
		if dc != null:
			return false
	return true


func is_slot_free(index: int) -> bool:
	return index >= 0 and index < SLOT_COUNT and slots[index] == null


## TDeck.AddCard: first free slot, then resort. No-op when full, duplicate, or rule-breaking.
func add_card(card: Cards.CardDef, card_league: int = 1, card_level: int = 1) -> bool:
	if card == null or is_full() or not can_add_card(card):
		return false
	for i in SLOT_COUNT:
		if slots[i] == null:
			slots[i] = DeckCard.new(card, card_league, card_level)
			break
	sort()
	return true


func remove_card(card: Cards.CardDef) -> void:
	for i in SLOT_COUNT:
		if slots[i] != null and slots[i].card == card:
			slots[i] = null
			sort()
			return


## TCardInfo.Compare: nils last, spawners after non-spawners, then techlevel, spells after units,
## buildings after non-buildings, then filename, league, level.
static func compare(a: DeckCard, b: DeckCard) -> int:
	if a == null and b == null:
		return 0
	if a == null:
		return -(compare(b, a))
	if b == null:
		return 1 if a.card.is_spawner() else -1
	var l := a.card
	var r := b.card
	if l.is_spawner() != r.is_spawner():
		return 1 if l.is_spawner() else -1
	if l.tier != r.tier:
		return l.tier - r.tier
	if l.is_spell() != r.is_spell():
		return 1 if l.is_spell() else -1
	if l.is_building() != r.is_building():
		return 1 if l.is_building() else -1
	if l.unit_id != r.unit_id:
		return 1 if l.unit_id.nocasecmp_to(r.unit_id) > 0 else -1
	if a.league != b.league:
		return a.league - b.league
	return a.level - b.level


func sort() -> void:
	slots.sort_custom(func(a, b): return compare(a, b) < 0)


## Deck cards in slot order as unit_id strings for Commander.set_deck.
func card_ids() -> Array:
	var result: Array = []
	for dc in slots:
		if dc != null:
			result.append(dc.card.unit_id)
	return result


## Build a deck from unit_id strings (sandbox/tests). Asserts every card obeys the rules.
## Defaults are the original's DEFAULT_LEAGUE (4) / DEFAULT_LEVEL (5).
static func from_scripts(unit_ids: Array, card_league: int = 4, card_level: int = 5) -> Deck:
	var deck := Deck.new()
	for unit_id in unit_ids:
		var added := deck.add_card(Cards.by_script(unit_id), card_league, card_level)
		assert(added, "card %s does not fit the deck" % unit_id)
	return deck
