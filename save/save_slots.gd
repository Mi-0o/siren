extends RefCounted
## The nine save slots, kept in static vars and written to user://saves.cfg on every change.
## Preload this script rather than naming a class, so it works before the editor's class cache
## catches up.
##
## A slot holds everything needed to put the game back: the robot's position, charge and the
## damage state of each part, the scene, plus what the menus show (the real date and time of the
## save, the Europa time it was made at, and the area and station). The Europa clock itself is
## shared by every save (europa_clock.gd), so loading doesn't change it. An empty Dictionary is
## an empty slot.
##
## The active slot is the one the save stations write to. Loading a slot or saving into another
## one makes that slot the active one.

const PATH: String = "user://saves.cfg"
const SLOT_COUNT: int = 9
## Slots shown per page in the menus.
const PAGE_SIZE: int = 3
const PAGE_COUNT: int = 3

static var active_slot: int = 0
## A save the main menu is loading: the next scene's PauseMenu applies it once it's ready.
static var pending_load: Dictionary = {}
static var _slots: Array[Dictionary] = []
static var _loaded: bool = false


static func get_slot(index: int) -> Dictionary:
	_ensure_loaded()
	return _slots[index]


static func is_empty(index: int) -> bool:
	return get_slot(index).is_empty()


## The first empty slot, or -1 when all are taken.
static func first_empty() -> int:
	for i in SLOT_COUNT:
		if is_empty(i):
			return i
	return -1


## The slot saved most recently, or -1 with no saves.
static func latest() -> int:
	var best := -1
	var best_time := -1.0
	for i in SLOT_COUNT:
		var data := get_slot(i)
		if not data.is_empty() and float(data.get("unix", 0.0)) > best_time:
			best_time = float(data.get("unix", 0.0))
			best = i
	return best


static func get_active() -> int:
	_ensure_loaded()
	return active_slot


static func set_active(index: int) -> void:
	_ensure_loaded()
	active_slot = clampi(index, 0, SLOT_COUNT - 1)
	_write()


## Saves data into a slot and makes it the active one.
static func store(index: int, data: Dictionary) -> void:
	_ensure_loaded()
	_slots[index] = data.duplicate(true)
	active_slot = index
	_write()


static func delete(index: int) -> void:
	_ensure_loaded()
	_slots[index] = {}
	_write()


## Snapshot of the game right now, as made at a save station in area.
static func capture(player: Player, clock: Node, area: String, station: String) -> Dictionary:
	var now := Time.get_datetime_dict_from_system()
	var data := {
		"date": "%02d.%02d.%04d" % [now.day, now.month, now.year],
		"time": "%02d:%02d" % [now.hour, now.minute],
		"unix": Time.get_unix_time_from_system(),
		"area": area,
		"station": station,
		"scene": "",
		"x": 0.0,
		"y": 0.0,
		"charge": 0.0,
		"max_charge": 0.0,
		"core": 0,
		"legs": 0,
		"systems": 0,
		"europa_minutes": 0.0,
	}
	if player != null:
		data.scene = player.get_tree().current_scene.scene_file_path
		data.x = player.global_position.x
		data.y = player.global_position.y
		data.charge = player.charge
		data.max_charge = player.max_charge
		data.core = int(player.get_damage(Player.Part.CORE))
		data.legs = int(player.get_damage(Player.Part.LEGS))
		data.systems = int(player.get_damage(Player.Part.SYSTEMS))
	if clock != null and "europa_minutes" in clock:
		data.europa_minutes = float(clock.get("europa_minutes"))
	return data


## Puts the robot back as the slot recorded it. The clock is left alone: it is the same for
## every save.
static func apply(data: Dictionary, player: Player, _clock: Node) -> void:
	if player != null:
		# Damage first: healing a core fault revives the robot, so charge sticks afterwards.
		player.set_damage(Player.Part.CORE, int(data.get("core", 0)) as Player.Damage)
		player.set_damage(Player.Part.LEGS, int(data.get("legs", 0)) as Player.Damage)
		player.set_damage(Player.Part.SYSTEMS, int(data.get("systems", 0)) as Player.Damage)
		if player.has_method("_detach_wire"):
			player.call("_detach_wire")
		player.velocity = Vector2.ZERO
		player.global_position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		player.reset_physics_interpolation()
		if player.has_method("_set_charge"):
			player.call("_set_charge", float(data.get("charge", player.max_charge)))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_slots.clear()
	for i in SLOT_COUNT:
		_slots.append({})
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	active_slot = clampi(int(cfg.get_value("meta", "active_slot", 0)), 0, SLOT_COUNT - 1)
	for i in SLOT_COUNT:
		var value: Variant = cfg.get_value("slot_%d" % (i + 1), "data", {})
		if value is Dictionary:
			_slots[i] = value


static func _write() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "active_slot", active_slot)
	for i in SLOT_COUNT:
		if not _slots[i].is_empty():
			cfg.set_value("slot_%d" % (i + 1), "data", _slots[i])
	cfg.save(PATH)
