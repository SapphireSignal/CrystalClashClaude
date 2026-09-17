class_name SimConstants
## Constants and enums of the original simulation (see docs/original-architecture.md).

const TICK_MS: int = 32              # original server heartbeat TARGET_FRAMETIME (Game.Server.pas:67)
const GAME_TICK_MS: int = 1000       # GAME_TICK_DURATION (Constants.pas:48)
const GAME_WARMING_MS: int = 10000   # GAME_WARMING_DURATION (Constants.pas:49)
const THINK_INTERVAL_MS: int = 250   # THINK_TIME_INTERVAL
const SUMMONING_SICKNESS_MS: int = 1000
const DEFAULT_SPEED: float = 4.0 / 1000.0   # world units per ms (UnitTemplate.dws:6)
const DEFAULT_ATTENTION_RANGE: float = 22.0
const OVERHEAL_LIMIT_FACTOR: float = 2.0

const GROUP_APPROACH: int = 0
const GROUP_MAINWEAPON: int = 1

const MAP_BOUNDS: float = 150.0
const BUILDGRID_SIZE := Vector2i(8, 3)
const PATHFINDING_TILE_SIZE: float = 0.8

# Economy (BaseConflict.Game.pas:222-236)
const STARTING_GOLD: float = 300.0
const GOLD_CAP: float = 400.0
const GOLD_CAP_PER_TIER: float = 100.0
const STARTING_WOOD: float = 1600.0
const STARTING_TIER: int = 1
const MAX_TIER: int = 3
const STARTING_INCOME: float = 10.0
const INCOME_PER_UPGRADE: float = 2.0
const INCOME_UPGRADE_CAP: int = 10
const INCOME_UPGRADE_COST: float = 1500.0
const INCOME_UPGRADE_COST_STEP: float = 250.0
const WAVE_EVERY_N_TICKS: int = 2
const CHARM_COUNT_CAP: int = 3       # reCharmCount cap per commander
const GADGET_COUNT_CAP: int = 5      # reGadgetCount cap per commander

# Game events by league index 0..4 (Scripts/Scenarios/Game.dws:36-39), in seconds
const TECH_LEVEL_2_SECONDS := [180, 180, 180, 240, 240]
const TECH_LEVEL_3_SECONDS := [360, 360, 360, 480, 480]
const SHOWDOWN_SECONDS := [360, 540, 540, 720, 720]

enum ArmorType { UNARMORED, LIGHT, MEDIUM, HEAVY, FORTIFIED }

enum DamageType {
	SIEGE = 1 << 0, TRUE = 1 << 1, IGNORE_ARMOR = 1 << 2, RANGED = 1 << 3, MELEE = 1 << 4,
	SPLASH = 1 << 5, SPELL = 1 << 6, ABILITY = 1 << 7, REFLECTED = 1 << 8, IRREDIRECTABLE = 1 << 9,
	REDIRECTED = 1 << 10, ANTI_AIR = 1 << 11, HOT = 1 << 12, DOT = 1 << 13, FLAT_HEAL = 1 << 14,
	OVERHEAL = 1 << 15, CHARGE = 1 << 16,
}

const ARMOR_NAMES := {
	"atUnarmored": ArmorType.UNARMORED, "atLight": ArmorType.LIGHT, "atMedium": ArmorType.MEDIUM,
	"atHeavy": ArmorType.HEAVY, "atFortified": ArmorType.FORTIFIED,
}

const DAMAGE_NAMES := {
	"dtSiege": DamageType.SIEGE, "dtTrue": DamageType.TRUE, "dtIgnoreArmor": DamageType.IGNORE_ARMOR,
	"dtRanged": DamageType.RANGED, "dtMelee": DamageType.MELEE, "dtSplash": DamageType.SPLASH,
	"dtSpell": DamageType.SPELL, "dtAbility": DamageType.ABILITY, "dtReflected": DamageType.REFLECTED,
	"dtIrredirectable": DamageType.IRREDIRECTABLE, "dtRedirected": DamageType.REDIRECTED,
	"dtAntiAir": DamageType.ANTI_AIR, "dtHoT": DamageType.HOT, "dtDoT": DamageType.DOT,
	"dtFlatHeal": DamageType.FLAT_HEAL, "dtOverheal": DamageType.OVERHEAL, "dtCharge": DamageType.CHARGE,
}


static func damage_mask(names: Array) -> int:
	var mask := 0
	for n in names:
		mask |= DAMAGE_NAMES.get(n, 0)
	return mask


## TArmorComponent.OnDamage (EntityComponents.Shared.pas:2043-2078), reproduced exactly.
static func apply_armor(amount: float, armor: ArmorType, damage_type: int) -> float:
	if damage_type & DamageType.IGNORE_ARMOR or amount <= 1.0:
		return amount
	var factor := 1.0
	var offset := 0.0
	match armor:
		ArmorType.LIGHT:
			factor = 0.85
		ArmorType.MEDIUM:
			factor = 0.7 if damage_type & DamageType.RANGED else 0.8
		ArmorType.HEAVY:
			factor = 0.7
			offset = 5.0
		ArmorType.FORTIFIED:
			factor = 4.0 if damage_type & DamageType.SIEGE else 1.0
	return maxf(1.0, factor * amount - offset)
