# Swordster

Swordster is an arena survival game in which three equipped spirit swords fight
autonomously while the player moves and issues commands.

## Language

**Spirit sword**:
An autonomous weapon with a sword type, element and rarity, equipped in a sword
slot or available as a dropped sword.

**Sword type**:
A sword's combat identity, defining its automatic attack and ultimate. The four
types are Fang, Warden, Pike and Colossus.
_Avoid_: Sword class

**Sword slot**:
One of the three numbered positions in the player's equipped sword loadout.
_Avoid_: Inventory slot

**Converge**:
The player's coordinated command directing all three equipped spirit swords
to strike a chosen point.
_Avoid_: Ultimate

**Ultimate**:
A manually triggered special attack belonging to a sword type and activated
through its equipped slot.
_Avoid_: Converge

**Element**:
A sword's fire, ice or poison affinity, independent of its sword type and rarity.

**Condition**:
A lasting effect an element's blows leave on an enemy: burning (fire), poisoned (poison, up to
six stacks), chilled and frozen (ice, frozen after four stacks).
_Avoid_: Status effect, debuff

**Rarity**:
A sword's Common, Rare or Mythic quality, independent of its type and element.

**Armed enemy**:
An enemy carrying one spirit sword, with a sword type, element and rarity of its
own. When it dies the sword lies where it fell.
_Avoid_: Loot enemy

**Sword drop**:
A spirit sword lying in the arena, left by an armed enemy or put back by a swap,
until it is claimed or expires.
_Avoid_: Pickup item, loot

**Swap**:
The player's replacement of the spirit sword in a chosen sword slot by the nearest
sword drop within reach; the replaced sword becomes a sword drop and the slot
keeps its ultimate's recharge fraction.
_Avoid_: Equip

**Wave**:
A numbered group of enemies queued when it starts and arriving one by one, each
first telegraphed by a spawn marker. It is complete only when its queue, its
markers and every living enemy are gone; a break follows, then the next wave.
A wave's number sets how many enemies it holds, which types it may hold, how
tough they are and how good the swords they carry may be.
_Avoid_: Round, level

**Chain**:
The count of kills in unbroken succession, each within 2.6 seconds of the last.
It announces itself at 10, 25, 50 and 100 kills and ends when the window lapses;
the best chain of a run is kept for its end screen.
_Avoid_: Combo streak
