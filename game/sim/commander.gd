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
var slots: Array[DeckSlot] = []
var free_cards: bool = false        # sandbox: NOT_PAYED_RESOURCES includes gold/wood/charge


class DeckSlot:
	var card: Cards.CardDef
	var level: int = 5
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
		if charges < 1 or commander.tier < tier_cost():
			return false
		return commander.gold >= gold_cost and commander.wood >= wood_cost

	func tier_cost() -> int:
		return 1 if card.is_spawner() else card.tier


func _init(p_team: int, p_league: int = 4) -> void:
	team = p_team
	league = p_league


func set_deck(unit_ids: Array) -> void:
	slots.clear()
	for unit_id in unit_ids:
		var card := Cards.by_script(unit_id)
		var s := DeckSlot.new()
		s.card = card
		s.cost = Cards.base_cost(card.tier, card.legendary, card.is_spell(), card.is_spawner()) + card.cost_adjust
		s.gold_cost = 0.0 if card.is_spawner() else s.cost
		s.wood_cost = s.cost if card.is_spawner() else 0.0
		s.charge_cap = Cards.charge_count(card.tier, league, card.legendary)
		s.charges = s.charge_cap
		s.charge_cooldown_ms = Cards.charge_cooldown(card.tier, league, s.level, card.legendary, card.is_spawner())
		slots.append(s)


func gold_cap() -> float:
	return SimConstants.GOLD_CAP + SimConstants.GOLD_CAP_PER_TIER * (tier - 1)


func income() -> float:
	return SimConstants.STARTING_INCOME + SimConstants.INCOME_PER_UPGRADE * income_upgrades


func income_upgrade_cost() -> float:
	return SimConstants.INCOME_UPGRADE_COST + SimConstants.INCOME_UPGRADE_COST_STEP * income_upgrades


## TCommanderIncomeDefaultComponent + TCommanderIncomeOverflowComponent: gold above cap becomes wood.
func pay_income() -> void:
	var amount := income()
	var room := maxf(0.0, gold_cap() - gold)
	var to_gold := minf(amount, room)
	gold += to_gold
	wood += amount - to_gold


## TWelaEffectPayCostComponent with ConvertResource(reGold, reWood) and (reWood, reSpentWood).
func pay(slot: DeckSlot, now: int) -> void:
	if free_cards:
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


func raise_tier(new_tier: int) -> void:
	tier = clampi(maxi(tier, new_tier), 1, SimConstants.MAX_TIER)
