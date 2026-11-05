extends Control
## The SIRYN title over the main menu: five separate letters cut from heavy steel plate, each with
## an amber neon tube set into a groove down its strokes, like the rest of the complex's worn
## signage. They have been up there a long time: chipped edges, scratches, rust bleeding from the
## bolts, grime run down under the grooves, frost and snow.
##
## No two letters are alike. The S is patched with a welded plate over a crack. The I is old
## rusted iron with a tired, paler tube that wavers. The R is dark gunmetal with worn hazard
## stripes on its leg, a chunk broken off its bowl and a dead stretch of tube. The Y hangs a
## little low and crooked, its tube buzzing out and spitting sparks, a cut cable dangling from it.
## The N is crusted in ice, its glow dulled through the frost.
##
## Everything is painted once into images; per frame only the light levels and the particles
## change. The letters sit centred between the top of the screen and the menu's buttons.

const CW: int = 240
const CH: int = 80
## Scale of the letter designs, and where the letters' top left sits on the canvas.
const S: float = 1.25
const LX: float = 28.0
const LY: float = 12.0
const DESIGN_H: float = 40.0
const HALF_STROKE: float = 3.5
const WIDTHS: Array[int] = [24, 5, 24, 26, 24]
const GAP: int = 11
## Each letter's drop in canvas pixels, so they don't hang perfectly in line.
const DROPS: Array[int] = [0, -1, 1, 2, 0]
const FAULTY: int = 3
const WAVERY: int = 1
const HALO: Array[float] = [0.42, 0.24, 0.12, 0.05]

const TUBE := Color(1.0, 0.56, 0.14)
const TUBE_HOT := Color(1.0, 0.86, 0.55)
const TUBE_OLD := Color(1.0, 0.72, 0.42)
const TUBE_GHOST := Color(0.2, 0.11, 0.06)
const GROOVE := Color(0.025, 0.025, 0.03)
const STEEL := Color(0.2, 0.2, 0.21)
const STEEL_HI := Color(0.4, 0.39, 0.37)
const STEEL_LO := Color(0.07, 0.07, 0.08)
const GUNMETAL := Color(0.14, 0.15, 0.17)
const IRON := Color(0.24, 0.2, 0.18)
const RUST_COLORS: Array[Color] = [Color(0.36, 0.17, 0.08), Color(0.48, 0.24, 0.1),
		Color(0.26, 0.12, 0.06)]
const HAZARD := Color(0.6, 0.47, 0.12)
const RIVET := Color(0.46, 0.44, 0.4)
const WELD := Color(0.3, 0.27, 0.24)
const CABLE := Color(0.32, 0.08, 0.06)
const SNOW := Color(0.86, 0.91, 0.97)
const FROST := Color(0.78, 0.87, 0.94)
const ICE := Color(0.62, 0.77, 0.88)
const SPARK := Color(1.0, 0.75, 0.35)
const STRIKE: Array[float] = [0.7, 0.0, 0.0, 0.9, 0.15, 0.0, 1.0, 0.35, 1.0]
const STRIKE_STEP: float = 0.05

## Set by the main menu, so the title can centre itself above the buttons.
var menu: Control

var _body_tex: Array[ImageTexture] = []
var _lit_tex: Array[ImageTexture] = []
var _halo_tex: Array[ImageTexture] = []
var _reflect_tex: Array[ImageTexture] = []
var _glow: Control
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _levels: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
## How bright each tube burns at best: the I's is old, the N's is dulled by ice.
var _peak: Array[float] = [1.0, 0.8, 1.0, 1.0, 0.7]
var _strike_at: Array[float] = []
var _fault_left: float = 0.0
var _fault_wait: float = 2.5
var _brown_left: float = 0.0
var _brown_wait: float = 16.0
var _sparks: Array[Vector4] = []
var _spark_life: Array[Vector2] = []
var _blown: Array[Vector4] = []
var _tops: PackedVector2Array = PackedVector2Array()
var _glints: Array[Vector2i] = []
var _y_spark: Vector2
## The Y's cut cable: where it hangs from, and how long it is.
var _cable_at: Vector2
## Top and bottom of the painted letters on the canvas, for centring.
var _vis_top: int = CH
var _vis_bottom: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 5151
	_paint()
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	for i in WIDTHS.size():
		_strike_at.append(0.35 + i * 0.2 + _rng.randf_range(0.0, 0.12))


func _process(delta: float) -> void:
	_t += delta
	var screen := get_viewport_rect().size
	var below := screen.y * 0.48
	if menu != null and menu.has_method("stack_top"):
		below = float(menu.call("stack_top"))
	var vis_h := float(_vis_bottom - _vis_top)
	var top := roundf((below - vis_h) * 0.5)
	position = Vector2(floorf((screen.x - CW) * 0.5), top - _vis_top)
	_update_light(delta)
	_update_particles(delta)
	queue_redraw()
	_glow.queue_redraw()


func _update_light(delta: float) -> void:
	_fault_wait -= delta
	if _fault_left > 0.0:
		_fault_left -= delta
	elif _fault_wait <= 0.0:
		_fault_left = _rng.randf_range(0.08, 0.45)
		_fault_wait = _rng.randf_range(1.0, 4.5)
		_burst(_y_spark, _rng.randi_range(3, 7))
	_brown_wait -= delta
	if _brown_left > 0.0:
		_brown_left -= delta
	elif _brown_wait <= 0.0:
		_brown_left = _rng.randf_range(0.12, 0.28)
		_brown_wait = _rng.randf_range(14.0, 30.0)
	var hum := 0.94 + 0.06 * sin(_t * 31.0) * sin(_t * 2.7)
	var brown := 1.0
	if _brown_left > 0.0:
		brown = 0.25 if fmod(_brown_left, 0.08) < 0.05 else 0.6
	for i in _levels.size():
		var since := _t - _strike_at[i]
		var level := 0.0
		if since >= 0.0:
			var k := int(since / STRIKE_STEP)
			level = STRIKE[k] if k < STRIKE.size() else 1.0
		if i == FAULTY and _fault_left > 0.0 and since > 1.0:
			level *= 0.0 if fmod(_fault_left, 0.07) < 0.04 else 0.55
		if i == WAVERY:
			# A tired tube: slow, uneven breathing.
			level *= 0.82 + 0.18 * sin(_t * 1.3) * sin(_t * 0.47 + 1.0)
		_levels[i] = level * hum * brown * _peak[i]


func _burst(at: Vector2, n: int) -> void:
	for k in n:
		_sparks.append(Vector4(at.x, at.y, _rng.randf_range(-35.0, 35.0), _rng.randf_range(-45.0, 5.0)))
		_spark_life.append(Vector2(0.0, _rng.randf_range(0.25, 0.6)))


func _update_particles(delta: float) -> void:
	var i := 0
	while i < _sparks.size():
		var s := _sparks[i]
		var life := _spark_life[i]
		life.x += delta
		if life.x >= life.y:
			_sparks.remove_at(i)
			_spark_life.remove_at(i)
			continue
		s.w += 160.0 * delta
		s.x += s.z * delta
		s.y += s.w * delta
		_sparks[i] = s
		_spark_life[i] = life
		i += 1
	# Snow blown off the letters' tops by the wind.
	if not _tops.is_empty() and _rng.randf() < delta * 7.0:
		var p := _tops[_rng.randi_range(0, _tops.size() - 1)]
		_blown.append(Vector4(p.x, p.y - 1.0, _rng.randf_range(-120.0, -55.0), 0.0))
	i = 0
	while i < _blown.size():
		var b := _blown[i]
		b.w += delta
		b.x += b.z * delta
		b.y += (sin(b.w * 9.0 + b.x) * 9.0 + 4.0) * delta
		if b.w > 1.0:
			_blown.remove_at(i)
			continue
		_blown[i] = b
		i += 1


func _draw() -> void:
	# The Y's cut cable, swaying in the wind.
	var sway := sin(_t * 2.1) * 1.5 + sin(_t * 5.3) * 0.5
	for k in 9:
		var t := float(k) / 8.0
		draw_rect(Rect2(floorf(_cable_at.x + sway * t * t), _cable_at.y + k, 1, 1), CABLE)
	draw_rect(Rect2(floorf(_cable_at.x + sway) - 1, _cable_at.y + 9, 3, 1), Color(0.55, 0.36, 0.2))
	for i in _body_tex.size():
		draw_texture(_body_tex[i], Vector2.ZERO)
		var level := clampf(_levels[i], 0.0, 1.0)
		if level > 0.01:
			draw_texture(_lit_tex[i], Vector2.ZERO, Color(1, 1, 1, level))
			draw_texture(_reflect_tex[i], Vector2.ZERO, Color(1, 1, 1, level))
	for b in _blown:
		var c := SNOW
		c.a = 0.7 * (1.0 - b.w)
		draw_rect(Rect2(floorf(b.x), floorf(b.y), 2 if b.z < -95.0 else 1, 1), c)


## Additive layer: the tubes' glow, sparks and ice glints.
func _draw_glow() -> void:
	for i in _halo_tex.size():
		var level := clampf(_levels[i], 0.0, 1.0)
		if level > 0.01:
			_glow.draw_texture(_halo_tex[i], Vector2.ZERO, Color(1, 1, 1, level))
	for k in _sparks.size():
		var s := _sparks[k]
		var life := _spark_life[k]
		var c := SPARK.lerp(TUBE, life.x / life.y)
		c.a = 1.0 - life.x / life.y
		_glow.draw_rect(Rect2(floorf(s.x), floorf(s.y), 1, 1), c)
	for g in _glints:
		var a := pow(maxf(0.0, sin(_t * 1.7 + g.x * 0.37 + g.y * 0.91)), 12.0)
		if a > 0.05:
			_glow.draw_rect(Rect2(g.x, g.y, 1, 1), Color(0.7, 0.85, 1.0, a))


# --- Painting ----------------------------------------------------------------------------------


func _paint() -> void:
	var letters := _letters()
	for li in letters.size():
		var body := {}
		var core := {}
		for line in (letters[li] as Array):
			var pts: PackedVector2Array = line
			_fill_polys(Geometry2D.offset_polyline(pts, HALF_STROKE, Geometry2D.JOIN_MITER,
					Geometry2D.END_BUTT), body)
			_raster_line(pts, core)
		_paint_letter(li, body, core)


func _paint_letter(li: int, body: Dictionary, core: Dictionary) -> void:
	var x0 := LX + _letter_x(li) * S
	var x1 := x0 + WIDTHS[li] * S
	var top := LY + DROPS[li]
	var h := DESIGN_H * S
	# Wear first: chipped edges, and a chunk broken off the R's bowl.
	for px in body.keys():
		var q: Vector2i = px
		if _is_edge(body, q) and _rng.randf() < 0.07:
			body.erase(q)
	if li == 2:
		var chunk := Vector2i(int(x0 + 21.0 * S), int(top + 11.0 * S))
		for oy in range(-2, 3):
			for ox in range(0, 4 - absi(oy)):
				body.erase(chunk + Vector2i(ox, oy))
	# The groove the tube sits in, three pixels wide, kept inside the metal.
	var groove := {}
	for px in core.keys():
		var q: Vector2i = px
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var r := q + Vector2i(ox, oy)
				if body.has(r):
					groove[r] = true
	var img := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
	var reflect := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
	var lit := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
	var base: Color = [STEEL, IRON, GUNMETAL, STEEL.darkened(0.1), STEEL][li]
	for px in body.keys():
		var q: Vector2i = px
		_vis_top = mini(_vis_top, q.y)
		_vis_bottom = maxi(_vis_bottom, q.y + 1)
		var t := (float(q.y) - top) / h
		var n := _noise(q.x * 0.21 + li * 9.0, q.y * 0.21)
		var c := base.lerp(STEEL_HI, n * 0.25)
		# Brushed grain, darker towards the bottom.
		c = c.darkened(0.12 * t + 0.05 * float(hash(Vector2i(q.x / 3, q.y)) % 3))
		var rust := _noise(q.x * 0.17 + 31.0 + li * 5.0, q.y * 0.19) * 0.85 + t * 0.35
		var rust_line := 0.82 if li != 1 else 0.62
		if rust > rust_line:
			c = RUST_COLORS[int(rust * 9.0) % 3]
		if li == 2 and q.y > top + 22.0 * S and (q.x + q.y) / 3 % 2 == 0 and q.x > x0 + 9.0 * S:
			c = HAZARD.lerp(c, 0.35 if _noise(q.x * 0.4, q.y * 0.4) > 0.4 else 0.8)
		if _is_edge(body, q):
			if not body.has(q + Vector2i.UP) or not body.has(q + Vector2i.LEFT):
				c = c.lightened(0.3)
			else:
				c = STEEL_LO
		if groove.has(q):
			c = GROOVE
		elif _near(groove, q):
			var r := TUBE
			r.a = 0.32
			reflect.set_pixel(q.x, q.y, r)
		if li == 4 and q.y < top + h * 0.75 and _rng.randf() < 0.45 - t * 0.5:
			c = FROST.lerp(c, _rng.randf_range(0.0, 0.5))
		c.a = 1.0
		img.set_pixel(q.x, q.y, c)
	# Grime run down from the bottom of each groove, scratches across the plate.
	for px in groove.keys():
		var q: Vector2i = px
		if not groove.has(q + Vector2i.DOWN) and _rng.randf() < 0.3:
			for k in _rng.randi_range(2, 6):
				var r := q + Vector2i(0, 1 + k)
				if body.has(r) and not groove.has(r):
					img.set_pixel(r.x, r.y, img.get_pixel(r.x, r.y).darkened(0.35))
	for k in 4:
		var a := Vector2(_rng.randf_range(x0, x1), _rng.randf_range(top, top + h))
		var d := Vector2(_rng.randf_range(2.0, 6.0), _rng.randf_range(-2.0, 2.0))
		for j in int(d.length()):
			var p := (a + d.normalized() * j).floor()
			var r := Vector2i(int(p.x), int(p.y))
			if body.has(r) and not groove.has(r):
				img.set_pixel(r.x, r.y, STEEL_HI.darkened(0.15))
	# Bolts at the stroke ends, rust bleeding down from some.
	var bolts := _bolt_spots(li, x0, top)
	for b in bolts:
		var q := Vector2i(int(b.x), int(b.y))
		if body.has(q) and not groove.has(q):
			img.set_pixel(q.x, q.y, RIVET)
			if _rng.randf() < 0.6:
				for k in _rng.randi_range(2, 6):
					var r := q + Vector2i(0, k + 1)
					if body.has(r) and not groove.has(r):
						img.set_pixel(r.x, r.y, RUST_COLORS[k % 3])
	# The S's welded patch over a crack.
	if li == 0:
		var pr := Rect2i(int(x0 + 12.0 * S), int(top + 17.0 * S), 8, 6)
		for y in range(pr.position.y, pr.end.y):
			for x in range(pr.position.x, pr.end.x):
				var q := Vector2i(x, y)
				if not body.has(q) or groove.has(q):
					continue
				var edge := x == pr.position.x or y == pr.position.y or x == pr.end.x - 1 or y == pr.end.y - 1
				img.set_pixel(x, y, WELD.lightened(0.15) if edge and (x + y) % 2 == 0 else WELD.darkened(0.2))
		for k in 5:
			var q := Vector2i(pr.position.x - 1 - k, pr.position.y + 2 + k / 2)
			if body.has(q) and not groove.has(q):
				img.set_pixel(q.x, q.y, STEEL_LO)
	# The tube in its groove: hot where it runs straight, a dead stretch in the R's leg.
	var tube := {}
	var tube_col := TUBE_OLD if li == WAVERY else TUBE
	for px in core.keys():
		var q: Vector2i = px
		if not body.has(q):
			continue
		var dead := li == 2 and q.y > top + 28.0 * S and q.y < top + 34.0 * S and q.x > x0 + 14.0 * S
		img.set_pixel(q.x, q.y, TUBE_GHOST if not dead else TUBE_GHOST.darkened(0.4))
		if dead:
			continue
		tube[q] = true
		var straight := (core.has(q + Vector2i.LEFT) and core.has(q + Vector2i.RIGHT)) \
				or (core.has(q + Vector2i.UP) and core.has(q + Vector2i.DOWN))
		var c := TUBE_HOT if straight else tube_col
		if li == 4 and _rng.randf() < 0.4:
			c = c.lerp(FROST, 0.45)
		lit.set_pixel(q.x, q.y, c)
	# Snow on the top edges, icicles under the bottom ones (long under the frozen N).
	for px in body.keys():
		var q: Vector2i = px
		var above := q + Vector2i.UP
		if not body.has(above) and not body.has(above + Vector2i.UP) and _rng.randf() < 0.65:
			_put(img, above.x, above.y, SNOW)
			_tops.append(Vector2(above.x, above.y))
			_vis_top = mini(_vis_top, above.y)
			if _rng.randf() < 0.06:
				_glints.append(above)
		var below := q + Vector2i.DOWN
		if not body.has(below) and _rng.randf() < (0.16 if li == 4 else 0.06):
			var length := _rng.randi_range(1, 6 if li == 4 else 3)
			for k in length:
				_put(img, below.x, below.y + k, ICE.lerp(FROST, float(k) / float(length)))
	if li == FAULTY:
		_y_spark = Vector2(x0 + 13.0 * S, top + 30.0 * S)
		_cable_at = Vector2(x0 + 13.0 * S + 2.0, float(_bottom_of(body, int(x0 + 13.0 * S + 2.0))))
	_body_tex.append(ImageTexture.create_from_image(img))
	_lit_tex.append(ImageTexture.create_from_image(lit))
	_reflect_tex.append(ImageTexture.create_from_image(reflect))
	_halo_tex.append(ImageTexture.create_from_image(_halo(tube, tube_col)))


func _bolt_spots(li: int, x0: float, top: float) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var raw: Array = [
		[Vector2(21, 2.5), Vector2(3, 37.5)],
		[Vector2(2.5, 3), Vector2(2.5, 37)],
		[Vector2(2.5, 37), Vector2(2.5, 4.5), Vector2(19.5, 37)],
		[Vector2(4, 2), Vector2(22, 2), Vector2(13, 37)],
		[Vector2(2.5, 37), Vector2(21.5, 3)],
	][li]
	for v in raw:
		var p: Vector2 = v
		# Off the groove, beside the stroke's centre line.
		spots.append(Vector2(x0 + p.x * S + 2.0, top + p.y * S))
	return spots


func _bottom_of(body: Dictionary, x: int) -> int:
	var y := CH - 1
	while y > 0 and not body.has(Vector2i(x, y)):
		y -= 1
	return y + 1


func _letter_x(index: int) -> float:
	var x := 0.0
	for k in index:
		x += WIDTHS[k] + GAP
	return x


## Each letter's stroke centre lines, in design units (40 tall) from its own left. Straight
## strokes with 45 degree chamfers.
func _letters() -> Array:
	var raw := [
		[[Vector2(24, 2.5), Vector2(7, 2.5), Vector2(2.5, 7), Vector2(2.5, 15.5), Vector2(7, 20),
				Vector2(17, 20), Vector2(21.5, 24.5), Vector2(21.5, 33), Vector2(17, 37.5),
				Vector2(0, 37.5)]],
		[[Vector2(2.5, 0), Vector2(2.5, 40)]],
		[[Vector2(2.5, 40), Vector2(2.5, 2.5), Vector2(17, 2.5), Vector2(21.5, 7), Vector2(21.5, 15.5),
				Vector2(17, 20), Vector2(2.5, 20)],
				[Vector2(11, 20), Vector2(21.5, 40)]],
		[[Vector2(2, 0), Vector2(13, 18)], [Vector2(24, 0), Vector2(13, 18)],
				[Vector2(13, 15), Vector2(13, 40)]],
		[[Vector2(2.5, 40), Vector2(2.5, 2), Vector2(21.5, 38), Vector2(21.5, 0)]],
	]
	var out: Array = []
	for li in raw.size():
		var ox := _letter_x(li)
		var lines: Array = []
		for line in (raw[li] as Array):
			var pts := PackedVector2Array()
			for v in (line as Array):
				var p: Vector2 = v
				pts.append(Vector2(LX + (ox + p.x) * S, LY + DROPS[li] + p.y * S))
			lines.append(pts)
		out.append(lines)
	return out


func _fill_polys(polys: Array[PackedVector2Array], into: Dictionary) -> void:
	for poly in polys:
		var lo := poly[0]
		var hi := poly[0]
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		for y in range(int(floorf(lo.y)), int(ceilf(hi.y))):
			for x in range(int(floorf(lo.x)), int(ceilf(hi.x))):
				if x >= 0 and y >= 0 and x < CW and y < CH \
						and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
					into[Vector2i(x, y)] = true


## A one pixel centre line.
func _raster_line(line: PackedVector2Array, into: Dictionary) -> void:
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var n := int(ceilf(a.distance_to(b) * 2.0))
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(maxi(n, 1)))
			into[Vector2i(int(floorf(p.x)), int(floorf(p.y)))] = true


func _is_edge(body: Dictionary, q: Vector2i) -> bool:
	return not (body.has(q + Vector2i.UP) and body.has(q + Vector2i.DOWN)
			and body.has(q + Vector2i.LEFT) and body.has(q + Vector2i.RIGHT))


func _near(pixels: Dictionary, q: Vector2i) -> bool:
	return pixels.has(q + Vector2i.UP) or pixels.has(q + Vector2i.DOWN) or pixels.has(q + Vector2i.LEFT) \
			or pixels.has(q + Vector2i.RIGHT)


## The glow around a tube: rings of falling brightness.
func _halo(tube: Dictionary, col: Color) -> Image:
	var img := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
	var seen := tube.duplicate()
	var frontier: Array = tube.keys()
	for ring in HALO.size():
		var next: Array = []
		for px in frontier:
			var q: Vector2i = px
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var r: Vector2i = q + d
				if not seen.has(r):
					seen[r] = true
					next.append(r)
		for px in next:
			var q: Vector2i = px
			var c := col
			c.a = HALO[ring]
			_put(img, q.x, q.y, c)
		frontier = next
	for px in tube.keys():
		var q: Vector2i = px
		var c := col
		c.a = 0.3
		_put(img, q.x, q.y, c)
	return img


func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < CW and y < CH:
		img.set_pixel(x, y, c)


func _noise(x: float, y: float) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_h(ix, iy), _h(ix + 1, iy), fx), lerpf(_h(ix, iy + 1), _h(ix + 1, iy + 1), fx), fy)


func _h(x: int, y: int) -> float:
	return float(hash(Vector2i(x, y)) % 1000) / 1000.0
