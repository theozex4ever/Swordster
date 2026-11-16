class_name PickupState
extends RefCounted
## A spirit sword lying in the arena (game/main.py `Pickup`): dropped by an armed enemy that died, or the
## sword a swap put back. It holds an immutable `SwordSpec` (its type, element and rarity never change)
## and counts down its own life on gameplay time; at zero it is gone.

var spec: SwordSpec
var position: Vector2 = Vector2.ZERO
## Gameplay seconds since it landed (prototype `t`; the visual bobs by it). The prototype starts it at a random
## offset to desynchronise the bobbing; that is cosmetic, so here it starts at zero and a visual that wants
## variety derives it from `serial`.
var age: float = 0.0
var life: float = LootDefs.PICKUP_LIFE
## Unique within the run, for presentation (visual identity and phase); never read by the rules.
var serial: int = 0


static func make(spec_value: SwordSpec, at: Vector2, serial_value: int) -> PickupState:
	var pickup: PickupState = PickupState.new()
	pickup.spec = spec_value
	pickup.position = at
	pickup.serial = serial_value
	return pickup


## True while a pickup that is close to expiring is in the hidden half of its blink.
func blink_hidden() -> bool:
	return life < LootDefs.PICKUP_BLINK_BELOW and int(life * LootDefs.PICKUP_BLINK_RATE) % 2 == 0
