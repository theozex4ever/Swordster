class_name SwordSpec
extends RefCounted
## What a spirit sword is: sword type, rarity and element. Immutable
## description used to equip a sword slot; all per-instance state lives in
## `SwordState`.

var type_id: StringName = &"fang"
## Index into SwordDefs.RARITIES (0 Common, 1 Rare, 2 Mythic).
var rarity: int = 0
## Element identity (&"fire", &"ice", &"poison"): the condition its blows leave.
var element: StringName = &"fire"


static func make(type_value: StringName, rarity_value: int, element_value: StringName) -> SwordSpec:
	var spec: SwordSpec = SwordSpec.new()
	spec.type_id = type_value
	spec.rarity = rarity_value
	spec.element = element_value
	return spec


## The sword's full name ("Rare Ember Fang").
func display_name() -> String:
	return SwordDefs.full_name(self)
