class_name SwordSpec
extends RefCounted
## What a spirit sword is: sword type, rarity and element. Immutable
## description used to equip a sword slot; all per-instance state lives in
## `SwordState`.

var type_id: StringName = &"fang"
## Index into SwordDefs.RARITIES (0 Common, 1 Rare, 2 Mythic).
var rarity: int = 0
## Element identity (&"fire", &"ice", &"poison"). In this slice it only
## colours the sword: conditions are not ported yet.
var element: StringName = &"fire"


static func make(type_value: StringName, rarity_value: int, element_value: StringName) -> SwordSpec:
	var spec: SwordSpec = SwordSpec.new()
	spec.type_id = type_value
	spec.rarity = rarity_value
	spec.element = element_value
	return spec
