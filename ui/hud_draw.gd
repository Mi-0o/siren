class_name HudDraw
extends RefCounted
## Shared drawing helpers for the HUD, so every panel has the same grimy, chamfered metal look
## and the same 3x5 pixel font. Everything is drawn at native pixel scale.

const PLATE_COLOR := Color(0.11, 0.11, 0.13)
const PLATE_LIGHT := Color(0.24, 0.23, 0.24)
const PLATE_SHADOW := Color(0.04, 0.04, 0.05)
const GRIME_COLORS: Array[Color] = [
	Color(0.07, 0.07, 0.08), Color(0.2, 0.12, 0.07), Color(0.16, 0.16, 0.17)
]
const RIVET_COLOR := Color(0.32, 0.3, 0.29)
## How far the top right and bottom left corners are cut off, in pixels.
const CHAMFER: int = 4
## Glyph size in pixels; glyphs sit one pixel apart.
const GLYPH_HEIGHT: int = 5
## 3x5 glyphs, one string per row. The colon is one pixel wide.
const GLYPHS: Dictionary = {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "011", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
	":": ["0", "1", "0", "1", "0"],
	"C": ["111", "100", "100", "100", "111"],
	"G": ["111", "100", "101", "101", "111"],
	"H": ["101", "101", "111", "101", "101"],
}


## The plate outline for a panel of the given size, clockwise from the top left.
static func plate_polygon(size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, 0),
		Vector2(size.x - CHAMFER, 0),
		Vector2(size.x, CHAMFER),
		Vector2(size.x, size.y),
		Vector2(CHAMFER, size.y),
		Vector2(0, size.y - CHAMFER),
	])


## Draws a panel's metal plate with its edge lighting, then the grime from roll_grime() and a
## rivet at each given point.
static func draw_plate(canvas: CanvasItem, size: Vector2, grime: Array, rivets: Array) -> void:
	canvas.draw_colored_polygon(plate_polygon(size), PLATE_COLOR)
	canvas.draw_rect(Rect2(1, 0, size.x - CHAMFER - 1, 1), PLATE_LIGHT)
	canvas.draw_rect(Rect2(0, 1, 1, size.y - CHAMFER - 1), PLATE_LIGHT)
	canvas.draw_rect(Rect2(CHAMFER, size.y - 1, size.x - CHAMFER, 1), PLATE_SHADOW)
	canvas.draw_rect(Rect2(size.x - 1, CHAMFER, 1, size.y - CHAMFER - 1), PLATE_SHADOW)
	for g in grime:
		canvas.draw_rect(Rect2(g[0], Vector2.ONE), g[1])
	for r in rivets:
		canvas.draw_rect(Rect2(r, Vector2.ONE), RIVET_COLOR)


## Rolls count grime pixels inside a plate of the given size, avoiding the keep_clear rects.
## Returns [position, colour] pairs. A fixed seed keeps the grit from crawling between runs.
static func roll_grime(size: Vector2, rng_seed: int, count: int, keep_clear: Array[Rect2]) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var polygon := plate_polygon(size)
	var grime: Array = []
	var tries := 0
	while grime.size() < count and tries < count * 50:
		tries += 1
		var p := Vector2(rng.randi_range(1, int(size.x) - 2), rng.randi_range(1, int(size.y) - 2))
		if not Geometry2D.is_point_in_polygon(p, polygon):
			continue
		if keep_clear.any(func(r: Rect2) -> bool: return r.has_point(p)):
			continue
		grime.append([p, GRIME_COLORS[rng.randi_range(0, GRIME_COLORS.size() - 1)]])
	return grime


## Draws text in the 3x5 font with its top left at pos. Unknown characters leave a gap.
static func draw_text(canvas: CanvasItem, text: String, pos: Vector2, color: Color) -> void:
	var x := pos.x
	for c in text:
		var rows: Array = GLYPHS.get(c, ["000", "000", "000", "000", "000"])
		draw_glyph(canvas, rows, Vector2(x, pos.y), color)
		x += rows[0].length() + 1


## Width of text in the 3x5 font, in pixels.
static func text_width(text: String) -> int:
	var width := 0
	for c in text:
		var rows: Array = GLYPHS.get(c, ["000"])
		width += rows[0].length() + 1
	return maxi(width - 1, 0)


## Draws a glyph given as rows of "0"/"1" (any other character is blank too) at pos.
static func draw_glyph(canvas: CanvasItem, rows: Array, pos: Vector2, color: Color) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "1":
				canvas.draw_rect(Rect2(pos + Vector2(x, y), Vector2.ONE), color)
