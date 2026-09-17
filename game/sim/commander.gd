class_name Commander
## One player's resources and deck (Scripts/Commander/CommanderTemplate.ets, CommanderMethods.dws).
## Gold spent is refunded as wood; wood spent accumulates as "spent wood" which buys automatic income
## upgrades (1500 + 250 per upgrade, max 10). Card charges recharge one at a time while below cap.

var team: int
var league: int = 4
var gold: float = SimConstants.STARTING_GOLD
var wood: float = SimConstants.STARTING_WOOD
var spent_wood: float = 0.0
var tier: int = SimConstants.STARTING_TIER
var income_upgrades: int = 0
var charm_count: int = 0            # reCharmCount: placed charms (Promise of Life), cap 3
var gadget_count: int = 0           # reGadgetCount: living gadgets (Blue turrets, factories, drones), cap 5
var slots: Array[DeckSlot] = []
var free_cards: bool = false        # sandbox: NOT_PAYED_RESOURCES includes gold/wood/charge
var properties: Dictionary = {}     # commander entity unit properties -> expiry (upHasEchoesOfTheFuture)
var loan_factor: float = 1.0        # TCommanderIncomeLoanComponent (Echoes of the Future): gold income x factor
var loan_until: int = -1            # while the timer runs; the first income after expiry starts the x0 payback window
var loan_duration: int = 0


class DeckSlot:
	var card: Cards.CardDef
	var league: int = 4              # RGameCard.tier: the card's own league, drives charge count + recharge
	var level: int = 5               # RGameCard.level: only shortens the recharge (CardTemplate.dws matrix)
	var times_played: int = 0        # reCardTimesPlayed: raised before each spawn (Atlas' level)
	var charges: int
	var charge_cap: int
	var charge_cooldown_ms: int
	var recharge_at: int = -1        # time the next charge arrives, -1 = not recharging
	var cost: float
	var gold_cost: float             # 0 for spawners
	var wood_cost: float             # 0 for non-spawners
	var spell_entity: SimEntity      # spells: the card's own entity (keeps charges between casts)

	func is_ready(now: int, commander: Commander) -> bool:
		if commander.free_cards:
			return true
		if card.epic:   # TWelaReadyCostComponent.CostsCap without charging: castable whenever the gold bar is full
			return commander.tier >= tier_cost() and commander.gold >= commander.gold_cap()
		if charges < 1 or commander.tier < tier_cost():
			return false
		return commander.gold >= gold_cost and commander.wood >= wood_cost

	func tier_cost() -> int:
		return 1 if card.is_spawner() else card.tier


func _init(p_team: int, p_league: int = 4) -> void:
	team = p_team
	league = p_league


## Sandbox/tests: every card at the commander's league, level 5 (DEFAULT_LEAGUE/DEFAULT_LEVEL behavior).
func set_deck(unit_ids: Array) -> void:
	slots.clear()
	for unit_id in unit_ids:
		_add_slot(Cards.by_script(unit_id), league, 5)


## RGameCard: a validated Deck where each slot carries its card's own league and level.
## In this snapshot they only change charge count and recharge time (CardTemplate.dws); card cost
## and unit stats are league-independent, so spawned units keep using the game league.
func set_deck_from(deck: Deck) -> void:
	slots.clear()
	for dc in deck.slots:
		if dc != null:
			_add_slot(dc.card, dc.league, dc.level)


func _add_slot(card: Cards.CardDef, card_league: int, card_level: int) -> void:
	var s := DeckSlot.new()
	s.card = card
	s.league = card_league
	s.level = card_level
	s.cost = Cards.base_cost(card.tier, card.legendary, card.is_spell(), card.is_spawner()) + card.cost_adjust
	s.gold_cost = 0.0 if card.is_spawner() else s.cost
	s.wood_cost = s.cost if card.is_spawner() else 0.0
	s.charge_cap = Cards.charge_count(card.tier, card_league, card.legendary)
	s.charges = s.charge_cap
	s.charge_cooldown_ms = int(Cards.charge_cooldown(card.tier, card_league, card_level, card.legendary, card.is_spawner()) * card.charge_cooldown_mult)
	slots.append(s)


func gold_cap() -> float:
	return SimConstants.GOLD_CAP + SimConstants.GOLD_CAP_PER_TIER * (tier - 1)


func income() -> float:
	return SimConstants.STARTING_INCOME + SimConstants.INCOME_PER_UPGRADE * income_upgrades


func income_upgrade_cost() -> float:
	return SimConstants.INCOME_UPGRADE_COST + SimConstants.INCOME_UPGRADE_COST_STEP * income_upgrades


## TCommanderIncomeDefaultComponent + TCommanderIncomeOverflowComponent: gold above cap becomes wood.
func pay_income(now: int = 0) -> void:
	var amount := income()
	if loan_until >= 0:   # TCommanderIncomeLoanComponent.AdjustIncome
		if now < loan_until or loan_factor > 0.0:
			amount *= loan_factor
			if now >= loan_until:   # first income after the boost: payback window of duration x factor / 2 at x0
				loan_until = now + int(loan_duration * loan_factor / 2.0)
				loan_factor = 0.0
		else:
			loan_until = -1
			loan_factor = 1.0
	var room := maxf(0.0, gold_cap() - gold)
	var to_gold := minf(amount, room)
	gold += to_gold
	wood += amount - to_gold


## TWelaEffectPayCostComponent with ConvertResource(reGold, reWood) and (reWood, reSpentWood).
func pay(slot: DeckSlot, now: int) -> void:
	if free_cards:
		return
	if slot.card.epic:   # PrepareEpicSpell: ConsumesAll of the gold (refunded as wood), no charge to spend
		wood += gold
		gold = 0.0
		return
	slot.charges -= 1
	if slot.recharge_at < 0:
		slot.recharge_at = now + slot.charge_cooldown_ms
	gold -= slot.gold_cost
	wood += slot.gold_cost
	wood -= slot.wood_cost
	spent_wood += slot.wood_cost
	_auto_income_upgrade()


## GOLD_UPGRADE_GROUP: upgrades whenever spent wood covers the (rising) cost, up to the cap.
func _auto_income_upgrade() -> void:
	while income_upgrades < SimConstants.INCOME_UPGRADE_CAP and spent_wood >= income_upgrade_cost():
		spent_wood -= income_upgrade_cost()
		income_upgrades += 1


## Charge recharge (Globals.dws AddCharging): one charge per cooldown while below the cap.
func update_charges(now: int) -> void:
	for s in slots:
		if s.recharge_at >= 0 and now >= s.recharge_at:
			s.charges = mini(s.charge_cap, s.charges + 1)
			s.recharge_at = -1 if s.charges >= s.charge_cap else s.recharge_at + s.charge_cooldown_ms


func has_property(prop: String, now: int) -> bool:
	return properties.has(prop) and (properties[prop] < 0 or now < properties[prop])


func start_income_loan(factor: float, duration: int, now: int) -> void:
	loan_factor = factor
	loan_duration = duration
	loan_until = now + duration


func raise_tier(new_tier: int) -> void:
	tier = clampi(maxi(tier, new_tier), 1, SimConstants.MAX_TIER)
