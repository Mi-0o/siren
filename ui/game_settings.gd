class_name GameSettings
extends RefCounted
## Player settings, kept in static vars so any script can read them (GameSettings.particles,
## GameSettings.screen_shake...). Saved to user://settings.cfg on every change and loaded once
## at startup by load_and_apply().
##
## Working now: display mode, V-Sync, brightness and the colorblind filter (via the screen
## overlay the pause menu owns), key bindings, screen shake (ScreenFx.shake does nothing while
## it's off) and particles (see particle_scale). The volumes are only stored until there's sound.

enum DisplayMode { FULLSCREEN, WINDOWED, BORDERLESS }
enum Particles { DEFAULT, REDUCED, NONE }
## Screen filter for colour vision deficiencies. Each one shifts the colours that type of eye
## can't tell apart into ones it can (daltonization).
enum Colorblind { OFF, PROTANOPIA, DEUTERANOPIA, TRITANOPIA }

const PATH: String = "user://settings.cfg"
## Gameplay actions the player can rebind, with the names shown in the menu.
const REMAPPABLE: Array[StringName] = [
	&"move_left", &"move_right", &"look_up", &"look_down", &"jump", &"run", &"dash", &"wire",
	&"attack", &"shoot", &"burst", &"interact",
]
const REMAP_NAMES: Array[String] = [
	"MOVE LEFT", "MOVE RIGHT", "LOOK UP", "LOOK DOWN", "JUMP", "RUN", "DASH", "WIRE", "MELEE",
	"HANDGUN", "ANTIMATTER CANNON", "INTERACT",
]
const COLORBLIND_NAMES: Array[String] = ["OFF", "PROTANOPIA", "DEUTERANOPIA", "TRITANOPIA"]
const VOLUME_IDS: Array[String] = ["general", "music", "game", "ui"]

static var display_mode: DisplayMode = DisplayMode.WINDOWED
static var vsync: bool = true
## 0 to 1; 0.5 leaves the picture untouched.
static var brightness: float = 0.5
static var particles: Particles = Particles.DEFAULT
static var screen_shake: bool = true
## 0 to 1 per bus id in VOLUME_IDS. Nothing plays sound yet.
static var volumes: Dictionary = {"general": 1.0, "music": 1.0, "game": 1.0, "ui": 1.0}
static var dev_mode: bool = false
static var colorblind: Colorblind = Colorblind.OFF
## 0 to 1: how much of the colorblind correction is applied.
static var colorblind_strength: float = 1.0

## Keyboard events each remappable action had in the project, for "reset to default".
static var _default_keys: Dictionary = {}
static var _loaded: bool = false
## Whether the saved file chose a display mode; until then the project's window setup is kept.
static var _display_chosen: bool = false


## Reads the saved settings and applies them. Safe to call more than once.
static func load_and_apply() -> void:
	if _loaded:
		return
	_loaded = true
	# The save stations' interact key isn't in the project's Input Map: make sure it exists
	# before its default is recorded.
	_ensure_action(&"interact", KEY_A, JOY_BUTTON_Y)
	for action in REMAPPABLE:
		if InputMap.has_action(action):
			_default_keys[action] = _key_code(action)
	display_mode = _current_display_mode()
	vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED

	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	if cfg.has_section_key("graphics", "display_mode"):
		display_mode = clampi(cfg.get_value("graphics", "display_mode"), 0, 2) as DisplayMode
		_display_chosen = true
	vsync = cfg.get_value("graphics", "vsync", vsync)
	brightness = clampf(cfg.get_value("graphics", "brightness", brightness), 0.0, 1.0)
	particles = clampi(cfg.get_value("graphics", "particles", particles), 0, 2) as Particles
	screen_shake = cfg.get_value("graphics", "screen_shake", screen_shake)
	for id in VOLUME_IDS:
		volumes[id] = clampf(cfg.get_value("audio", id, volumes[id]), 0.0, 1.0)
	dev_mode = cfg.get_value("general", "dev_mode", dev_mode)
	var filter: int = cfg.get_value("accessibility", "colorblind", colorblind)
	colorblind = clampi(filter, 0, 3) as Colorblind
	colorblind_strength = clampf(
		cfg.get_value("accessibility", "colorblind_strength", colorblind_strength), 0.0, 1.0
	)
	for action in REMAPPABLE:
		var code: int = cfg.get_value("controls", String(action), -1)
		if code > 0:
			_set_key(action, code)
	apply_display()


static func save() -> void:
	var cfg := ConfigFile.new()
	if _display_chosen:
		cfg.set_value("graphics", "display_mode", display_mode)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "brightness", brightness)
	cfg.set_value("graphics", "particles", particles)
	cfg.set_value("graphics", "screen_shake", screen_shake)
	for id in VOLUME_IDS:
		cfg.set_value("audio", id, volumes[id])
	cfg.set_value("general", "dev_mode", dev_mode)
	cfg.set_value("accessibility", "colorblind", colorblind)
	cfg.set_value("accessibility", "colorblind_strength", colorblind_strength)
	for action in REMAPPABLE:
		cfg.set_value("controls", String(action), _key_code(action))
	cfg.save(PATH)


## Pushes display mode (only once the player has picked one) and V-Sync to the window.
static func apply_display() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	if not _display_chosen:
		return
	match display_mode:
		DisplayMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DisplayMode.BORDERLESS:
			# Godot's plain fullscreen is a borderless window covering the screen.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)


static func set_display_mode(mode: DisplayMode) -> void:
	display_mode = mode
	_display_chosen = true
	apply_display()
	save()


static func set_vsync(on: bool) -> void:
	vsync = on
	apply_display()
	save()


## Exponent for the brightness overlay: 1 is untouched, below 1 brightens, above darkens.
## How many particles an effect gets, as a share of its full amount, for the particles setting.
## Essential particles carry gameplay information (the burst, the charge bar's drain sparks,
## impact sparks): DEFAULT and REDUCED keep them all, NONE halves them. Everything else is
## decoration: REDUCED keeps 30%, NONE drops it.
static func particle_scale(essential: bool) -> float:
	match particles:
		Particles.REDUCED:
			return 1.0 if essential else 0.3
		Particles.NONE:
			return 0.5 if essential else 0.0
	return 1.0


## count scaled by particle_scale, rounded at random so small bursts keep the right average
## (one-at-a-time emitters at 30% still emit about every third time).
static func particle_count(count: int, essential: bool) -> int:
	var scaled := float(count) * particle_scale(essential)
	var whole := floori(scaled)
	return whole + (1 if randf() < scaled - float(whole) else 0)


## count scaled by particle_scale and rounded, for effects that draw a fixed set of particles
## every frame (they need the same number each frame, not a random one).
static func particle_slots(count: int, essential: bool) -> int:
	return int(round(float(count) * particle_scale(essential)))


## Whether to make one particle, for effects that spawn them one by one.
static func particle_keep(essential: bool) -> bool:
	return randf() < particle_scale(essential)


static func brightness_gamma() -> float:
	return pow(2.0, (0.5 - brightness) * 2.0)


# --- Controls --------------------------------------------------------------------------------


## The physical keycode of the action's first keyboard binding, or 0 when it has none.
static func _key_code(action: StringName) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	return 0


## Name of the action's key as the menu shows it, e.g. "LEFT", "SHIFT", "Z".
static func key_name(action: StringName) -> String:
	return code_name(_key_code(action))


## Name of a physical key as the menu shows it, or "---" for none.
static func code_name(code: int) -> String:
	if code == 0:
		return "---"
	var shown := DisplayServer.keyboard_get_keycode_from_physical(code as Key)
	if shown == KEY_NONE:
		shown = code as Key
	return OS.get_keycode_string(shown).to_upper()


## The other remappable action already on this key, or &"" if it's free.
static func action_on_key(code: int, except: StringName) -> StringName:
	for other in REMAPPABLE:
		if other != except and _key_code(other) == code:
			return other
	return &""


## Replaces the action's keyboard binding. An action already on that key gets this one's old
## key instead, so nothing ends up doubled or lost. The menu asks the player first.
static func rebind(action: StringName, code: int) -> void:
	var old := _key_code(action)
	for other in REMAPPABLE:
		if other != action and _key_code(other) == code:
			_set_key(other, old)
	_set_key(action, code)
	save()


## True when the action is on the key the project gave it.
static func is_default_key(action: StringName) -> bool:
	return _key_code(action) == int(_default_keys.get(action, 0))


## Puts one action back on its default key. An action sitting on that key gets this one's
## current key, like a rebind.
static func reset_key(action: StringName) -> void:
	rebind(action, int(_default_keys.get(action, 0)))


static func reset_controls() -> void:
	for action in REMAPPABLE:
		_set_key(action, _default_keys.get(action, 0))
	save()


## Swaps the action's keyboard events for one key (or none for 0). Pad bindings stay.
static func _set_key(action: StringName, code: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	if code > 0:
		var key := InputEventKey.new()
		key.physical_keycode = code as Key
		InputMap.action_add_event(action, key)


static func _ensure_action(action: StringName, key_code: Key, pad_button: JoyButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key := InputEventKey.new()
	key.physical_keycode = key_code
	InputMap.action_add_event(action, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = pad_button
	InputMap.action_add_event(action, pad)


static func _current_display_mode() -> DisplayMode:
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return DisplayMode.FULLSCREEN
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return DisplayMode.BORDERLESS
	return DisplayMode.WINDOWED
