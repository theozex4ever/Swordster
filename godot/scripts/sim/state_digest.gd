class_name StateDigest
extends RefCounted
## A plain-values copy of everything that decides how a run goes on, built by reflection (issue #41).
## `GameRun.state_digest()` is the one entry point: it serializes every script variable of the run, and of every
## object they reach (swords, enemies with their conditions, projectiles, fields, pickups, the wave director with its
## queue and markers, motes), except the members `GameRun.STATE_DIGEST_EXCLUDED` names. Nothing is listed here per
## member, so a member added to any of those classes is in the digest the day it is declared: the combined fight's
## frame-rate comparison (render_rate_checks.gd) then sees it without anyone remembering to extend a digest. A member
## that must stay out of it (a static input, a queue the presentation drains) goes into the exclusion list with its
## reason, and a check pins that list, so leaving something out is always a reviewed decision.
##
## The result is plain data (Dictionary / Array / String / int / bool / null) that survives a JSON round trip:
##  - numbers are fixed-point text ("%.6f"), so two runs match only if they are equal to a millionth, and a
##    different tick, delta or draw cannot hide in rounding;
##  - an object appears in full the first time the walk reaches it and as `{"ref": n}` afterwards (n counts the
##    objects in the order they were first reached), so which enemy a sword targets is part of the digest and
##    object cycles cannot loop;
##  - a random generator is its seed and its `state` (as text: 64-bit values do not survive JSON numbers), so a
##    gameplay draw made anywhere (a presenter drawing from the gameplay stream, say) shows;
##  - dictionaries keep their keys as text, objects used as keys by their serial (or their own serialization).

var _excluded: Dictionary
var _seen: Dictionary[int, int] = {}


## The digest of `root`'s script variables, leaving out the names in `excluded` (a Dictionary keyed by name).
static func of(root: Object, excluded: Dictionary) -> Dictionary:
	var digest: StateDigest = StateDigest.new()
	digest._excluded = excluded
	digest._seen[root.get_instance_id()] = 0
	return digest._members(root, true)


## The names of the script variables the digest of `root` serializes: every one except the excluded ones.
static func member_names(root: Object, excluded: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for property: Dictionary in root.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name: String = String(property["name"])
		if not excluded.has(name):
			names.append(name)
	return names


## A 64-bit fingerprint of the same state, cheap enough to take on EVERY tick (the readable digest costs about 8 ms,
## this a fraction of it): the same walk over the same members and objects, folded into one integer instead of built
## into text. Floats are folded bit for bit, so two runs agree only if they are identical. `GameRun.state_fingerprint()`
## is the entry point; `CombinedFight` chains it tick after tick, so a difference that appears on one tick and is gone
## by the next checkpoint still changes the chain for good.
static func fingerprint(root: Object, excluded: Dictionary) -> int:
	var walker: StateDigest = StateDigest.new()
	walker._excluded = excluded
	walker._seen[root.get_instance_id()] = 0
	return walker._fold_members(root, true)


## Per script: the names of its script variables (reflection is the slow part, so it is done once per class).
static var _names_of: Dictionary[Script, PackedStringArray] = {}

const _PRIME: int = 1099511628211


static func _names(object: Object) -> PackedStringArray:
	var script: Script = object.get_script() as Script
	if script != null and _names_of.has(script):
		return _names_of[script]
	var names: PackedStringArray = PackedStringArray()
	for property: Dictionary in object.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			names.append(String(property["name"]))
	if script != null:
		_names_of[script] = names
	return names


## Folds `value` into `accumulator` (FNV-style, wrapping); also how a chain of per-tick fingerprints is built.
static func mix(accumulator: int, value: int) -> int:
	return (accumulator ^ value) * _PRIME


func _fold_members(object: Object, is_root: bool) -> int:
	var accumulator: int = -3750763034362895579
	for name: String in _names(object):
		if is_root and _excluded.has(name):
			continue
		accumulator = mix(accumulator, _fold(object.get(name)))
	return accumulator


func _fold(value: Variant) -> int:
	match typeof(value):
		TYPE_NIL:
			return 0
		TYPE_BOOL, TYPE_INT:
			return int(value) + 7
		TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_COLOR:
			return hash(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).hash()
		TYPE_ARRAY:
			var accumulator: int = (value as Array).size()
			for item: Variant in value:
				accumulator = mix(accumulator, _fold(item))
			return accumulator
		TYPE_DICTIONARY:
			var accumulator: int = (value as Dictionary).size()
			for key: Variant in value:
				accumulator = mix(accumulator, _fold_key(key))
				accumulator = mix(accumulator, _fold(value[key]))
			return accumulator
		TYPE_OBJECT:
			return _fold_object(value as Object)
	return var_to_str(value).hash()


func _fold_object(object: Object) -> int:
	if object == null:
		return 0
	var id: int = object.get_instance_id()
	if _seen.has(id):
		return mix(1, _seen[id])
	_seen[id] = _seen.size()
	if object is RandomNumberGenerator:
		var generator: RandomNumberGenerator = object
		return mix(mix(2, generator.seed), generator.state)
	return _fold_members(object, false)


func _fold_key(key: Variant) -> int:
	if typeof(key) == TYPE_OBJECT:
		var object: Object = key as Object
		if object != null and "serial" in object:
			return mix(3, int(object.get("serial")))
		return _fold_object(object)
	return _fold(key)



func _members(object: Object, is_root: bool) -> Dictionary:
	var members: Dictionary = {}
	for property: Dictionary in object.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name: String = String(property["name"])
		if is_root and _excluded.has(name):
			continue
		members[name] = _value(object.get(name))
	return members


func _value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT:
			return value
		TYPE_FLOAT:
			return _number(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value)
		TYPE_VECTOR2:
			return "%s,%s" % [_number((value as Vector2).x), _number((value as Vector2).y)]
		TYPE_VECTOR2I:
			return "%d,%d" % [(value as Vector2i).x, (value as Vector2i).y]
		TYPE_RECT2:
			var rect: Rect2 = value
			return "%s,%s,%s,%s" % [_number(rect.position.x), _number(rect.position.y), _number(rect.size.x), _number(rect.size.y)]
		TYPE_COLOR:
			return (value as Color).to_html()
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_value(item))
			return items
		TYPE_DICTIONARY:
			var entries: Dictionary = {}
			for key: Variant in value:
				entries[_key(key)] = _value(value[key])
			return entries
		TYPE_OBJECT:
			return _object(value as Object)
	return var_to_str(value)


func _object(object: Object) -> Variant:
	if object == null:
		return null
	var id: int = object.get_instance_id()
	if _seen.has(id):
		return {"ref": _seen[id]}
	_seen[id] = _seen.size()
	if object is RandomNumberGenerator:
		var generator: RandomNumberGenerator = object
		return {"seed": str(generator.seed), "state": str(generator.state)}
	return _members(object, false)


func _key(key: Variant) -> String:
	if typeof(key) == TYPE_OBJECT:
		var object: Object = key as Object
		# An enemy used as a key (the targets a sweep has hit) is named by its serial: it is serialized in full in the list it lives in.
		if object != null and "serial" in object:
			return "serial:%d" % int(object.get("serial"))
		return JSON.stringify(_object(object))
	return str(_value(key))


## Fixed-point text. NaN and infinity print as such, which also differs from every ordinary value.
static func _number(value: float) -> String:
	return "%.6f" % value
