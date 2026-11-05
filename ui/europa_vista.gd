class_name EuropaVista
extends Control
## The main menu's backdrop: the view from the roof of an absurdly large industrial complex
## on the ice of Europa. Black starry sky (no air to scatter light), Jupiter fixed in the right
## border (Europa is tidally locked, so it never moves), and a snowed-in sea of buildings,
## chimneys, lattice masts and a radio telescope running to the horizon.
##
## The time of day comes from europa_clock.gd, the same clock the HUD shows in game, so the menu
## sky matches the game whatever the save or area. One Europa day lasts an hour. In the first half
## the small, distant sun rises at the left, arcs over the sky and slides behind Jupiter on the
## right: as Jupiter's limb covers it, Jupiter's shadow sweeps across the complex from the right
## and night begins. Through the night Jupiter waxes from a black disc (with a backlit ring
## just after the eclipse) to full and back to half by dawn, so its light on the snow changes too.
##
## The complex is painted once into three images when the menu opens: colour, which way each
## pixel faces (so the sun lights left, right or upward faces as it moves), and lit windows. A
## shader lights it every frame. Smoke, wind-blown snow, ice dust and blinking lights are drawn
## on top at native pixel scale.

const IMG_W: int = 800
const IMG_H: int = 270
## Eye level in the painted image: the horizon and the vanishing point.
const HORIZON: int = 150
const SUN_R: float = 2.5
const JUP_R: float = 112.0
## Width of the soft edge of Jupiter's shadow as it sweeps over, in pixels.
const SHADOW_SOFT: float = 34.0

const CLOCK := preload("res://ui/europa_clock.gd")

const SNOW := Color(0.86, 0.91, 0.97)
const SNOW_DIM := Color(0.66, 0.73, 0.83)
const PLAIN := Color(0.74, 0.78, 0.84)
const LINEA := Color(0.52, 0.34, 0.25)
const METAL := Color(0.3, 0.3, 0.32)
const METAL_DARK := Color(0.16, 0.16, 0.18)
const METAL_LIGHT := Color(0.46, 0.46, 0.47)
const RUST := Color(0.44, 0.24, 0.13)
const CONCRETE := Color(0.42, 0.42, 0.43)
const HAZE := Color(0.55, 0.61, 0.69)
const GLASS := Color(0.05, 0.06, 0.07)
const ICE := Color(0.64, 0.79, 0.89)
const WIN_AMBER := Color(1.0, 0.58, 0.2)
const WIN_WARM := Color(1.0, 0.78, 0.46)
const WIN_CYAN := Color(0.45, 0.9, 1.0)
const LIGHT_RED := Color(1.0, 0.13, 0.08)
const LIGHT_AMBER := Color(1.0, 0.6, 0.16)
const SMOKE := Color(0.5, 0.49, 0.5)
const STEAM := Color(0.84, 0.87, 0.91)
const NIGHT_AMBIENT := Color(0.035, 0.045, 0.075)
const DAY_AMBIENT := Color(0.1, 0.12, 0.17)
const SUN_LIGHT := Color(1.12, 1.08, 1.0)
const JUP_LIGHT := Color(1.0, 0.82, 0.62)
const TIERS: Array[float] = [0.46, 0.32, 0.22]
const V := Vector2(400.0, 150.0)

const SKY_SHADER := """
shader_type canvas_item;

uniform vec2 screen_size;
uniform vec2 sun_pos;
uniform float sun_r = 2.5;
uniform float sun_glare;
uniform vec2 jup_center;
uniform float jup_r;
uniform vec3 jup_light;
uniform float rim_gain;
uniform float star_gain;
uniform float t;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float bayer(vec2 p) {
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
			15.0, 7.0, 13.0, 5.0);
	ivec2 i = ivec2(mod(p, 4.0));
	return (m[i.x + i.y * 4] + 0.5) / 16.0;
}

vec3 bands(vec3 n) {
	float lat = n.y;
	float lon = atan(n.x, n.z);
	float warp = fbm(vec2(lon * 2.6, lat * 9.0) + vec2(t * 0.003, 0.0));
	float v = lat + (warp - 0.5) * 0.07;
	float b = sin(v * 19.0 + 0.6);
	vec3 c = mix(vec3(0.92, 0.85, 0.72), vec3(0.62, 0.42, 0.28), smoothstep(-0.2, 0.6, b));
	c *= 0.93 + 0.07 * sin(v * 95.0 + warp * 6.0);
	c = mix(c, vec3(0.95, 0.8, 0.6), smoothstep(0.08, 0.0, abs(v)) * 0.45);
	c = mix(c, vec3(0.5, 0.47, 0.46), smoothstep(0.55, 0.92, abs(v)));
	vec2 d = vec2((lon + 0.55) / 0.2, (v + 0.36) / 0.07);
	float spot = dot(d, d);
	c = mix(c, vec3(0.96, 0.9, 0.8), smoothstep(1.7, 1.15, spot) * 0.55);
	c = mix(c, vec3(0.76, 0.38, 0.24), smoothstep(1.0, 0.25, spot));
	return c;
}

void fragment() {
	vec2 p = floor(UV * screen_size) + 0.5;
	float dith = bayer(p);
	vec3 col = vec3(0.004, 0.005, 0.012);
	// A faint band of the galaxy across the sky, crowded with small stars.
	vec2 m = p / screen_size.y;
	float band = exp(-pow((m.y - 0.62 + m.x * 0.42) / 0.17, 2.0));
	col += vec3(0.05, 0.055, 0.08) * band * smoothstep(0.35, 0.8, fbm(p * 0.03)) * star_gain;
	float h = hash(p);
	if (h > 0.9935 - band * 0.012) {
		float b = hash(p + 17.3);
		float tw = 0.75 + 0.25 * sin(t * (1.0 + b * 3.0) + h * 80.0);
		vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.75), hash(p + 3.1));
		col += tint * (0.22 + 0.78 * b * b) * tw * star_gain;
	}
	vec2 cell = floor(p / 23.0);
	float ch = hash(cell + 91.7);
	if (ch > 0.74) {
		vec2 sp = cell * 23.0 + 3.0 + floor(vec2(hash(cell + 5.0), hash(cell + 9.0)) * 17.0) + 0.5;
		vec2 dd = abs(p - sp);
		float tw = 0.7 + 0.3 * sin(t * 1.7 + ch * 40.0);
		if (dd.x + dd.y < 0.5) {
			col += vec3(1.0) * tw * star_gain;
		} else if (dd.x + dd.y < 1.5) {
			col += vec3(0.42, 0.46, 0.58) * tw * star_gain;
		}
	}

	vec2 ds = p - sun_pos;
	float d = length(ds);
	vec2 q = (p - jup_center) / jup_r;
	float r2 = dot(q, q);
	if (r2 < 1.0) {
		vec3 n = vec3(q.x, -q.y, sqrt(1.0 - r2));
		vec3 c = bands(n);
		float lit = clamp(dot(n, jup_light) * 1.3 + 0.06, 0.0, 1.0);
		lit = floor(lit * 7.0 + dith) / 7.0;
		col = c * (0.012 + lit * 1.02);
		col *= mix(0.62, 1.0, pow(n.z, 0.35));
		// Backlit just after the eclipse: a thin bright ring on the side the sun went behind.
		vec2 sd = normalize(sun_pos - jup_center);
		float facing = 0.5 + 0.5 * dot(normalize(p - jup_center), sd);
		float edge = smoothstep(0.86, 1.0, sqrt(r2));
		col += vec3(1.0, 0.78, 0.52) * edge * pow(facing, 3.0) * rim_gain;
	} else if (d < sun_r) {
		col = vec3(1.0, 0.98, 0.93) * 1.6;
	}
	float g = sun_glare * (exp(-d / 5.0) * 0.55 + exp(-d / 26.0) * 0.12 + exp(-d / 90.0) * 0.05);
	if (abs(ds.x) < 0.5 || abs(ds.y) < 0.5) {
		g += sun_glare * exp(-d / 11.0) * 0.5;
	}
	g = floor(g * 14.0 + dith) / 14.0;
	col += vec3(1.0, 0.95, 0.86) * g;
	COLOR = vec4(col, 1.0);
}
"""

const LAND_SHADER := """
shader_type canvas_item;

uniform sampler2D face_tex : filter_nearest;
uniform sampler2D emit_tex : filter_nearest;
uniform float sun_amount;
uniform float sun_side;
uniform float sun_high;
uniform vec3 sun_color;
uniform float jup_amount;
uniform vec3 jup_color;
uniform vec3 ambient;
uniform float shadow_x;
uniform float shadow_soft;
uniform float emit_gain;

void fragment() {
	vec4 alb = texture(TEXTURE, UV);
	vec3 f = texture(face_tex, UV).rgb;
	vec4 e = texture(emit_tex, UV);
	float fx = f.r * 2.0 - 1.0;
	float up = f.g;
	float ao = f.b;
	float x = UV.x * float(textureSize(TEXTURE, 0).x);
	float lit_mask = 1.0 - smoothstep(shadow_x - shadow_soft, shadow_x + shadow_soft, x);
	// Facing us means facing away from the sun (it is somewhere ahead in the sky), so fronts
	// only get a little bounce off the snow; tops and the side towards the sun take the light.
	float direct = up * (0.4 + 0.6 * sun_high) + max(0.0, fx * sun_side) * (1.0 - 0.45 * sun_high)
			+ 0.14;
	float jup = up * 0.45 + max(0.0, fx) * 0.75 + 0.12;
	vec3 light = ambient + sun_color * (sun_amount * lit_mask * direct) + jup_color * (jup_amount * jup);
	vec3 col = alb.rgb * light * ao + e.rgb * e.a * emit_gain;
	COLOR = vec4(col, alb.a);
}
"""


class Puff:
	var pos: Vector2
	var vel: Vector2
	var age: float = 0.0
	var life: float = 6.0
	var r0: float = 1.0
	var grow: float = 1.0
	var steam: bool = false


var _alb: Image
var _face: Image
var _emit: Image
var _rng := RandomNumberGenerator.new()
var _sky: ColorRect
var _land: TextureRect
var _fx: Control
var _sky_mat: ShaderMaterial
var _land_mat: ShaderMaterial
var _t: float = 0.0
## Blinking lights in image pixels: x, y and kind (0 red beacon, 1 amber lamp, 2 white strobe).
var _lights: Array[Vector3] = []
## Smoke sources in image pixels: x, y and 1 for a cooling tower's steam.
var _stacks: Array[Vector3] = []
var _emit_wait: Array[float] = []
var _puffs: Array[Puff] = []
## Wind-blown flakes: x, y (screen), depth 0..1 and a wobble phase.
var _flakes: Array[Vector4] = []
## Snow streaming off the parapet and the roof: x, y, age, life.
var _drift: Array[Vector4] = []
var _drift_vel: Array[Vector2] = []
## Clouds of ice dust: x, y, width, height (screen), and the seed that scatters their streaks.
var _veils: Array[Vector4] = []
var _veil_seeds: Array[int] = []
var _streak_rng := RandomNumberGenerator.new()
var _wind: float = 150.0
var _gust: float = 0.0
var _gust_t: float = -1.0
var _gust_len: float = 4.0
var _gust_wait: float = 3.0

# The light this frame, shared by the shader and the particles.
var _sun_amount: float = 0.0
var _jup_amount: float = 0.0
var _ambient: Color = NIGHT_AMBIENT
var _shadow_screen_x: float = 9999.0
var _emit_gain: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7741
	_paint()
	_sky = ColorRect.new()
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = Shader.new()
	_sky_mat.shader.code = SKY_SHADER
	_sky.material = _sky_mat
	add_child(_sky)
	_land = TextureRect.new()
	_land.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_land.texture = ImageTexture.create_from_image(_alb)
	_land.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_land.size = Vector2(IMG_W, IMG_H)
	_land_mat = ShaderMaterial.new()
	_land_mat.shader = Shader.new()
	_land_mat.shader.code = LAND_SHADER
	_land_mat.set_shader_parameter("face_tex", ImageTexture.create_from_image(_face))
	_land_mat.set_shader_parameter("emit_tex", ImageTexture.create_from_image(_emit))
	_land_mat.set_shader_parameter("shadow_soft", SHADOW_SOFT)
	_land.material = _land_mat
	add_child(_land)
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_alb = null
	_face = null
	_emit = null
	var screen := _screen()
	for i in 300:
		_flakes.append(Vector4(_rng.randf_range(0, screen.x), _rng.randf_range(0, screen.y),
				_rng.randf(), _rng.randf_range(0, TAU)))
	for i in 7:
		_veils.append(_new_veil(screen, true))
		_veil_seeds.append(_rng.randi())
	for s in _stacks:
		_emit_wait.append(0.0)
	# Let the smoke trails exist already when the menu appears.
	_layout()
	_update_light()
	for i in 240:
		_update_particles(1.0 / 30.0)


func _process(delta: float) -> void:
	_t += delta
	_layout()
	_update_light()
	_update_particles(delta)
	_fx.queue_redraw()


func _screen() -> Vector2:
	return get_viewport_rect().size


func _layout() -> void:
	var screen := _screen()
	# Sized by hand each frame (no anchors: its parent is a CanvasLayer).
	size = screen
	_land.position = Vector2(floorf((screen.x - IMG_W) * 0.5), screen.y - IMG_H)


func _phase() -> float:
	return CLOCK.phase()


# --- Day and night -----------------------------------------------------------------------------


func _update_light() -> void:
	var screen := _screen()
	var o := _land.position
	var horizon_y := o.y + HORIZON
	var jc := Vector2(screen.x + 6.0, o.y + 98.0)
	var rise := Vector2(-8.0, horizon_y + 6.0)
	var set_at := jc + Vector2(-0.94, -0.34).normalized() * (JUP_R - 4.0)
	var ctrl := Vector2(screen.x * 0.42, o.y - 70.0)
	var phase := _phase()
	var sun := rise
	var sun_amount := 0.0
	var cover := 1.0
	var light_dir := Vector2.LEFT
	var phi := PI
	var rim := 0.0
	if phase < 0.5:
		var s := phase / 0.5
		sun = rise.lerp(ctrl, s).lerp(ctrl.lerp(set_at, s), s)
		var dist := sun.distance_to(jc)
		cover = clampf((JUP_R + SUN_R - dist) / (2.0 * SUN_R), 0.0, 1.0)
		sun_amount = smoothstep(-3.0, 10.0, horizon_y - sun.y)
		light_dir = (sun - jc).normalized()
		var d0 := rise.distance_to(jc)
		phi = PI - PI * 0.5 * clampf((dist - JUP_R) / (d0 - JUP_R), 0.0, 1.0)
		rim = clampf(1.0 - (dist - JUP_R) / 30.0, 0.0, 1.0) * 0.9
	else:
		var u := (phase - 0.5) / 0.5
		sun = set_at
		if u < 0.5:
			light_dir = Vector2.RIGHT
			phi = PI * (1.0 - 2.0 * u)
		else:
			light_dir = (rise - jc).normalized()
			phi = PI * (u - 0.5)
		rim = maxf(0.0, 1.0 - (phase - 0.5) * CLOCK.DAY_SECONDS / 70.0) * 0.9
	# Jupiter's lit side: light_dir is on screen (y down), phi the angle from our line of sight.
	var jl := Vector3(light_dir.x * sin(phi), -light_dir.y * sin(phi), cos(phi))
	var lit_share := (1.0 + cos(phi)) * 0.5
	_sun_amount = sun_amount
	_jup_amount = 0.04 + 0.34 * lit_share
	# Jupiter's shadow sweeps in from the right while its limb covers the sun.
	var visible_l := -o.x
	var visible_r := visible_l + screen.x
	var sweep := smoothstep(0.0, 1.0, cover)
	var shadow_img_x := lerpf(visible_r + SHADOW_SOFT * 2.0, visible_l - SHADOW_SOFT * 2.0, sweep)
	if phase >= 0.5:
		shadow_img_x = visible_l - SHADOW_SOFT * 4.0
	_shadow_screen_x = shadow_img_x + o.x
	var day := sun_amount * (1.0 - sweep)
	_ambient = NIGHT_AMBIENT.lerp(DAY_AMBIENT, day)
	_emit_gain = lerpf(1.0, 0.65, day)
	var sun_side := clampf((sun.x - screen.x * 0.5) / (screen.x * 0.5), -1.0, 1.0)
	var sun_high := clampf((horizon_y - sun.y) / (horizon_y - 15.0), 0.0, 1.0)

	_sky_mat.set_shader_parameter("screen_size", screen)
	_sky_mat.set_shader_parameter("sun_pos", sun.floor() + Vector2(0.5, 0.5))
	_sky_mat.set_shader_parameter("sun_r", SUN_R)
	_sky_mat.set_shader_parameter("sun_glare", sun_amount * (1.0 - cover) if phase < 0.5 else 0.0)
	_sky_mat.set_shader_parameter("jup_center", jc)
	_sky_mat.set_shader_parameter("jup_r", JUP_R)
	_sky_mat.set_shader_parameter("jup_light", jl)
	_sky_mat.set_shader_parameter("rim_gain", rim)
	_sky_mat.set_shader_parameter("star_gain", lerpf(1.0, 0.6, day))
	_sky_mat.set_shader_parameter("t", _t)
	_land_mat.set_shader_parameter("sun_amount", sun_amount if phase < 0.5 else 0.0)
	_land_mat.set_shader_parameter("sun_side", sun_side)
	_land_mat.set_shader_parameter("sun_high", sun_high)
	_land_mat.set_shader_parameter("sun_color", Vector3(SUN_LIGHT.r, SUN_LIGHT.g, SUN_LIGHT.b))
	_land_mat.set_shader_parameter("jup_amount", _jup_amount)
	_land_mat.set_shader_parameter("jup_color", Vector3(JUP_LIGHT.r, JUP_LIGHT.g, JUP_LIGHT.b))
	_land_mat.set_shader_parameter("ambient", Vector3(_ambient.r, _ambient.g, _ambient.b))
	_land_mat.set_shader_parameter("shadow_x", shadow_img_x)
	_land_mat.set_shader_parameter("emit_gain", _emit_gain)
	if phase >= 0.5:
		_sun_amount = 0.0


## How brightly something floating at screen x is lit right now, 0 to about 1.2.
func _lum(x: float) -> float:
	var mask := 1.0 - smoothstep(_shadow_screen_x - SHADOW_SOFT, _shadow_screen_x + SHADOW_SOFT, x)
	return _ambient.b * 1.6 + _sun_amount * mask * 0.9 + _jup_amount * 0.55


# --- Wind, snow and smoke ----------------------------------------------------------------------


func _new_veil(screen: Vector2, anywhere: bool) -> Vector4:
	var w := _rng.randf_range(70.0, 190.0)
	var x: float = _rng.randf_range(-w, screen.x) if anywhere else screen.x + _rng.randf_range(0.0, 120.0)
	return Vector4(x, _rng.randf_range(screen.y * 0.35, screen.y - 8.0), w, _rng.randf_range(8.0, 34.0))


func _update_particles(delta: float) -> void:
	var screen := _screen()
	var o := _land.position
	# Gusts come every few seconds on top of an already strong, uneven wind.
	_gust_wait -= delta
	if _gust_t < 0.0 and _gust_wait <= 0.0:
		_gust_t = 0.0
		_gust_len = _rng.randf_range(2.5, 5.0)
	if _gust_t >= 0.0:
		_gust_t += delta
		_gust = pow(sin(PI * clampf(_gust_t / _gust_len, 0.0, 1.0)), 2.0)
		if _gust_t >= _gust_len:
			_gust_t = -1.0
			_gust = 0.0
			_gust_wait = _rng.randf_range(4.0, 11.0)
	_wind = 150.0 + 35.0 * sin(_t * 0.23) + 22.0 * sin(_t * 0.71 + 1.0) + _gust * 170.0

	for i in _flakes.size():
		var f := _flakes[i]
		f.x -= _wind * (0.4 + f.z * 1.15) * delta
		f.y += (sin(_t * 2.3 + f.w) * 16.0 * f.z + 8.0 + f.z * 10.0 - _gust * 14.0) * delta
		if f.x < -8.0 or f.y > screen.y + 2.0 or f.y < -12.0:
			f.x = screen.x + _rng.randf_range(0.0, 30.0)
			f.y = _rng.randf_range(-6.0, screen.y)
		_flakes[i] = f

	var i := 0
	while i < _drift.size():
		var d := _drift[i]
		d.z += delta
		if d.z >= d.w:
			_drift.remove_at(i)
			_drift_vel.remove_at(i)
			continue
		var v := _drift_vel[i]
		v.y += 22.0 * delta
		v.x = lerpf(v.x, -_wind * 0.95, delta * 2.0)
		d.x += v.x * delta
		d.y += v.y * delta
		_drift[i] = d
		_drift_vel[i] = v
		i += 1
	var want := int(90.0 + 110.0 * _gust)
	while _drift.size() < want:
		var low := _rng.randf() < 0.55
		var y: float = o.y + (_rng.randf_range(226.0, 236.0) if not low else _rng.randf_range(238.0, 270.0))
		_drift.append(Vector4(_rng.randf_range(0.0, screen.x + 40.0), y, 0.0, _rng.randf_range(0.5, 2.2)))
		_drift_vel.append(Vector2(-_wind * _rng.randf_range(0.5, 0.9),
				_rng.randf_range(-26.0, -4.0) if not low else _rng.randf_range(-6.0, 2.0)))

	for k in _veils.size():
		var vl := _veils[k]
		vl.x -= _wind * 0.85 * delta
		if vl.x + vl.z < -10.0:
			vl = _new_veil(screen, false)
			_veil_seeds[k] = _rng.randi()
		_veils[k] = vl

	for k in _stacks.size():
		var s := _stacks[k]
		_emit_wait[k] -= delta
		if _emit_wait[k] > 0.0:
			continue
		var steam := s.z > 0.5
		_emit_wait[k] = 0.07 if steam else 0.05
		var p := Puff.new()
		p.pos = Vector2(s.x, s.y) + Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 0.5))
		p.vel = Vector2(-_wind * 0.08, _rng.randf_range(-16.0, -7.0))
		p.steam = steam
		p.life = _rng.randf_range(4.0, 6.0) if steam else _rng.randf_range(3.5, 5.0)
		p.r0 = 2.0 if steam else 1.0
		p.grow = _rng.randf_range(1.1, 1.6) if steam else _rng.randf_range(0.8, 1.3)
		_puffs.append(p)
	i = 0
	while i < _puffs.size():
		var p := _puffs[i]
		p.age += delta
		if p.age >= p.life:
			_puffs.remove_at(i)
			continue
		# Bent over hard by the wind once clear of the mouth, still rising a little.
		p.vel.x = lerpf(p.vel.x, -_wind * 0.42, delta * 0.9)
		p.vel.y = lerpf(p.vel.y, -3.0, delta * 0.6)
		p.pos += p.vel * delta + Vector2(0.0, sin(_t * 1.3 + p.life * 7.0) * 5.0 * delta)
		i += 1


func _draw_fx() -> void:
	var screen := _screen()
	var o := _land.position
	var night := 1.0 - clampf(_sun_amount, 0.0, 1.0) * 0.6
	# Beacons and lamps on the structures.
	for l in _lights:
		var p := Vector2(l.x, l.y) + o
		if p.x < -3.0 or p.x > screen.x + 3.0:
			continue
		var ph := fmod(l.x * 0.37 + l.y * 0.11, TAU)
		var on := 0.0
		var c := LIGHT_RED
		match int(l.z):
			0:
				on = clampf(sin(_t * PI * 0.8 + ph) * 1.6, 0.0, 1.0)
			1:
				c = LIGHT_AMBER
				on = 0.75 + 0.25 * sin(_t * 9.0 + ph) * sin(_t * 2.3 + ph * 2.0)
			2:
				c = Color(0.9, 0.95, 1.0)
				on = 1.0 if fmod(_t + ph, 2.6) < 0.07 else 0.0
		if on <= 0.01:
			continue
		var g := c
		g.a = 0.33 * on * night
		_fx.draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), g)
		_fx.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), g)
		g.a = 0.1 * on * night
		_fx.draw_rect(Rect2(p + Vector2(-2, -1), Vector2(5, 3)), g)
		_fx.draw_rect(Rect2(p + Vector2(-1, -2), Vector2(3, 5)), g)
		var core := c.lerp(Color.WHITE, 0.3)
		core.a = on
		_fx.draw_rect(Rect2(p, Vector2.ONE), core)

	# Smoke and steam, lit like everything else, the smoke glowing amber just above the mouth.
	for p in _puffs:
		var k := p.age / p.life
		var r := int(p.r0 + p.age * p.grow * 1.1)
		var lum := _lum(p.pos.x + o.x)
		var base := STEAM if p.steam else SMOKE
		var c := Color(base.r * lum, base.g * lum, base.b * lum)
		if not p.steam and p.age < 0.7:
			c = c.lerp(Color(1.0, 0.45, 0.15), (1.0 - p.age / 0.7) * 0.6 * night)
		c.a = (0.17 if p.steam else 0.24) * pow(1.0 - k, 1.2) * minf(1.0, p.age / 0.15)
		var center := (p.pos + o).floor()
		for dy in range(-r, r + 1):
			var half := int(sqrt(float(r * r - dy * dy)))
			var row := c
			if dy < 0:
				row = c.lightened(0.08)
			_fx.draw_rect(Rect2(center.x - half, center.y + dy, half * 2 + 1, 1), row)

	# Ice dust blowing through in clouds of fine streaks, thicker in gusts.
	for v in _veils.size():
		var vl := _veils[v]
		var lum := _lum(vl.x + vl.z * 0.5)
		_streak_rng.seed = _veil_seeds[v]
		for k in 36:
			var u := _streak_rng.randf_range(-1.0, 1.0)
			var w := _streak_rng.randf_range(-1.0, 1.0)
			var length := _streak_rng.randf_range(3.0, 20.0)
			var r2 := u * u + w * w
			if r2 > 1.0:
				continue
			var c := Color(SNOW.r * lum, SNOW.g * lum, SNOW.b * lum,
					(0.05 + 0.07 * _gust) * (1.0 - r2))
			var x := floorf(vl.x + vl.z * 0.5 * (1.0 + u))
			_fx.draw_rect(Rect2(x, floorf(vl.y + vl.w * 0.5 * w), floorf(length * (1.0 - r2 * 0.6)) + 1.0, 1), c)

	# Snow streaming off the parapet and along the roof.
	for k in _drift.size():
		var d := _drift[k]
		var a := sin(PI * d.z / d.w)
		var lum := _lum(d.x)
		var c := Color(SNOW.r * lum, SNOW.g * lum, SNOW.b * lum, 0.55 * a)
		var length := 1.0 + floorf(absf(_drift_vel[k].x) / 90.0)
		_fx.draw_rect(Rect2(floorf(d.x), floorf(d.y), length, 1), c)

	# Flakes: far ones single faint pixels, near ones streaks that stretch in the gusts.
	for f in _flakes:
		var lum := _lum(f.x)
		var c := Color(SNOW.r * lum, SNOW.g * lum, SNOW.b * lum)
		var x := floorf(f.x)
		var y := floorf(f.y)
		if f.z < 0.45:
			c.a = 0.22 + f.z * 0.5
			_fx.draw_rect(Rect2(x, y, 1, 1), c)
		else:
			var length := floorf(1.0 + _wind * (f.z - 0.3) / 70.0)
			c.a = 0.35 + f.z * 0.45
			_fx.draw_rect(Rect2(x, y, 1, 1), c)
			if length > 1.0:
				c.a *= 0.45
				_fx.draw_rect(Rect2(x + 1, y, length - 1.0, 1), c)


# --- Painting the complex ----------------------------------------------------------------------


func _paint() -> void:
	_alb = Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	_face = Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGB8)
	_emit = Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	_face.fill(Color(0.5, 0.0, 1.0))
	_plain()
	_row(156, 3, 12, 4, 13, 0.62, 0.05, 1, 0.75)
	_row(162, 4, 18, 5, 16, 0.55, 0.06, 1, 0.8)
	# The far giants and the steaming cooling towers behind the middle.
	_mega(70, 150, 168, 56, 0.45)
	_mega(650, 724, 168, 66, 0.45)
	_cooling(452, 170, 22, 13, 0.5, false)
	_cooling(478, 171, 26, 15, 0.48, true)
	_mast(364, 170, 96, 6, 0.5, true)
	_mast(436, 170, 104, 6, 0.5, true)
	_row(173, 7, 28, 8, 22, 0.42, 0.07, 1, 0.85)
	_pipe(176, 3, 0.38, 0, IMG_W)
	# The middle distance: the radio telescope, the big chimneys, tall masts.
	_dish(232, 72, 44.0, 17.0, -0.18, 0.24, 192)
	_stack(300, 192, 50, 9, 0.24, true)
	_stack(316, 192, 82, 7, 0.26, false)
	_stack(545, 192, 86, 7, 0.26, false)
	_stack(562, 192, 58, 9, 0.24, true)
	_mast(612, 198, 8, 18, 0.22, true)
	_mast(178, 198, 22, 16, 0.22, true)
	_mast(348, 196, 92, 8, 0.28, true)
	_mast(470, 196, 84, 9, 0.28, true)
	_curtain(36, 120, 196, 40, 0.26)
	_curtain(680, 770, 196, 44, 0.26)
	_row(190, 12, 40, 12, 30, 0.28, 0.08, 1, 0.9)
	_pipe(194, 4, 0.22, 0, IMG_W)
	_row(206, 16, 52, 16, 38, 0.16, 0.09, 2, 0.92)
	_pipe(209, 5, 0.12, 0, IMG_W)
	# Close by: tall dark blocks at the sides and a row of rooftops just below us.
	_mega(96, 178, 236, 92, 0.06)
	_mega(642, 714, 236, 112, 0.06)
	_row(232, 22, 70, 24, 52, 0.05, 0.1, 2, 0.9)
	_roof()


## The ice plain out to the horizon, cut by Europa's reddish ridges.
func _plain() -> void:
	for y in range(HORIZON, IMG_H):
		var t := float(y - HORIZON) / float(IMG_H - HORIZON)
		_fill(Rect2i(0, y, IMG_W, 1), PLAIN.lerp(HAZE, 0.55 * (1.0 - t)), 0.0, 1.0)
	# The horizon is not perfectly flat.
	for x in IMG_W:
		var bump := int(1.5 + sin(x * 0.031) * 1.2 + sin(x * 0.11 + 2.0) * 0.8)
		if bump > 0:
			_fill(Rect2i(x, HORIZON - bump, 1, bump), PLAIN.lerp(HAZE, 0.62), 0.0, 1.0)
	# Ridges (lineae): long double lines, nearly flat near the horizon.
	for k in 9:
		var y0 := float(HORIZON + 1 + _rng.randi_range(0, 18))
		var slope := _rng.randf_range(-0.03, 0.03)
		var x0 := _rng.randi_range(-200, IMG_W)
		var run := _rng.randi_range(120, 420)
		for x in range(x0, x0 + run):
			var y := int(y0 + (x - x0) * slope + sin(x * 0.02 + k) * 1.5)
			if y <= HORIZON:
				continue
			var c := LINEA.lerp(HAZE, 0.45)
			_dot(x, y, c, 0.0, 0.8)
			if (x + k) % 3 != 0:
				_dot(x, y + 1, PLAIN.lerp(LINEA, 0.35), 0.0, 1.0)


## A row of buildings at one distance, sitting on base_y.
func _row(base_y: int, hmin: int, hmax: int, wmin: int, wmax: int, haze: float, depth: float,
		win: int, density: float) -> void:
	var x := -_rng.randi_range(0, wmax)
	while x < IMG_W:
		var w := _rng.randi_range(wmin, wmax)
		if _rng.randf() < density:
			var h := _rng.randi_range(hmin, hmax)
			var top := base_y - h
			var colors: Array[Color] = [METAL, METAL_DARK, CONCRETE.darkened(0.2), METAL.lerp(RUST, 0.3)]
			_box(x, top, x + w, base_y + 3, depth, colors[_rng.randi_range(0, 3)], haze, 0.22, win)
			var gear := _rng.randf()
			var col := METAL_DARK.lerp(HAZE, haze)
			if gear < 0.18 and w > 6:
				# A small stack.
				var sx := x + _rng.randi_range(1, w - 3)
				var sh := _rng.randi_range(3, 3 + h / 3)
				_fill(Rect2i(sx, top - sh, 2, sh), col, 0.0, 0.0)
				_dot(sx, top - sh - 1, SNOW.lerp(HAZE, haze * 0.6), 0.0, 1.0)
				_dot(sx + 1, top - sh - 1, SNOW.lerp(HAZE, haze * 0.6), 0.0, 1.0)
				if _rng.randf() < 0.5:
					_light(sx, top - sh - 2, 0)
			elif gear < 0.36:
				# A whip antenna.
				var ax := x + _rng.randi_range(0, w - 1)
				var ah := _rng.randi_range(4, 6 + h / 2)
				_fill(Rect2i(ax, top - ah, 1, ah), col, 0.0, 0.0)
				if _rng.randf() < 0.4:
					_light(ax, top - ah - 1, 0)
			elif gear < 0.46 and w > 8:
				# A little dish on the roof.
				var dx := x + _rng.randi_range(2, w - 4)
				_fill(Rect2i(dx, top - 3, 3, 2), METAL_LIGHT.lerp(HAZE, haze), 0.0, 0.7)
				_dot(dx + 1, top - 1, col)
		x += w + _rng.randi_range(-wmin / 2, 2)


## One building in one-point perspective: the front, plus the side and the snowed top it shows
## from here. depth is how much smaller its back face is.
func _box(x0: int, y0: int, x1: int, y1: int, depth: float, base: Color, haze: float,
		windows: float, win: int) -> void:
	var f := 1.0 - depth
	var c := base.lerp(HAZE, haze)
	var snow := SNOW.lerp(HAZE, haze * 0.6)
	if float(x1) < V.x:
		_poly(PackedVector2Array([Vector2(x1, y0), _back(Vector2(x1, y0), f), _back(Vector2(x1, y1), f),
				Vector2(x1, y1)]), c.darkened(0.12), 1.0, 0.0)
	elif float(x0) > V.x:
		_poly(PackedVector2Array([Vector2(x0, y0), _back(Vector2(x0, y0), f), _back(Vector2(x0, y1), f),
				Vector2(x0, y1)]), c.darkened(0.12), -1.0, 0.0)
	if float(y0) > V.y + 1.0:
		_poly(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), _back(Vector2(x1, y0), f),
				_back(Vector2(x0, y0), f)]), snow, 0.0, 1.0)
	var w := x1 - x0
	var h := y1 - y0
	_fill(Rect2i(x0, y0, w, h), c)
	if w < 3 or h < 3:
		return
	# Panel seams.
	var seam := c.darkened(0.28)
	var step := _rng.randi_range(4, 9)
	for sx in range(x0 + step, x1 - 1, step):
		_fill(Rect2i(sx, y0 + 1, 1, h - 1), seam)
	# Floors of windows, a few lit.
	var floor_h := win + _rng.randi_range(2, 3)
	for wy in range(y0 + 2, y1 - 2, floor_h):
		if _rng.randf() < 0.25:
			continue
		var lit_row := _rng.randf() < 0.5
		for wx in range(x0 + 1, x1 - win, win + 1):
			if _rng.randf() < windows * (1.6 if lit_row else 0.5):
				var g := WIN_AMBER
				var roll := _rng.randf()
				if roll < 0.12:
					g = WIN_CYAN
				elif roll < 0.4:
					g = WIN_WARM
				g.a = lerpf(1.0, 0.55, haze)
				for k in win:
					_glow(wx + k, wy, g)
			elif win > 1 and _rng.randf() < 0.5:
				_fill(Rect2i(wx, wy, win, 1), GLASS.lerp(c, 0.4))
	# Rust running down from a few seams.
	for k in _rng.randi_range(0, 2 + w / 12):
		var rx := _rng.randi_range(x0, x1 - 1)
		var ry := _rng.randi_range(y0, y1 - 2)
		_fill(Rect2i(rx, ry, 1, _rng.randi_range(2, 7)), RUST.lerp(HAZE, haze))
	# Snow on the top edge and rime plastered on the windward (right) edge.
	_fill(Rect2i(x0, y0, w, 1), snow, 0.0, 0.8)
	if float(y0) <= V.y + 1.0:
		for x in range(x0, x1):
			if _rng.randf() < 0.45:
				_dot(x, y0 - 1, snow, 0.0, 1.0)
	for y in range(y0, y1):
		if _rng.randf() < 0.3:
			_dot(x1 - 1, y, snow, 0.5, 0.2)
	for x in range(x0, x1):
		if _rng.randf() < 0.18:
			_fill(Rect2i(x, y0 + 1, 1, _rng.randi_range(1, 3)), snow.lerp(c, 0.4), 0.0, 0.3)


func _back(p: Vector2, f: float) -> Vector2:
	return V + (p - V) * f


## A stepped megastructure: three blocks with setbacks, pipes up its face and glowing vents.
func _mega(x0: int, x1: int, base_y: int, top_y: int, haze: float) -> void:
	var h := base_y - top_y
	var y := base_y
	var l := x0
	var r := x1
	for k in 3:
		var th := int(h * TIERS[k])
		_box(l, y - th, r, y, 0.04, METAL_DARK if k != 1 else METAL, haze, 0.4, 2 if haze < 0.2 else 1)
		# Pipes up the face.
		for p in 2:
			var px := l + 3 + _rng.randi_range(0, maxi(1, r - l - 8))
			for i in 3:
				var fx := float(i) - 1.0
				_fill(Rect2i(px + i, y - th + 2, 1, th - 2), METAL_LIGHT.darkened(0.2).lerp(HAZE, haze), fx)
			for fy in range(y - th + 6, y, 9):
				_fill(Rect2i(px - 1, fy, 5, 1), METAL_DARK.lerp(HAZE, haze))
		# Big vents with a warm glow behind the louvres.
		if r - l > 20:
			var vx := l + _rng.randi_range(4, r - l - 14)
			var vy := y - th + _rng.randi_range(4, maxi(5, th - 10))
			for row in range(0, 6, 2):
				var g := WIN_AMBER
				g.a = lerpf(0.75, 0.4, haze)
				for x in range(vx, vx + 9):
					_glow(x, vy + row, g)
		y -= th
		var setback := maxi(3, (r - l) / 6)
		l += setback + _rng.randi_range(-1, 2)
		r -= setback + _rng.randi_range(-1, 2)
	# Roof gear: a crane boom and a couple of small dishes.
	var col := METAL_DARK.lerp(HAZE, haze)
	var cx := (l + r) / 2
	_fill(Rect2i(cx, y - 18, 2, 18), col)
	_line(Vector2(cx - 22, y - 16), Vector2(cx + 12, y - 19), col)
	_line(Vector2(cx - 22, y - 16), Vector2(cx - 22, y - 8), col.lerp(HAZE, 0.3))
	_fill(Rect2i(cx - 23, y - 8, 3, 2), col)
	_light(cx, y - 19, 0)
	_light(cx - 22, y - 17, 0)
	_fill(Rect2i(l + 2, y - 4, 4, 2), METAL_LIGHT.lerp(HAZE, haze), 0.0, 0.8)
	_fill(Rect2i(r - 7, y - 5, 5, 3), METAL_LIGHT.lerp(HAZE, haze), 0.0, 0.8)


## A tall round chimney: rust bands, a faded red and white top, rings with snow on them and rime
## on the windward side. Smoking ones glow at the mouth.
func _stack(cx: int, base_y: int, top_y: int, w: int, haze: float, smoke: bool) -> void:
	var x0 := cx - w / 2
	for y in range(top_y, base_y):
		var from_top := y - top_y
		var c := CONCRETE.darkened(0.3)
		if from_top < 14:
			c = Color(0.52, 0.2, 0.14) if (from_top / 5) % 2 == 0 else Color(0.62, 0.6, 0.57)
		elif (from_top % 16) < 2:
			c = RUST
		c = c.lerp(HAZE, haze)
		for i in w:
			var fx := (float(i) + 0.5) / float(w) * 2.0 - 1.0
			_dot(x0 + i, y, c, fx, 0.0, 0.9 + 0.1 * (1.0 - absf(fx)))
		if _rng.randf() < 0.4:
			_dot(x0 + w - 1, y, SNOW.lerp(HAZE, haze * 0.6), 0.8, 0.2)
	# Ladder.
	var lad := METAL_DARK.lerp(HAZE, haze)
	_fill(Rect2i(x0 + 1, top_y + 2, 1, base_y - top_y - 2), lad)
	# Rings with snow on them.
	for ry in range(top_y + 22, base_y - 6, 28):
		_fill(Rect2i(x0 - 1, ry, w + 2, 1), lad)
		_fill(Rect2i(x0 - 1, ry - 1, w + 2, 1), SNOW.lerp(HAZE, haze * 0.6), 0.0, 1.0)
	# The lip, with snow on it and a dark (or glowing) mouth.
	_fill(Rect2i(x0 - 1, top_y - 1, w + 2, 2), METAL.lerp(HAZE, haze))
	_fill(Rect2i(x0 - 1, top_y - 2, w + 2, 1), SNOW.lerp(HAZE, haze * 0.6), 0.0, 1.0)
	if smoke:
		var g := WIN_AMBER
		g.a = 0.8
		for i in range(1, w - 1):
			_glow(x0 + i, top_y - 2, g)
		_stacks.append(Vector3(cx, top_y - 3, 0.0))
	_light(x0 - 1, top_y + 3, 0)
	_light(x0 + w, top_y + 3, 0)


## A cooling tower: a waisted shell, stained, with snow on the rim.
func _cooling(cx: int, base_y: int, h: int, wb: int, haze: float, steam: bool) -> void:
	for y in range(base_y - h, base_y):
		var t := float(base_y - y) / float(h)
		var waist := 0.7
		var k := (t - waist) / (waist if t < waist else 1.0 - waist)
		var half := float(wb) * (0.62 + (0.38 if t < waist else 0.16) * k * k)
		var l := int(round(cx - half))
		var r := int(round(cx + half))
		for x in range(l, r + 1):
			var fx := (float(x - l) + 0.5) / float(r - l + 1) * 2.0 - 1.0
			var c := CONCRETE.lerp(SNOW, 0.15)
			if hash(Vector2i(x, y / 3)) % 7 == 0:
				c = c.darkened(0.2)
			_dot(x, y, c.lerp(HAZE, haze), fx)
	var top_half := int(float(wb) * 0.78)
	_fill(Rect2i(cx - top_half, base_y - h - 1, top_half * 2 + 1, 1), SNOW.lerp(HAZE, haze * 0.6), 0.0, 1.0)
	if steam:
		_stacks.append(Vector3(cx, base_y - h - 2, 1.0))


## A tapering lattice mast with X bracing, platforms with drum antennas, guy wires and beacons.
func _mast(cx: int, base_y: int, top_y: int, wb: int, haze: float, guys: bool) -> void:
	var col := METAL_DARK.lerp(HAZE, haze)
	var rime := SNOW.lerp(HAZE, haze * 0.6)
	var h := base_y - top_y
	if guys:
		var wire := col.lerp(HAZE, 0.35 + haze * 0.3)
		for k in 2:
			var ay := top_y + int(h * (0.22 + 0.32 * k))
			for s in 2:
				var side := s * 2 - 1
				var gx := cx + side * int(h * (0.42 + 0.22 * k))
				_line(Vector2(cx, ay), Vector2(gx, base_y), wire, 2)
	for y in range(top_y, base_y + 1):
		var half := _mast_half(y, base_y, h, wb)
		_dot(int(round(cx - half)), y, col, -1.0)
		_dot(int(round(cx + half)), y, col, 1.0)
		if _rng.randf() < 0.22:
			_dot(int(round(cx + half)) + 1, y, rime, 1.0, 0.3)
	var y := base_y
	while y > top_y + 3:
		var ha := _mast_half(y, base_y, h, wb)
		var seg := maxi(3, int(ha * 2.4))
		var yb := maxi(top_y, y - seg)
		var hb := _mast_half(yb, base_y, h, wb)
		_line(Vector2(cx - ha, y), Vector2(cx + hb, yb), col)
		_line(Vector2(cx + ha, y), Vector2(cx - hb, yb), col)
		_line(Vector2(cx - hb, yb), Vector2(cx + hb, yb), col)
		y = yb
	# Platforms with drum antennas.
	var py := base_y - 36
	while py > top_y + 14:
		var half := int(_mast_half(py, base_y, h, wb))
		_fill(Rect2i(cx - half - 2, py, half * 2 + 5, 1), col)
		_fill(Rect2i(cx - half - 2, py - 1, half * 2 + 5, 1), rime, 0.0, 1.0)
		for s in 2:
			if _rng.randf() < 0.7:
				var side := s * 2 - 1
				var dx := cx + side * (half + 2) - (2 if side < 0 else 0)
				_fill(Rect2i(dx, py + 1, 1, 3), METAL_LIGHT.lerp(HAZE, haze), -1.0)
				_fill(Rect2i(dx + 1, py + 1, 1, 3), METAL_LIGHT.lerp(HAZE, haze), 1.0)
				_dot(dx, py, rime, 0.0, 1.0)
		_light(cx - half - 2, py, 1 if haze < 0.3 else 0)
		py -= 36 + _rng.randi_range(-4, 6)
	_fill(Rect2i(cx, top_y - 10, 1, 10), col)
	_light(cx, top_y - 11, 0)
	_light(cx, top_y + h / 2, 0)
	if h > 120:
		_light(cx, top_y - 4, 2)


func _mast_half(y: int, base_y: int, h: int, wb: int) -> float:
	var t := float(base_y - y) / float(h)
	return maxf(0.6, lerpf(float(wb) * 0.5, 0.8, t))


## A curtain antenna: wires strung between two masts, hung with rows of dipoles.
func _curtain(x0: int, x1: int, base_y: int, top: int, haze: float) -> void:
	_mast(x0, base_y, base_y - top - 30, 6, haze, false)
	_mast(x1, base_y, base_y - top - 30, 6, haze, false)
	var col := METAL_DARK.lerp(HAZE, haze + 0.12)
	for k in 4:
		var y := base_y - top - 22 + k * 9
		for x in range(x0, x1):
			var t := float(x - x0) / float(x1 - x0)
			var sag := int(4.0 * t * (1.0 - t) * 4.0)
			_dot(x, y + sag, col)
			if (x - x0) % 6 == 3:
				_dot(x, y + sag + 1, col)
				_dot(x, y + sag + 2, col)
				if _rng.randf() < 0.3:
					_dot(x, y + sag - 1, SNOW.lerp(HAZE, haze * 0.6), 0.0, 1.0)


## A long pipeline crossing the complex on low trestles, snow along its top.
func _pipe(y: int, thick: int, haze: float, x0: int, x1: int) -> void:
	var c := METAL.lerp(RUST, 0.25).lerp(HAZE, haze)
	for x in range(x0, x1, 34):
		_fill(Rect2i(x + 6, y + thick, 2, 4 + thick), METAL_DARK.lerp(HAZE, haze))
	_fill(Rect2i(x0, y, x1 - x0, 1), SNOW.lerp(HAZE, haze * 0.6), 0.0, 1.0)
	for i in range(1, thick):
		var up := 0.7 - float(i) / float(thick) * 0.7
		_fill(Rect2i(x0, y + i, x1 - x0, 1), c, 0.0, up, 1.0 - float(i) / float(thick) * 0.35)
	for x in range(x0 + 11, x1, 22):
		_fill(Rect2i(x, y, 1, thick), c.lightened(0.15), 0.0, 0.4)


## The radio telescope: a big dish on a yoke and pedestal, facing up into the sky, snow lying
## in the bottom of the bowl, the feed held over it on four legs.
func _dish(cx: int, cy: int, rx: float, ry: float, tilt: float, haze: float, base_y: int) -> void:
	var col := METAL_DARK.lerp(HAZE, haze)
	var conc := CONCRETE.darkened(0.15).lerp(HAZE, haze)
	# Pedestal and yoke.
	var ped_top := cy + int(ry * 0.5) + 10
	_box(cx - 9, ped_top, cx + 9, base_y, 0.04, CONCRETE.darkened(0.25), haze, 0.15, 1)
	_poly(PackedVector2Array([Vector2(cx - 15, ped_top + 1), Vector2(cx + 15, ped_top + 1),
			Vector2(cx + 9, ped_top - 6), Vector2(cx - 9, ped_top - 6)]), conc, 0.0, 0.5)
	for s in 2:
		var side := s * 2 - 1
		_line(Vector2(cx + side * 13, ped_top), Vector2(cx + side * int(rx * 0.55), cy + 2), col)
		_line(Vector2(cx + side * 12, ped_top), Vector2(cx + side * int(rx * 0.55) - side, cy + 2), col)
	# Back truss under the bowl.
	for k in 7:
		var a := float(k) / 6.0
		_line(Vector2(cx + (a - 0.5) * rx * 1.6, cy + ry * 0.4), Vector2(cx, ped_top - 6), col.lerp(HAZE, 0.2))
	# The bowl.
	var face := Color(0.6, 0.62, 0.64).lerp(HAZE, haze)
	var snow := SNOW.lerp(HAZE, haze * 0.6)
	var ca := cos(-tilt)
	var sa := sin(-tilt)
	for y in range(int(cy - rx - 2), int(cy + rx + 2)):
		for x in range(int(cx - rx - 2), int(cx + rx + 2)):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			var lx := dx * ca - dy * sa
			var ly := dx * sa + dy * ca
			var e := (lx * lx) / (rx * rx) + (ly * ly) / (ry * ry)
			if e > 1.0:
				continue
			if e > 0.8:
				_dot(x, y, METAL.lerp(HAZE, haze), signf(lx) * 0.4, 0.3)
				continue
			var up := 0.45 + 0.4 * (ly / ry)
			var fx := -lx / rx * 0.7
			var c := face
			var ring := absf(sqrt(e) - 0.55) < 0.035 or absf(sqrt(e) - 0.3) < 0.04
			var ang := fmod(atan2(ly / ry, lx / rx) + TAU, TAU / 12.0)
			if ring or ang < 0.06:
				c = face.darkened(0.2)
			var pool := (lx / rx) * (lx / rx) + pow((ly / ry - 0.25) / 0.55, 2.0)
			if pool < 0.42 + 0.06 * sin(lx * 0.7):
				c = snow
				up = 1.0
			_dot(x, y, c, fx, up)
	# Feed over the bowl, held by four legs.
	var focus := Vector2(cx + rx * 0.12, cy - rx * 0.78)
	for k in 4:
		var a := float(k) * PI * 0.5 + 0.4
		var rim := Vector2(cos(a) * rx * 0.9, sin(a) * ry * 0.9).rotated(tilt) + Vector2(cx, cy)
		_line(rim, focus, col)
	_fill(Rect2i(int(focus.x) - 2, int(focus.y) - 3, 4, 5), METAL.lerp(HAZE, haze), 0.0, 0.2)
	_fill(Rect2i(int(focus.x) - 2, int(focus.y) - 4, 4, 1), snow, 0.0, 1.0)
	_light(int(focus.x), int(focus.y) - 5, 0)
	var rim_top := Vector2(0.0, -ry).rotated(tilt) + Vector2(cx, cy)
	_light(int(cx - rx * 0.95), int(cy + rx * 0.17), 0)
	_light(int(rim_top.x), int(rim_top.y) - 1, 2)


## The roof we stand on: a snowed-over deck, a parapet with a drift heaped on it, an iced railing,
## a vent unit and a warning lamp.
func _roof() -> void:
	var top := 236
	_fill(Rect2i(0, top + 6, IMG_W, IMG_H - top - 6), SNOW, 0.0, 1.0)
	# Wind-carved ripples in the snow.
	for k in 260:
		var x := _rng.randi_range(-10, IMG_W)
		var y := _rng.randi_range(top + 8, IMG_H - 1)
		var run := _rng.randi_range(4, 16)
		_fill(Rect2i(x, y, run, 1), SNOW_DIM if _rng.randf() < 0.7 else SNOW.lightened(0.1), 0.0, 0.75)
	# Parapet, its face towards us, then the drift on its coping.
	_fill(Rect2i(0, top, IMG_W, 6), CONCRETE.darkened(0.4))
	_fill(Rect2i(0, top + 5, IMG_W, 1), CONCRETE.darkened(0.55), 0.0, 0.0, 0.7)
	for x in range(0, IMG_W, 13):
		_fill(Rect2i(x, top, 1, 6), CONCRETE.darkened(0.55))
	for x in IMG_W:
		var dh := int(2.5 + sin(x * 0.045) * 1.4 + sin(x * 0.13 + 1.7) * 0.9 + sin(x * 0.31) * 0.5)
		_fill(Rect2i(x, top - dh, 1, dh), SNOW, 0.0, 1.0)
		if (x * 7) % 5 == 0:
			_dot(x, top - dh, SNOW.lightened(0.15), 0.0, 1.0)
	# Railing: posts, two rails with rime and a few icicles.
	var rail := METAL_DARK
	for x in range(6, IMG_W, 26):
		_fill(Rect2i(x, top - 13, 1, 12), rail, 0.4)
	for ry in [top - 13, top - 7]:
		var yy: int = ry
		_fill(Rect2i(0, yy, IMG_W, 1), rail, 0.0, 0.3)
		for x in IMG_W:
			if _rng.randf() < 0.55:
				_dot(x, yy - 1, SNOW, 0.0, 1.0)
			if _rng.randf() < 0.05:
				for i in _rng.randi_range(1, 3):
					_dot(x, yy + 1 + i, ICE, 0.0, 0.3)
	# A vent unit on the left, a lamp post on the right.
	_box(170, 222, 214, 250, 0.1, METAL, 0.0, 0.0, 1)
	for y in range(226, 246, 2):
		_fill(Rect2i(174, y, 36, 1), METAL_DARK, 0.0, 0.0, 0.7)
	_fill(Rect2i(170, 221, 44, 1), SNOW, 0.0, 1.0)
	_fill(Rect2i(600, 196, 2, 50), METAL_DARK, 0.5)
	_fill(Rect2i(597, 194, 8, 3), METAL, 0.0, 0.4)
	_fill(Rect2i(597, 193, 8, 1), SNOW, 0.0, 1.0)
	_light(601, 197, 1)
	_light(198, 220, 0)


# --- Pixel helpers -----------------------------------------------------------------------------


func _fill(r: Rect2i, c: Color, fx: float = 0.0, up: float = 0.0, ao: float = 1.0) -> void:
	r = r.intersection(Rect2i(0, 0, IMG_W, IMG_H))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	c.a = 1.0
	_alb.fill_rect(r, c)
	_face.fill_rect(r, Color(fx * 0.5 + 0.5, up, ao))
	_emit.fill_rect(r, Color(0, 0, 0, 0))


func _dot(x: int, y: int, c: Color, fx: float = 0.0, up: float = 0.0, ao: float = 1.0) -> void:
	if x < 0 or y < 0 or x >= IMG_W or y >= IMG_H:
		return
	c.a = 1.0
	_alb.set_pixel(x, y, c)
	_face.set_pixel(x, y, Color(fx * 0.5 + 0.5, up, ao))
	_emit.set_pixel(x, y, Color(0, 0, 0, 0))


## A lit window or vent pixel: dark glass that glows on its own.
func _glow(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= IMG_W or y >= IMG_H:
		return
	_alb.set_pixel(x, y, GLASS)
	_face.set_pixel(x, y, Color(0.5, 0.0, 1.0))
	_emit.set_pixel(x, y, c)


## A one pixel line; every > 1 draws only every n-th pixel (for faint wires).
func _line(a: Vector2, b: Vector2, c: Color, every: int = 1) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in n + 1:
		if i % every != 0:
			continue
		var p := a.lerp(b, float(i) / float(maxi(n, 1)))
		_dot(int(floorf(p.x)), int(floorf(p.y)), c)


func _poly(pts: PackedVector2Array, c: Color, fx: float, up: float) -> void:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(int(floorf(lo.y)), int(ceilf(hi.y))):
		for x in range(int(floorf(lo.x)), int(ceilf(hi.x))):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_dot(x, y, c, fx, up)


func _light(x: int, y: int, kind: int) -> void:
	_lights.append(Vector3(x, y, kind))
