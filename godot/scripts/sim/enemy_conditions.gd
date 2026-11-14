class_name EnemyConditions
extends RefCounted
## The elemental conditions on one enemy (prototype `Enemy` condition fields):
## burn, stacking poison, chill and freeze, with the timers and the damage-over-time
## accumulator. It owns the rules for applying and ticking them; the run owns the
## consequences (damage dealt to the enemy, deaths, fire spread, cues), so a death
## can only ever be resolved by `GameRun.kill`. Visuals read `view()`, never this.

## Seconds left of each condition; zero or less means it is not on the enemy.
var burn: float = 0.0
var burn_dps: float = 0.0
var poison: float = 0.0
var poison_dps: float = 0.0
var poison_stacks: int = 0
var chill: float = 0.0
var chill_stacks: int = 0
var frozen: float = 0.0
## Damage over time not yet dealt, and seconds until it may next be dealt.
var dot: float = 0.0
var dot_time: float = ConditionDefs.DOT_PERIOD
## Scales how long a freeze lasts on this kind of enemy (brutes resist).
var freeze_factor: float = 1.0


func is_burning() -> bool:
	return burn > 0.0


func is_frozen() -> bool:
	return frozen > 0.0


func is_chilled() -> bool:
	return chill > 0.0


## Applies one dose of an element (prototype `Game.afflict`); `power` is the source
## sword's base damage. Fire refreshes the burn and keeps the stronger dps while it
## still burns. Poison adds stacks up to the cap, refreshes the timer and keeps the
## stronger per-stack dps while it still lasts. Ice refreshes the chill; stacks only
## grow while the enemy is not frozen, and the stack that reaches the threshold
## freezes it. Returns true when this dose froze the enemy.
func apply(element: StringName, power: float, stacks: int) -> bool:
	match element:
		ConditionDefs.FIRE:
			var dps: float = ConditionDefs.burn_dps(power, stacks)
			burn_dps = maxf(burn_dps, dps) if burn > 0.0 else dps
			burn = ConditionDefs.BURN_TIME
		ConditionDefs.POISON:
			var dps: float = ConditionDefs.poison_dps(power)
			poison_dps = maxf(poison_dps, dps) if poison > 0.0 else dps
			poison_stacks = mini(ConditionDefs.POISON_MAX, poison_stacks + stacks)
			poison = ConditionDefs.POISON_TIME
		ConditionDefs.ICE:
			chill = ConditionDefs.CHILL_TIME
			if frozen > 0.0:
				return false
			chill_stacks += stacks
			if chill_stacks >= ConditionDefs.FREEZE_STACKS:
				chill_stacks = 0
				frozen = ConditionDefs.FREEZE_TIME * freeze_factor
				return true
	return false


## Ignition from a burning enemy's death (prototype `Game.kill`): it never weakens
## or shortens a burn that is already stronger or longer.
func ignite_from_spread(source_burn_dps: float) -> void:
	burn_dps = maxf(burn_dps if burn > 0.0 else 0.0, source_burn_dps * ConditionDefs.SPREAD_DPS_FACTOR)
	burn = maxf(burn, ConditionDefs.BURN_TIME * ConditionDefs.SPREAD_TIME_FACTOR)


## One gameplay step (prototype `Game.update_conditions`, per enemy): timers run
## down, stacks fall away with their condition, and burn and poison feed the
## damage-over-time accumulator. Returns the whole points of damage that land on
## this step (0 on most steps). A condition that runs out on this step still
## contributes its last step of damage.
func tick(dt: float) -> int:
	frozen = maxf(0.0, frozen - dt)
	chill = maxf(0.0, chill - dt)
	if chill <= 0.0:
		chill_stacks = 0
	var dps: float = 0.0
	if burn > 0.0:
		burn -= dt
		dps += burn_dps
	if poison > 0.0:
		poison -= dt
		dps += poison_dps * float(poison_stacks)
		if poison <= 0.0:
			poison_stacks = 0
	if dps <= 0.0:
		dot = 0.0
		return 0
	dot += dps * dt
	dot_time -= dt
	if dot_time > 0.0:
		return 0
	dot_time = ConditionDefs.DOT_PERIOD
	var whole: int = int(dot)
	if whole < 1:
		return 0
	dot -= float(whole)
	return whole


## The element the last damage-over-time number belongs to (prototype colours it
## fire when burning at least as hard as the poison, else poison).
func dominant_element() -> StringName:
	var fire: bool = burn > 0.0 and (poison <= 0.0 or burn_dps >= poison_dps * float(poison_stacks))
	return ConditionDefs.FIRE if fire else ConditionDefs.POISON


## A read-only copy of what presentation may show.
func view() -> ConditionView:
	return ConditionView.of(self)
