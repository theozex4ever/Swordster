class_name PickupCard
extends RefCounted
## The words and numbers of a dropped sword's card (game/main.py `Game.draw_pickup_card`): its full name, what its type
## is for, its damage, attack speed and range with the rarity applied, its element, its ultimate and how long that
## takes to recharge, and the keys that claim it. Plain text from the immutable definitions, so the card can be checked
## against the prototype's own for every type, rarity and element, and so a drawn card can never disagree with the
## sword it describes. `compare_to` adds what the prototype leaves to the eye: how the pickup differs from the sword in a slot.

const HINT: String = "press 1 / 2 / 3 to swap"


## The prototype's six lines, in drawing order.
static func lines(spec: SwordSpec) -> Array[String]:
	var found: Array[String] = []
	found.append(title(spec))
	found.append(SwordDefs.blurb(spec.type_id))
	found.append(stats(spec))
	found.append(SwordDefs.ELEMENT_TAGS.get(spec.element, String(spec.element).to_upper()))
	found.append(ultimate_line(spec))
	found.append(HINT)
	return found


static func title(spec: SwordSpec) -> String:
	return SwordDefs.full_name(spec)


static func stats(spec: SwordSpec) -> String:
	return "DMG %.0f   SPD %.1f/s   RNG %.0f" % [SwordDefs.damage_of(spec), 1.0 / SwordDefs.cooldown_of(spec), SwordDefs.range_of(spec)]


static func ultimate_line(spec: SwordSpec) -> String:
	return "ULT  %s%s   %.0fs" % [SwordDefs.ultimate_name(spec.type_id), "  (skill shot)" if SwordDefs.ultimate_is_shot(spec.type_id) else "", SwordDefs.ultimate_recharge_of(spec)]


## How the pickup compares to the sword now in a slot, for the three numbers the card shows: "1  Common Venom Fang   DMG +2   SPD -0.3/s   RNG +10".
static func compare_to(spec: SwordSpec, slot: int, equipped: SwordSpec) -> String:
	return "%d  %s   DMG %+.0f   SPD %+.1f/s   RNG %+.0f" % [
		slot + 1,
		SwordDefs.full_name(equipped),
		SwordDefs.damage_of(spec) - SwordDefs.damage_of(equipped),
		1.0 / SwordDefs.cooldown_of(spec) - 1.0 / SwordDefs.cooldown_of(equipped),
		SwordDefs.range_of(spec) - SwordDefs.range_of(equipped),
	]
