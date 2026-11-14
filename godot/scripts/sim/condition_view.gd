class_name ConditionView
extends RefCounted
## What a visual may know about an enemy's conditions: plain values, nothing it
## could write back. Gameplay owns every timer; a cue's look follows these and
## never drives them (ADR 0003).

var burning: bool = false
## Poison stacks (0 when not poisoned).
var poison_stacks: int = 0
## Chill stacks toward a freeze (0..3 while chilled and not frozen).
var chill_stacks: int = 0
var chilled: bool = false
var frozen: bool = false


static func of(conditions: EnemyConditions) -> ConditionView:
	var view: ConditionView = ConditionView.new()
	view.burning = conditions.is_burning()
	view.poison_stacks = conditions.poison_stacks if conditions.poison > 0.0 else 0
	view.chill_stacks = conditions.chill_stacks
	view.chilled = conditions.is_chilled()
	view.frozen = conditions.is_frozen()
	return view
