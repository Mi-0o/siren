class_name PauseMenu
extends Control
## The pause menu, which deliberately does NOT pause the game. Esc (or Start on a pad) shoves four
## neon buttons in from the right edge on pneumatic rods, and lowers a "GAME IS NOT PAUSED" neon
## sign from the top edge on two struts. The world keeps running the whole time; the robot just
## stops taking controls and idles. Up and down pick a button (it's pushed out further and glows
## harder), A or Enter confirms. CONTINUE closes the menu. LOAD STATION and SETTINGS pull the
## buttons back out and push a tall display in from the same edge instead (the save list, and an
## settings categories). The BACK button in a display's top
## right corner, Esc or Backspace step back a screen at a time until the buttons return.
## EXIT isn't wired yet: it faults and fizzes.
##
## The load display shows the nine save slots three at a time, with a page row (left button,
## page number, right button) under them; left and right turn the page. Confirming a filled slot
## offers LOAD or DELETE (delete asks twice). Save stations call open_save(), which pushes the
## same display in as SAVE STATION without the buttons or the sign: confirming a slot saves
## there (a filled one asks before it overwrites) and makes it the active slot. Slots live in
## save/save_slots.gd.
##
## Everything moves on MechTrack step scripts instead of tweens: short shoves, stalls that
## judder, slips, overshoots and hard stops, re-rolled a little on every open so the hardware
## never behaves quite the same twice. Steam vents where a movement ends, the neon strikes on
## with a stutter once a part has locked in place, and the selected button and the sign spit a
## few faint sparks.
##
## Settings live in GameSettings and save on every change. Left and right change the highlighted
## option; confirming a control waits for the new key (Esc cancels). The pause menu also owns the
## brightness overlay and, with dev mode on, the red "DEV MODE ENABLED" sign in the top right,
## which stays up while the menu is closed.
##
## Drawn entirely in code at native pixel scale, like the HUD. The menu's own input actions are
## added at startup when the project doesn't define them, so they can be remapped in the Input
## Map later without touching this script.

signal opened
signal closed

## What each button does.
enum Action { CONTINUE, LOAD_STATION, SETTINGS, EXIT }
## Which display, if any, has replaced the buttons.
enum Mode { BUTTONS, LOAD, SETTINGS, SAVE, NEW_GAME, EXIT }

const LABELS: Array[String] = ["CONTINUE", "LOAD STATION", "SETTINGS", "EXIT"]
## The buttons once the robot is dead (open_death): back to the last save station, pick a save,
## or leave for the main menu.
const DEATH_LABELS: Array[String] = ["LAST STATION", "LOAD SAVE", "MAIN MENU"]
enum DeathAction { LAST_STATION, LOAD_SAVE, MAIN_MENU }

## 5x7 neon tube glyphs, one string per row ("#" = tube). I is narrower.
const GLYPHS: Dictionary = {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"G": [".####", "#....", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	"-": ["....", "....", "....", "####", "....", "....", "...."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
	">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
	"%": ["##..#", "##.#.", "...#.", "..#..", ".#...", ".#.##", "#..##"],
	"/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
	".": [".", ".", ".", ".", ".", ".", "#"],
	":": [".", ".", "#", ".", ".", "#", "."],
	"'": ["#", "#", ".", ".", ".", ".", "."],
}
## Small 3x5 phosphor glyphs for the displays' rows. Digits match the HUD clock.
const SMALL_GLYPHS: Dictionary = {
	"0": ["###", "#.#", "#.#", "#.#", "###"],
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###", "..#", "###", "#..", "###"],
	"3": ["###", "..#", ".##", "..#", "###"],
	"4": ["#.#", "#.#", "###", "..#", "..#"],
	"5": ["###", "#..", "###", "..#", "###"],
	"6": ["###", "#..", "###", "#.#", "###"],
	"7": ["###", "..#", ".#.", ".#.", ".#."],
	"8": ["###", "#.#", "###", "#.#", "###"],
	"9": ["###", "#.#", "###", "..#", "###"],
	":": [".", "#", ".", "#", "."],
	".": [".", ".", ".", ".", "#"],
	",": [".", ".", ".", "#", "#"],
	"'": ["#", "#", ".", ".", "."],
	"-": ["...", "...", "###", "...", "..."],
	"+": ["...", ".#.", "###", ".#.", "..."],
	"/": ["..#", "..#", ".#.", "#..", "#.."],
	"%": ["#.#", "..#", ".#.", "#..", "#.#"],
	"?": ["###", "..#", ".##", "...", ".#."],
	"<": ["..#", ".#.", "#..", ".#.", "..#"],
	">": ["#..", ".#.", "..#", ".#.", "#.."],
	"A": ["###", "#.#", "###", "#.#", "#.#"],
	"B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": ["###", "#..", "#..", "#..", "###"],
	"D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"],
	"F": ["###", "#..", "##.", "#..", "#.."],
	"G": ["###", "#..", "#.#", "#.#", "###"],
	"H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"J": ["..#", "..#", "..#", "#.#", "###"],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"],
	"L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
	"N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
	"O": ["###", "#.#", "#.#", "#.#", "###"],
	"P": ["###", "#.#", "###", "#..", "#.."],
	"Q": ["###", "#.#", "#.#", "###", "..#"],
	"R": ["###", "#.#", "##.", "#.#", "#.#"],
	"S": ["###", "#..", "###", "..#", "###"],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"W": ["#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"Z": ["###", "..#", ".#.", "#..", "###"],
}
const SPACE_W: int = 3
## Preloaded rather than named by class, so it works before the editor's class cache catches up.
const DEV_MENU_SCRIPT := preload("res://ui/dev_menu.gd")
const DEATH_WATCH_SCRIPT := preload("res://ui/death_watch.gd")
const SAVE_SLOTS := preload("res://save/save_slots.gd")

## Where EXIT goes once confirmed.
const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
## Seconds the exit screen glitches out before the main menu takes over.
const EXIT_DELAY: float = 0.35

# --- Ice -------------------------------------------------------------------------------------
# Europa is cold. The in-game menu only carries a light crust: frost on the top edges, short
# icicles, frosted glass corners and the odd chip shaken loose. The main menu lays it on thicker.
const FROST := Color(0.86, 0.93, 0.98)
const ICE := Color(0.64, 0.79, 0.89)
const ICE_DEEP := Color(0.4, 0.52, 0.62)
## How much ice the in-game menu carries (1.0 is the main menu's heaviest plaque).
const MENU_FROST: float = 0.45

# --- Buttons ---------------------------------------------------------------------------------
const PLAQUE_SIZE := Vector2i(92, 15)
const HALF_PLAQUE_H: int = 7
## Gap between the rested plaque's back and the screen's right edge, where the rod shows.
const RIGHT_MARGIN: int = 12
const BUTTON_STEP: int = 20
## Where the button stack is centred, as a fraction of the screen height (a bit above middle).
const STACK_CENTER: float = 0.42
## How much further the selected button is pushed out, in pixels.
const SELECT_PUSH: int = 8
## How far the left corners are cut, so the plaque points into the screen.
const PLAQUE_CHAMFER: int = 4
const TEXT_X: int = 13
const BUTTON_RIVETS: Array = [Vector2i(85, 2), Vector2i(85, 12)]
const PLAQUE_COLOR := Color(0.12, 0.115, 0.12)
const PLAQUE_LIGHT := Color(0.27, 0.25, 0.24)
const PLAQUE_SHADOW := Color(0.035, 0.035, 0.045)
const RUST_COLORS: Array[Color] = [
	Color(0.24, 0.12, 0.06), Color(0.17, 0.09, 0.05), Color(0.07, 0.07, 0.08),
	Color(0.19, 0.18, 0.18),
]
const CHANNEL_COLOR := Color(0.025, 0.03, 0.04)
const BUTTON_TUBE := Color(0.42, 0.92, 1.0)
const BUTTON_CORE := Color(0.85, 1.0, 1.0)
const BUTTON_GHOST := Color(0.1, 0.16, 0.19)
const LAMP_OFF := Color(0.22, 0.08, 0.04)
const LAMP_ON := Color(1.0, 0.62, 0.15)
const ROD_COLORS: Array[Color] = [
	Color(0.55, 0.54, 0.52), Color(0.33, 0.32, 0.32), Color(0.13, 0.13, 0.14)
]

# --- Sign ------------------------------------------------------------------------------------
const SIGN_TEXT: String = "GAME IS NOT PAUSED"
## Each tube pixel of the sign is this many screen pixels. 1 keeps it a small reminder notice.
const SIGN_SCALE: int = 1
const SIGN_LETTER_GAP: int = 1
const SIGN_WORD_GAP: int = 4
const SIGN_PAD := Vector2i(5, 3)
const SIGN_SHOWN_Y: int = 9
const SIGN_TUBE := Color(1.0, 0.56, 0.14)
const SIGN_CORE := Color(1.0, 0.86, 0.55)
const SIGN_GHOST := Color(0.2, 0.11, 0.07)
const TRUSS_DARK := Color(0.09, 0.085, 0.09)
const TRUSS_MID := Color(0.19, 0.18, 0.18)
const TRUSS_LIGHT := Color(0.32, 0.3, 0.28)
const STRUT_INSET: int = 14
const CABLE_COLOR := Color(0.32, 0.08, 0.06)

# --- Displays (save list, settings) ---------------------------------------------------------
const PANEL_TITLES: Array[String] = [
	"LOAD STATION", "SETTINGS", "SAVE STATION", "NEW GAME", "EXIT",
]
## Tall but narrow, so most of the screen stays in view.
const PANEL_SIZE := Vector2i(148, 176)
const PANEL_CHAMFER: int = 6
## The recessed screen inside the housing, in housing coordinates.
const PANEL_SCREEN := Rect2i(10, 20, 130, 148)
## Heights of the two rods that push the housing, in housing coordinates.
const PANEL_ROD_YS: Array[int] = [30, 146]
const PANEL_RIVETS: Array = [
	Vector2i(8, 3), Vector2i(140, 3), Vector2i(140, 172), Vector2i(8, 172), Vector2i(3, 88)
]
const ROW_H: int = 16
## Save slot boxes on the load and save screens: first one's top below the screen's top, their
## height and the gap between them. The page row sits under the third.
const SLOT_TOP: int = 3
const SLOT_H: int = 37
const SLOT_GAP: int = 3
const PAGE_ROW_Y: int = 126
const PAGE_BUTTON := Vector2i(17, 13)
## How long a fresh save's SAVED tag blinks.
const SAVED_TIME: float = 1.6
const SCREEN_BG := Color(0.02, 0.035, 0.04)
const PHOSPHOR := Color(0.5, 0.88, 0.92)
const PHOSPHOR_CORE := Color(0.82, 1.0, 1.0)
const PHOSPHOR_DIM := Color(0.16, 0.3, 0.33)
const ROW_SELECT := Color(0.06, 0.17, 0.19)
## The BACK button in the top right of each display, in housing coordinates.
const BACK_RECT := Rect2i(114, 3, 29, 13)
const SETTINGS_CATEGORIES: Array[String] = [
	"GRAPHICS", "AUDIO", "CONTROLS", "GAMEPLAY", "ACCESSIBILITY"
]
## Where the settings rows start below the screen's top.
const SETTINGS_TOP: int = 4
## Option rows on a settings page: where they start below the screen's top, and their height.
const OPTION_TOP: int = 19
const OPTION_H: int = 11
const SLIDER_W: int = 40
## How much left or right moves a slider.
const SLIDER_STEP: float = 0.05
const DEV_TUBE := Color(1.0, 0.16, 0.12)
const DEV_CORE := Color(1.0, 0.7, 0.62)
const DEV_GHOST := Color(0.22, 0.05, 0.04)
const BRIGHTNESS_SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float gamma = 1.0;
// Colorblind correction: 0 off, 1 protanopia, 2 deuteranopia, 3 tritanopia.
uniform int colorblind = 0;
uniform float strength = 1.0;

// Daltonization: simulate what the eye sees in LMS space, then push the colour difference it
// misses into channels it can still tell apart.
vec3 daltonize(vec3 c) {
	float l = 17.8824 * c.r + 43.5161 * c.g + 4.11935 * c.b;
	float m = 3.45565 * c.r + 27.1554 * c.g + 3.86714 * c.b;
	float s = 0.0299566 * c.r + 0.184309 * c.g + 1.46709 * c.b;
	if (colorblind == 1) {
		l = 2.02344 * m - 2.52581 * s;
	} else if (colorblind == 2) {
		m = 0.494207 * l + 1.24827 * s;
	} else {
		s = -0.395913 * l + 0.801109 * m;
	}
	vec3 seen = vec3(
		0.0809444479 * l - 0.130504409 * m + 0.116721066 * s,
		-0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s,
		-0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s
	);
	vec3 err = c - seen;
	vec3 shift = vec3(0.0, err.r * 0.7 + err.g, err.r * 0.7 + err.b);
	return clamp(c + shift * strength, 0.0, 1.0);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (colorblind > 0) {
		c = daltonize(c);
	}
	COLOR = vec4(pow(c, vec3(gamma)), 1.0);
}
"""
## Reset symbol on each controls row: an arrow going round, small and big font sizes.
const RESET_ICON: Array[String] = [".##.#", "#..##", "#.###", "#...#", ".###."]
const RESET_ICON_BIG: Array[String] = [
	"..##..#", ".#..###", "#...###", "#.....#", "#.....#", ".#...#.", "..###..",
]
## Colorblind preview swatches: integrity green, yellow, orange, fault red, amber, neon cyan.
const PREVIEW_COLORS: Array[Color] = [
	Color(0.25, 0.95, 0.45), Color(1.0, 0.84, 0.22), Color(1.0, 0.52, 0.1),
	Color(1.0, 0.12, 0.09), Color(1.0, 0.62, 0.15), Color(0.5, 0.88, 0.92),
]
## How long the glass scrambles when it changes screen.
const GLITCH_TIME: float = 0.14

# --- Steam and sparks ------------------------------------------------------------------------
const STEAM_COLOR := Color(0.78, 0.8, 0.82)
const SPARK_COLORS: Array[Color] = [
	Color(1.0, 0.97, 0.8, 0.85), Color(1.0, 0.75, 0.35, 0.7), Color(0.85, 0.35, 0.1, 0.5)
]
## Neon strike-up pattern, one entry per STRIKE_STEP seconds: a few stuttering tries, then on.
const STRIKE_PATTERN: Array[float] = [0.0, 0.7, 0.0, 0.0, 1.0, 0.3, 0.0, 1.0, 0.8, 1.0]
const STRIKE_STEP: float = 0.03
const SHUTOFF_PATTERN: Array[float] = [0.6, 0.0, 0.8, 0.0]

## The robot that stops taking controls while the menu is out.
@export var player: Player
## Seconds between one button starting its shove and the next.
@export var button_stagger: float = 0.07
## Seconds between faint sparks on the selected button and the sign, at random in this range.
@export var spark_interval: Vector2 = Vector2(0.25, 1.1)
## The HUD clock (its europa_minutes is saved and loaded). A sibling named StatusPanel is used
## if this is left empty.
@export var status_panel: Control

## True from the moment the menu is called until CONTINUE (or Esc) sends it back.
var is_open: bool = false
var selected: int = 0

var _buttons: Array[Dictionary] = []
var _sign := MechTrack.new()
var _sign_light := NeonLight.new()
var _sign_letters: Array[Dictionary] = []
var _sign_text_size := Vector2i.ZERO
## Letter whose tube is failing this time round; it drops out now and then.
var _faulty_letter: int = -1
var _fault_left: float = 0.0
var _fault_wait: float = 1.0
var _time: float = 0.0
var _shake_seed: int = 0
var _shake_clock: float = 0.0
var _rng := RandomNumberGenerator.new()
var _steam: Array[Dictionary] = []
var _sparks := PixelSparks.new()
## Ice chips shaken off the plaques, the sign and the displays.
var _ice := PixelSparks.new()
var _ice_wait: float = 2.0
var _sign_frost: Array = []
var _sign_icicles: Array = []
var _panel_frost: Array = []
var _panel_icicles: Array = []
var _button_spark_wait: float = 0.5
var _sign_spark_wait: float = 0.8
var _panel_spark_wait: float = 1.0
var _mode: Mode = Mode.BUTTONS
## The displays: index 0 is the load screen, 1 settings, 2 the save screen.
var _panels: Array[Dictionary] = []
## What's highlighted on the current display: a row, or -1 for its BACK button.
var _focus: int = 0
## Settings category whose page is open, or -1 for the category list.
var _settings_page: int = -1
## First option row shown, when a page has more rows than fit on the glass.
var _option_scroll: int = 0
## On a controls row: 0 the key itself, 1 its reset symbol.
var _option_col: int = 0
var _category_rows: Array[Dictionary] = []
var _back_text: Dictionary
var _back_press := MechTrack.new()
var _glitch_left: float = 0.0
## Physics frame from which the robot gets its controls back, or -1. Waiting a frame or two
## keeps a Z press that confirmed CONTINUE from also reaching the robot as a jump.
var _unlock_frame: int = -1
## Page of save slots shown, 0 to 2.
var _slot_page: int = 0
## Presses of the page row's left and right buttons.
var _page_press: Array[MechTrack] = [MechTrack.new(), MechTrack.new()]
var _page_texts: Array[Dictionary] = []
var _arrow_texts: Array[Dictionary] = []
## The choice box over a slot: the slot, the highlighted choice (0 left, 1 right) and whether a
## delete is waiting for its second press. Empty when there's no box up.
var _slot_box: Dictionary = {}
## Area and station of the save station that opened the save screen.
var _save_info: Dictionary = {}
var _saved_left: float = 0.0
var _saved_slot: int = -1
## Highlighted choice on the exit screen: 0 CANCEL, 1 EXIT.
var _exit_choice: int = 0
## True once EXIT is confirmed, while the screen dies before the main menu loads.
var _exiting: bool = false
## Set by open_death: the robot is dead and the menu shows the death sign and buttons. It can't be
## closed, only left by reloading or quitting, and the game still runs underneath.
var _dead: bool = false
## How far the death screen's darkening has come in, 0 to 1.
var _death_fade: float = 0.0
var _sign_tube: Color = SIGN_TUBE
var _sign_core: Color = SIGN_CORE
var _sign_ghost: Color = SIGN_GHOST
## Display layout. The main menu sets bigger ones before its _ready runs.
var panel_size: Vector2i = PANEL_SIZE
var panel_screen: Rect2i = PANEL_SCREEN
var back_rect: Rect2i = BACK_RECT
var slot_top: int = SLOT_TOP
var slot_h: int = SLOT_H
var slot_gap: int = SLOT_GAP
var page_row_y: int = PAGE_ROW_Y
var settings_row_h: int = ROW_H
var option_top: int = OPTION_TOP
var option_h: int = OPTION_H
var slider_w: int = SLIDER_W
## Settings rows in the big 5x7 font instead of the small one.
var settings_big: bool = false
## Option rows for each settings category, built in _ready.
var _pages: Array[Array] = []
## Controls row waiting for a key, or -1.
var _capturing: int = -1
## A key that's already taken, waiting for the player to pick REVERT or SWAP: the action being
## bound, the action that has the key, the key, and the highlighted choice (0 revert, 1 swap).
## Empty when there's no warning up.
var _conflict: Dictionary = {}
## Prepared text by font and string, for text that changes (values, key names).
var _text_cache: Dictionary = {}
## False while everything is put away; the dev sign still draws then.
var _active: bool = false
var _dev_text: Dictionary
var _dev_light := NeonLight.new()
var _dev_was_on: bool = false
var _brightness_rect: ColorRect


func _ready() -> void:
	add_to_group("pause_menu")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_ensure_actions()
	GameSettings.load_and_apply()
	_make_brightness_overlay()
	_build_pages()
	_dev_text = _build_text("DEV MODE ENABLED", 1, 1, SMALL_GLYPHS)
	# The dev tools panel (key left of 1, dev mode only) lives under the menu.
	var dev_menu: Control = DEV_MENU_SCRIPT.new()
	dev_menu.set("player", player)
	dev_menu.set("font", SMALL_GLYPHS)
	add_child(dev_menu)
	_sparks.colors = SPARK_COLORS
	_sparks.gravity = 220.0
	_sparks.damping = 0.2
	_ice.colors = [FROST, ICE, ICE_DEEP]
	_ice.gravity = 140.0
	_ice.damping = 0.5
	_buttons = _make_buttons(LABELS)
	_build_sign()
	for i in PANEL_TITLES.size():
		_panel_frost.append(_roll_edge_frost(panel_size.x - PANEL_CHAMFER - 4, 331 + i,
				MENU_FROST))
		_panel_icicles.append(_roll_icicles(panel_size.x - 10, 341 + i, MENU_FROST))
		_panels.append({
			"title": _build_text(PANEL_TITLES[i], 1, 2),
			"track": MechTrack.new(),
			"light": NeonLight.new(),
			"grime": _roll_panel_grime(301 + i * 17),
		})
	_back_text = _build_text("BACK", 1, 2)
	for i in SETTINGS_CATEGORIES.size():
		_category_rows.append({
			"number": _build_text("%02d" % (i + 1), 1, 1, SMALL_GLYPHS),
			"name": _build_text(SETTINGS_CATEGORIES[i], 1, 2),
		})
	for i in SAVE_SLOTS.PAGE_COUNT:
		_page_texts.append(_build_text(str(i + 1), 2, 1, SMALL_GLYPHS))
	_arrow_texts = [_build_text("<", 2, 1, SMALL_GLYPHS), _build_text(">", 2, 1, SMALL_GLYPHS)]
	# The death watch (robot's core faults or it falls out of the level) lives under the menu too.
	if player != null:
		var watch: Node = DEATH_WATCH_SCRIPT.new()
		watch.set("player", player)
		watch.set("menu", self)
		watch.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(watch)
	# A save picked in the main menu is waiting for this scene: put the robot back as saved.
	if not SAVE_SLOTS.pending_load.is_empty():
		var pending: Dictionary = SAVE_SLOTS.pending_load
		SAVE_SLOTS.pending_load = {}
		_apply_pending.call_deferred(pending)


func _unhandled_input(event: InputEvent) -> void:
	if _exiting:
		# On the way out to the main menu: nothing else gets a say.
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	if not _conflict.is_empty():
		_conflict_input(event)
		return
	if _capturing >= 0:
		_capture_key(event)
		return
	if not _slot_box.is_empty():
		_slot_box_input(event)
		return
	if event.is_action_pressed("pause_menu"):
		if not is_open:
			open()
		elif _mode != Mode.BUTTONS:
			_go_back()
		elif not _dead:
			close()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event.is_action_pressed("menu_back"):
		if _mode != Mode.BUTTONS:
			_go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_up", true):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down", true):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_left", true):
		_adjust(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right", true):
		_adjust(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		if _mode == Mode.BUTTONS:
			_confirm()
		else:
			_panel_confirm()
		get_viewport().set_input_as_handled()


## Shoves the buttons in and lowers the sign. The game keeps running.
func open() -> void:
	if is_open:
		return
	is_open = true
	_active = true
	_unlock_frame = -1
	if player != null:
		player.controls_locked = true
	selected = Action.CONTINUE
	_mode = Mode.BUTTONS
	_faulty_letter = _rng.randi_range(0, _sign_letters.size() - 1)
	_fault_wait = _rng.randf_range(0.8, 2.5)
	for i in _buttons.size():
		var b := _buttons[i]
		var select_track: MechTrack = b.select
		select_track.snap(1.0 if i == selected else 0.0)
		(b.track as MechTrack).play(_button_open_steps(i))
		(b.light as NeonLight).snap_off()
	_sign.play(_sign_open_steps())
	_sign_light.snap_off()
	opened.emit()


## Pushes the save screen in on its own (no buttons, no sign), for the save station whose area
## and station are in info. The game keeps running here too.
func open_save(info: Dictionary) -> void:
	if is_open:
		return
	is_open = true
	_active = true
	_unlock_frame = -1
	if player != null:
		player.controls_locked = true
	_save_info = info
	_show_panel(Mode.SAVE, 0.05)
	opened.emit()


## The robot is dead: the sign drops with message in red and the buttons offer the last station,
## a save, or the main menu. The game keeps running underneath, and there's no closing it.
func open_death(message: String) -> void:
	if is_open:
		close()
	_unlock_frame = -1
	_exiting = false
	_dead = true
	_set_sign(message, 2, DEV_TUBE, DEV_CORE, DEV_GHOST)
	_buttons = _make_buttons(DEATH_LABELS)
	open()


## Back to the normal pause menu, for when the robot is brought back without a reload (the dev
## menu healing a core fault).
func close_death() -> void:
	if not _dead:
		return
	_dead = false
	close()
	_set_sign(SIGN_TEXT, SIGN_SCALE, SIGN_TUBE, SIGN_CORE, SIGN_GHOST)
	_buttons = _make_buttons(LABELS)


func is_dead_screen() -> bool:
	return _dead


func _apply_pending(data: Dictionary) -> void:
	SAVE_SLOTS.apply(data, player, _clock())


## Pulls everything back out. Control returns to the robot a couple of physics frames later.
func close() -> void:
	if not is_open:
		return
	is_open = false
	_capturing = -1
	_conflict = {}
	_slot_box = {}
	_unlock_frame = Engine.get_physics_frames() + 2
	_retract_buttons()
	for panel in _panels:
		_retract_panel(panel)
	_mode = Mode.BUTTONS
	_sign.play(_sign_close_steps(_sign.value))
	_sign_light.turn_off()
	closed.emit()


func _physics_process(_delta: float) -> void:
	if _unlock_frame >= 0 and Engine.get_physics_frames() >= _unlock_frame:
		_unlock_frame = -1
		if player != null and not _dead:
			player.controls_locked = false


func _process(delta: float) -> void:
	_update_dev_sign(delta)
	if not _active:
		if GameSettings.dev_mode or _dev_was_on:
			queue_redraw()
		return
	_glitch_left = maxf(_glitch_left - delta, 0.0)
	_saved_left = maxf(_saved_left - delta, 0.0)
	_death_fade = move_toward(_death_fade, 1.0 if _dead else 0.0, delta / 1.5)
	_back_press.update(delta)
	for press in _page_press:
		press.update(delta)
	_time += delta
	_shake_clock += delta
	if _shake_clock >= 0.03:
		# Shakes change in steps, like a part chattering in its guide, not every frame.
		_shake_clock = 0.0
		_shake_seed += 1

	var any_shown := false
	for i in _buttons.size():
		var b := _buttons[i]
		var track: MechTrack = b.track
		for tag in track.update(delta):
			_on_button_tag(i, tag)
		for tag in (b.select as MechTrack).update(delta):
			_on_button_tag(i, tag)
		(b.jolt as MechTrack).update(delta)
		(b.light as NeonLight).update(delta)
		if track.value > 0.0 or track.is_busy():
			any_shown = true

	for i in _panels.size():
		var panel := _panels[i]
		var panel_track: MechTrack = panel.track
		for tag in panel_track.update(delta):
			_on_panel_tag(i, tag)
		(panel.light as NeonLight).update(delta)
		if panel_track.value > 0.0 or panel_track.is_busy():
			any_shown = true

	for tag in _sign.update(delta):
		_on_sign_tag(tag)
	_sign_light.update(delta)
	if _sign.value > 0.0 or _sign.is_busy():
		any_shown = true

	_update_fault(delta)
	_update_steam(delta)
	_sparks.update(delta)
	_ice.update(delta)
	if is_open:
		_emit_ambient_sparks(delta)

	if (not is_open and not any_shown and _steam.is_empty() and _sparks.is_empty()
			and _ice.is_empty()):
		_active = false
	queue_redraw()


func _draw() -> void:
	_draw_dev_sign()
	if not _active:
		return
	if _death_fade > 0.0:
		# Dead: the view sinks into a dim red murk (drawn over the world, under the menu).
		draw_rect(Rect2(Vector2.ZERO, _screen_size()), Color(0.05, 0.0, 0.0, 0.5 * _death_fade))
	_draw_sign()
	for i in _buttons.size():
		_draw_button(i)
	for i in _panels.size():
		_draw_panel(i)
	_draw_steam()
	_sparks.draw(self)
	_ice.draw(self)


# --- Input -----------------------------------------------------------------------------------


func _select(index: int) -> void:
	if index == selected:
		return
	var old: MechTrack = _buttons[selected].select
	old.play([
		{"to": 1.12, "dur": 0.025},
		{"to": 0.35, "dur": 0.05, "ease": 2.0},
		{"dur": 0.04, "shake": 1},
		{"to": 0.0, "dur": 0.04, "tag": "vent_small"},
	])
	selected = index
	var fresh: MechTrack = _buttons[selected].select
	fresh.play([
		{"to": 0.55, "dur": 0.04, "ease": 2.5},
		{"dur": _rng.randf_range(0.03, 0.07), "shake": 1},
		{"to": 1.2, "dur": 0.04, "ease": 2.0},
		{"to": 1.0, "dur": 0.035, "tag": "vent_small"},
	])
	(_buttons[selected].light as NeonLight).flicker_bright()
	_button_spark_wait = _rng.randf_range(0.05, 0.2)


func _confirm() -> void:
	if _dead:
		match selected:
			DeathAction.LAST_STATION:
				_reload_last_station()
			DeathAction.LOAD_SAVE:
				_show_panel(Mode.LOAD)
			DeathAction.MAIN_MENU:
				_leave_dead(MAIN_MENU_SCENE)
		return
	match selected:
		Action.CONTINUE:
			close()
		Action.LOAD_STATION:
			_show_panel(Mode.LOAD)
		Action.SETTINGS:
			_show_panel(Mode.SETTINGS)
		Action.EXIT:
			_show_panel(Mode.EXIT)


# --- Step scripts ----------------------------------------------------------------------------
# Each step: "to" (target, omit to hold), "dur" seconds, "ease" (Godot ease() curve, >1 speeds
# up into the stop), "shake" pixels of chatter while it runs, "tag" fired when it ends.


## delay holds everything back first, e.g. while a display clears the way.
func _button_open_steps(index: int, delay: float = 0.0) -> Array:
	var stall := _rng.randf_range(0.05, 0.11)
	var steps: Array = [
		{"dur": delay + index * button_stagger},
		{"to": _rng.randf_range(0.42, 0.6), "dur": 0.08, "ease": 2.4},
		{"dur": stall, "shake": 1},
	]
	if _rng.randf() < 0.35:
		# Pressure drops: it slides back a touch before the next shove.
		steps.append({"to": 0.36, "dur": 0.05, "ease": 0.6})
		steps.append({"dur": 0.05, "shake": 1})
	steps.append_array([
		{"to": 0.82, "dur": 0.05, "ease": 1.6},
		{"dur": 0.035, "shake": 1},
		{"to": 1.07, "dur": 0.05, "ease": 2.0},
		{"to": 1.0, "dur": 0.035, "tag": "locked"},
		{"dur": 0.08, "shake": 1},
	])
	return steps


## from is where the button is now: one caught halfway in skips the latch release.
func _button_close_steps(order: int, from: float) -> Array:
	var steps: Array = [{"dur": order * button_stagger * 0.8}]
	if from > 0.9:
		steps.append_array([
			{"to": 1.05, "dur": 0.03, "tag": "release"},
			{"dur": 0.05, "shake": 1},
		])
	else:
		steps.append({"dur": 0.0, "tag": "release"})
	steps.append_array([
		{"to": minf(_rng.randf_range(0.5, 0.65), from), "dur": 0.08, "ease": 2.2},
		{"dur": _rng.randf_range(0.04, 0.09), "shake": 1},
		{"to": -0.02, "dur": 0.08, "ease": 2.2, "tag": "gone"},
	])
	return steps


func _sign_open_steps() -> Array:
	return [
		{"dur": 0.05},
		{"to": _rng.randf_range(0.3, 0.4), "dur": 0.13, "ease": 2.2},
		{"dur": _rng.randf_range(0.07, 0.13), "shake": 1, "tag": "catch"},
		# The brake slips: a sudden short drop.
		{"to": 0.58, "dur": 0.035, "ease": 2.0},
		{"dur": _rng.randf_range(0.08, 0.16), "shake": 1},
		{"to": 1.1, "dur": 0.15, "ease": 2.0},
		{"to": 0.97, "dur": 0.05, "ease": 0.6},
		{"to": 1.0, "dur": 0.04, "tag": "locked"},
		{"dur": 0.1, "shake": 1},
	]


func _sign_close_steps(from: float) -> Array:
	var steps: Array = []
	if from > 0.9:
		steps.append_array([
			{"to": 1.06, "dur": 0.04, "tag": "release"},
			{"dur": 0.07, "shake": 1},
		])
	steps.append_array([
		{"to": minf(_rng.randf_range(0.5, 0.65), from), "dur": 0.12, "ease": 2.0},
		{"dur": _rng.randf_range(0.06, 0.12), "shake": 1, "tag": "catch"},
		{"to": -0.02, "dur": 0.13, "ease": 2.2, "tag": "gone"},
	])
	return steps


func _on_button_tag(index: int, tag: String) -> void:
	var mouth := _rod_mouth(index)
	match tag:
		"locked":
			# Locked in place: vent the cylinder and strike the tube.
			_vent(mouth, -PI / 2.0, 7, 26.0)
			_vent(mouth + Vector2(0, 2), 0.0, 4, 30.0)
			(_buttons[index].light as NeonLight).strike()
			var r := _button_rect(index)
			for k in 2:
				_ice.emit(Vector2(r.position.x + _rng.randi_range(8, r.size.x - 8), r.end.y), 1,
						PI / 2.0, 0.5, 4.0, 15.0, 0.4, 0.8)
		"release":
			_vent(mouth, -PI / 2.0, 5, 30.0)
			(_buttons[index].light as NeonLight).turn_off()
		"gone":
			_vent(Vector2(size.x - 1, mouth.y), PI, 3, 14.0)
		"vent_small":
			_vent(mouth, -PI / 2.0, 3, 18.0)


func _on_sign_tag(tag: String) -> void:
	var r := _sign_rect()
	match tag:
		"locked":
			for x in _strut_xs():
				_vent(Vector2(x - 2, r.position.y - 2), PI, 6, 30.0)
				_vent(Vector2(x + 4, r.position.y - 2), 0.0, 6, 30.0)
			_vent(Vector2(r.position.x, r.end.y - 3), PI * 0.85, 3, 16.0)
			_vent(Vector2(r.end.x, r.end.y - 3), PI * 0.15, 3, 16.0)
			_sign_light.strike()
			for k in 3:
				_ice.emit(Vector2(r.position.x + _rng.randi_range(6, r.size.x - 6), r.end.y), 1,
						PI / 2.0, 0.5, 4.0, 15.0, 0.4, 0.8)
		"catch":
			for x in _strut_xs():
				_vent(Vector2(x + 1, r.position.y - 3), -PI / 2.0, 2, 12.0)
		"release":
			for x in _strut_xs():
				_vent(Vector2(x - 2, r.position.y - 2), PI, 4, 34.0)
				_vent(Vector2(x + 4, r.position.y - 2), 0.0, 4, 34.0)


# --- Layout ----------------------------------------------------------------------------------


func _screen_size() -> Vector2:
	return size if size.x > 0.0 else get_viewport_rect().size


## Where the button's plaque is right now, including pushes and chatter.
func _button_rect(index: int) -> Rect2i:
	var b := _buttons[index]
	var screen := _screen_size()
	var track: MechTrack = b.track
	# Far enough right that a pushed-out selection and a jolt still sit off-screen.
	var hidden_x := screen.x + SELECT_PUSH + 6.0
	var rest_x := screen.x - RIGHT_MARGIN - PLAQUE_SIZE.x
	var x := lerpf(hidden_x, rest_x, track.value)
	x -= (b.select as MechTrack).value * SELECT_PUSH
	# A jammed confirm shoves it back in a little.
	x += (b.jolt as MechTrack).value * 3.0
	var stack_h := BUTTON_STEP * (_buttons.size() - 1) + PLAQUE_SIZE.y
	var y := roundf(screen.y * STACK_CENTER - stack_h / 2.0) + index * BUTTON_STEP
	var chatter := maxi(track.shake, (b.select as MechTrack).shake)
	chatter = maxi(chatter, (b.jolt as MechTrack).shake)
	var offset := _shake_offset(index * 7 + 1, chatter)
	return Rect2i(Vector2i(floori(x), int(y)) + offset, PLAQUE_SIZE)


## Where the button's rod leaves the screen edge's cylinder.
func _rod_mouth(index: int) -> Vector2:
	var r := _button_rect(index)
	return Vector2(_screen_size().x - 2, r.position.y + HALF_PLAQUE_H)


func _sign_rect() -> Rect2i:
	var frame := _sign_text_size + SIGN_PAD * 2
	var screen := _screen_size()
	var hidden_y := -frame.y - 6.0
	var y := floori(lerpf(hidden_y, SIGN_SHOWN_Y, _sign.value))
	var x := floori((screen.x - frame.x) / 2.0)
	var offset := _shake_offset(97, _sign.shake)
	# The sign only chatters sideways and a pixel up; it hangs, so it can't kick downwards.
	offset.y = mini(offset.y, 0)
	return Rect2i(Vector2i(x, y) + offset, frame)


func _strut_xs() -> Array[int]:
	var r := _sign_rect()
	return [r.position.x + STRUT_INSET, r.end.x - STRUT_INSET - 3]


func _shake_offset(salt: int, amount: int) -> Vector2i:
	if amount <= 0:
		return Vector2i.ZERO
	var h := hash(Vector2i(_shake_seed, salt))
	return Vector2i(h % (amount * 2 + 1) - amount, (h >> 8) % (amount * 2 + 1) - amount)


# --- Drawing: buttons ------------------------------------------------------------------------


func _draw_button(index: int) -> void:
	var b := _buttons[index]
	var r := _button_rect(index)
	var screen_w := int(_screen_size().x)
	if r.position.x >= screen_w:
		return
	var p := r.position
	var mid_y := p.y + HALF_PLAQUE_H

	# Piston rod from the plaque's back out through the screen edge.
	var rod_x := p.x + PLAQUE_SIZE.x
	if rod_x < screen_w:
		for k in ROD_COLORS.size():
			draw_rect(Rect2(rod_x, mid_y - 1 + k, screen_w - rod_x, 1), ROD_COLORS[k])
		# Witness marks on the rod show it sliding.
		var mark_x := rod_x + 3
		while mark_x < screen_w:
			draw_rect(Rect2(mark_x, mid_y, 1, 1), ROD_COLORS[2])
			mark_x += 6

	var poly := _plaque_polygon(p)
	draw_colored_polygon(poly, PLAQUE_COLOR)
	var w := PLAQUE_SIZE.x
	var h := PLAQUE_SIZE.y
	var c := PLAQUE_CHAMFER
	# Lit top edge and slanted upper chamfer, shadowed bottom and back.
	draw_rect(Rect2(p.x + c, p.y, w - c - 4, 1), PLAQUE_LIGHT)
	for k in c:
		draw_rect(Rect2(p.x + c - 1 - k, p.y + 1 + k, 1, 1), PLAQUE_LIGHT)
		draw_rect(Rect2(p.x + k, p.y + h - c + k, 1, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x, p.y + c, 1, h - c * 2), PLAQUE_LIGHT.darkened(0.25))
	draw_rect(Rect2(p.x + c, p.y + h - 1, w - c, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 4, p.y, 1, h), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 3, p.y + 1, 3, h - 2), PLAQUE_COLOR.darkened(0.25))
	# Clevis where the rod bolts on.
	draw_rect(Rect2(p.x + w - 3, mid_y - 2, 3, 5), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 2, mid_y - 1, 2, 3), ROD_COLORS[1])
	draw_rect(Rect2(p.x + w - 2, mid_y - 1, 1, 1), ROD_COLORS[0])
	for g in b.grime:
		draw_rect(Rect2(Vector2(p) + g[0], Vector2.ONE), g[1])
	for rv in BUTTON_RIVETS:
		draw_rect(Rect2(Vector2(p + rv), Vector2.ONE), HudDraw.RIVET_COLOR)

	var select_track: MechTrack = b.select
	var sel := clampf(select_track.value, 0.0, 1.0)
	var light: NeonLight = b.light
	var glow := light.level * lerpf(0.42, 1.0, sel)
	if index == selected and is_open:
		# Mains hum on the live tube.
		glow *= 0.93 + 0.07 * sin(_time * 31.0)

	# Status lamp left of the channel.
	var lamp_on := sel * light.level
	draw_rect(Rect2(p.x + 5, mid_y - 2, 3, 4), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + 6, mid_y - 1, 1, 2), LAMP_OFF.lerp(LAMP_ON, lamp_on))
	if lamp_on > 0.5:
		var halo := LAMP_ON
		halo.a = 0.25 * lamp_on
		draw_rect(Rect2(p.x + 5, mid_y - 2, 3, 4), halo)

	# Recessed channel the neon sits in.
	var text: Dictionary = b.text
	var channel := Rect2(p.x + TEXT_X - 3, p.y + 3, w - TEXT_X - 6, h - 6)
	draw_rect(channel, CHANNEL_COLOR)
	draw_rect(Rect2(channel.position.x, channel.position.y, channel.size.x, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(channel.position.x, channel.end.y, channel.size.x, 1),
			PLAQUE_LIGHT.darkened(0.4))
	_draw_neon(text, Vector2i(p.x + TEXT_X, p.y + 4), glow, sel, BUTTON_TUBE, BUTTON_CORE,
			BUTTON_GHOST)
	_draw_frost(b.frost, p)
	_draw_icicles(b.icicles, Vector2i(p.x, p.y + h))


func _plaque_polygon(p: Vector2i) -> PackedVector2Array:
	var w := PLAQUE_SIZE.x
	var h := PLAQUE_SIZE.y
	var c := PLAQUE_CHAMFER
	var o := Vector2(p)
	return PackedVector2Array([
		o + Vector2(c, 0), o + Vector2(w, 0), o + Vector2(w, h), o + Vector2(c, h),
		o + Vector2(0, h - c), o + Vector2(0, c),
	])


func _roll_plaque_grime(rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var grime: Array = []
	var channel := Rect2(TEXT_X - 4, 2, PLAQUE_SIZE.x - TEXT_X - 4, PLAQUE_SIZE.y - 4)
	var lamp := Rect2(4, HALF_PLAQUE_H - 3, 5, 6)
	var poly := _plaque_polygon(Vector2i.ZERO)
	var tries := 0
	while grime.size() < 26 and tries < 2000:
		tries += 1
		var g := Vector2(rng.randi_range(1, PLAQUE_SIZE.x - 5), rng.randi_range(1, PLAQUE_SIZE.y - 2))
		if channel.has_point(g) or lamp.has_point(g):
			continue
		if not Geometry2D.is_point_in_polygon(g, poly):
			continue
		grime.append([g, RUST_COLORS[rng.randi_range(0, RUST_COLORS.size() - 1)]])
		# Rust runs downwards in short streaks.
		if rng.randf() < 0.3 and g.y < PLAQUE_SIZE.y - 3:
			grime.append([g + Vector2(0, 1), RUST_COLORS[1]])
	return grime


# --- Drawing: sign ---------------------------------------------------------------------------


func _draw_sign() -> void:
	var r := _sign_rect()
	if r.end.y <= 0:
		return
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x - 1
	var y1 := r.end.y - 1

	# Struts up through the top edge, with a cable lashed to one of them.
	for sx in _strut_xs():
		if y0 > 0:
			draw_rect(Rect2(sx, 0, 1, y0), ROD_COLORS[0])
			draw_rect(Rect2(sx + 1, 0, 1, y0), ROD_COLORS[1])
			draw_rect(Rect2(sx + 2, 0, 1, y0), ROD_COLORS[2])
			var band_y := y0 - 4
			while band_y > 0:
				# Clamp bands, so the eye can follow the strut sliding.
				draw_rect(Rect2(sx - 1, band_y, 5, 1), TRUSS_DARK)
				band_y -= 9
		# Clamp block where the strut bites the top chord.
		draw_rect(Rect2(sx - 2, y0 - 3, 7, 4), TRUSS_DARK)
		draw_rect(Rect2(sx - 1, y0 - 3, 5, 1), TRUSS_LIGHT)
		draw_rect(Rect2(sx - 2, y0 - 2, 1, 1), HudDraw.RIVET_COLOR)
		draw_rect(Rect2(sx + 4, y0 - 2, 1, 1), HudDraw.RIVET_COLOR)
	var cable_x := _strut_xs()[1] + 5
	if y0 > 0:
		for cy in range(0, y0 - 2):
			var sway := 1 if cy % 10 < 5 else 0
			draw_rect(Rect2(cable_x + sway, cy, 1, 1), CABLE_COLOR)

	# Truss behind the letters: two chords, posts, zigzag bracing, end plates.
	draw_rect(Rect2(x0, y0, r.size.x, 1), TRUSS_LIGHT)
	draw_rect(Rect2(x0, y0 + 1, r.size.x, 1), TRUSS_MID)
	draw_rect(Rect2(x0, y0 + 2, r.size.x, 1), TRUSS_DARK)
	draw_rect(Rect2(x0, y1 - 2, r.size.x, 1), TRUSS_MID)
	draw_rect(Rect2(x0, y1 - 1, r.size.x, 1), TRUSS_DARK)
	draw_rect(Rect2(x0, y1, r.size.x, 1), PLAQUE_SHADOW)
	var bay := 8
	var top := y0 + 3
	var bottom := y1 - 3
	var bx := x0 + 2
	var flip := false
	while bx + bay <= x1 - 1:
		draw_rect(Rect2(bx, top, 1, bottom - top + 1), TRUSS_DARK)
		if flip:
			_pixel_line(Vector2i(bx + 1, top), Vector2i(bx + bay - 1, bottom), TRUSS_MID)
		else:
			_pixel_line(Vector2i(bx + 1, bottom), Vector2i(bx + bay - 1, top), TRUSS_MID)
		flip = not flip
		bx += bay
	draw_rect(Rect2(bx, top, 1, bottom - top + 1), TRUSS_DARK)
	for ex in [x0, x1 - 1]:
		draw_rect(Rect2(ex, y0, 2, r.size.y), TRUSS_MID)
		draw_rect(Rect2(ex, y0, 1, r.size.y), TRUSS_LIGHT.darkened(0.2))
	# Rust and bolts on the chords.
	for k in range(x0 + 5, x1 - 3, 17):
		draw_rect(Rect2(k, y0 + 1, 1, 1), HudDraw.RIVET_COLOR)
		draw_rect(Rect2(k + 6, y1 - 1, 2, 1), RUST_COLORS[0])
	# Ballast box with a status LED under one end.
	draw_rect(Rect2(x1 - 13, y1 - 1, 9, 4), TRUSS_DARK)
	draw_rect(Rect2(x1 - 13, y1 - 1, 9, 1), TRUSS_MID)
	var led_on := fmod(_time, 1.3) < 0.08
	draw_rect(Rect2(x1 - 6, y1 + 1, 1, 1),
			Color(1.0, 0.25, 0.1) if led_on else Color(0.3, 0.06, 0.04))
	# Frost on the top chord, icicles under the bottom one.
	_draw_frost(_sign_frost, Vector2i(x0, y0))
	_draw_icicles(_sign_icicles, Vector2i(x0, y1 + 1))

	var origin := Vector2i(x0, y0) + SIGN_PAD
	var hum := 0.95 + 0.05 * sin(_time * 29.0)
	for i in _sign_letters.size():
		var letter := _sign_letters[i]
		var level := _sign_light.level * hum
		if i == _faulty_letter and _fault_left > 0.0:
			level *= 0.12 if fmod(_fault_left, 0.06) < 0.04 else 0.6
		var lp := origin + Vector2i(letter.x, 0)
		# Standoffs that hold each letter off the truss.
		draw_rect(Rect2(lp.x + 2, lp.y - 2, 1, 2), TRUSS_DARK)
		draw_rect(Rect2(lp.x + letter.w - 3, lp.y + _sign_text_size.y, 1, 2), TRUSS_DARK)
		_draw_neon(letter.text, lp, level, 1.0, _sign_tube, _sign_core, _sign_ghost)


## Draws prepared neon text (from _build_text) with its top left at pos. level is how lit the
## tube is (0 = dead glass), halo how far the glow bleeds (0 to 1).
func _draw_neon(
	text: Dictionary, pos: Vector2i, level: float, halo: float, tube: Color, core: Color,
	ghost: Color
) -> void:
	var cell: int = text.scale
	var block := Vector2(cell, cell)
	if level > 0.02:
		var halos: Array = text.halos
		for k in halos.size():
			var c := tube
			c.a = level * lerpf(0.1, 0.3, halo) / (k + 1)
			if k > 0 and halo < 0.5:
				continue
			for px in halos[k]:
				draw_rect(Rect2(Vector2(pos + px), Vector2.ONE), c)
	var lit := ghost.lerp(tube, clampf(level, 0.0, 1.0))
	var hot := ghost.lerp(core, clampf(level * level, 0.0, 1.0))
	for px in text.lit:
		draw_rect(Rect2(Vector2(pos + px * cell), block), lit)
	if cell > 1:
		for px in text.lit:
			draw_rect(Rect2(Vector2(pos + px * cell), Vector2.ONE), hot)
	elif level > 0.5:
		# Single-pixel tubes: brighten the horizontal strokes' middles for a glassy core.
		for px in text.core:
			draw_rect(Rect2(Vector2(pos + px), Vector2.ONE), hot)


func _pixel_line(a: Vector2i, b: Vector2i, color: Color) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for k in steps + 1:
		var t := float(k) / maxf(steps, 1.0)
		var p := Vector2(a).lerp(Vector2(b), t).round()
		draw_rect(Rect2(p, Vector2.ONE), color)


# --- Text ------------------------------------------------------------------------------------


func _build_sign(message: String = SIGN_TEXT, cell: int = SIGN_SCALE) -> void:
	var x := 0
	_sign_letters.clear()
	for ch in message:
		if ch == " ":
			x += (SIGN_WORD_GAP - SIGN_LETTER_GAP) * cell
			continue
		var text := _build_text(ch, cell, 2)
		_sign_letters.append({"text": text, "x": x, "w": text.dims.x})
		x += text.dims.x + SIGN_LETTER_GAP * cell
	var letter_h: int = (_sign_letters[0].text as Dictionary).dims.y
	_sign_text_size = Vector2i(x - SIGN_LETTER_GAP * cell, letter_h)
	var sign_w := _sign_text_size.x + SIGN_PAD.x * 2
	_sign_frost = _roll_edge_frost(sign_w, 61, MENU_FROST)
	_sign_icicles = _roll_icicles(sign_w, 62, MENU_FROST)


## Swaps the sign's text, size and tube colour.
func _set_sign(message: String, cell: int, tube: Color, core: Color, ghost: Color) -> void:
	_build_sign(message, cell)
	_sign_tube = tube
	_sign_core = core
	_sign_ghost = ghost


## A plaque for each label, each with its own grime, frost and icicles.
func _make_buttons(labels: Array[String]) -> Array[Dictionary]:
	var made: Array[Dictionary] = []
	for i in labels.size():
		var plaque_seed := 71 + i * 13
		made.append({
			"text": _build_text(labels[i], 1, 2),
			"track": MechTrack.new(),
			"select": MechTrack.new(),
			"light": NeonLight.new(),
			"grime": _roll_plaque_grime(plaque_seed),
			"frost": _roll_frost(PLAQUE_SIZE.x, PLAQUE_SIZE.y, plaque_seed + 3, MENU_FROST),
			"icicles": _roll_icicles(PLAQUE_SIZE.x, plaque_seed + 4, MENU_FROST),
			"jolt": MechTrack.new(),
		})
	return made


## Prepares text for _draw_neon: tube pixels in glyph units, glow rings around them in screen
## pixels (ring k is k + 1 pixels out), and its size in screen pixels.
func _build_text(text: String, cell: int, rings: int, font: Dictionary = GLYPHS) -> Dictionary:
	var lit: Array[Vector2i] = []
	var core: Array[Vector2i] = []
	var x := 0
	for ch in text:
		if ch == " ":
			x += SPACE_W
			continue
		var rows: Array = font.get(ch, _blank_glyph(font))
		for y in rows.size():
			var row: String = rows[y]
			for gx in row.length():
				if row[gx] == "#":
					lit.append(Vector2i(x + gx, y))
					var left := gx > 0 and row[gx - 1] == "#"
					var right := gx < row.length() - 1 and row[gx + 1] == "#"
					if left and right:
						core.append(Vector2i(x + gx, y))
		x += (rows[0] as String).length() + 1
	var w := (x - 1) * cell
	var h := (font["O"] as Array).size() * cell

	# Glow rings by distance from the nearest tube pixel.
	var filled := {}
	for px in lit:
		for oy in cell:
			for ox in cell:
				filled[px * cell + Vector2i(ox, oy)] = true
	var halos: Array = []
	var frontier := filled.keys()
	for ring in rings:
		var next: Array[Vector2i] = []
		for px in frontier:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
					Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				var q: Vector2i = px + d
				if not filled.has(q):
					filled[q] = true
					next.append(q)
		halos.append(next)
		frontier = next
	return {"lit": lit, "core": core, "halos": halos, "scale": cell, "dims": Vector2i(w, h)}


# --- Displays --------------------------------------------------------------------------------


## Up or down: moves between buttons, or along the save list.
func _step(direction: int) -> void:
	match _mode:
		Mode.BUTTONS:
			_select((selected + direction + _buttons.size()) % _buttons.size())
		_:
			# -1 is the BACK button above the first row.
			var next := clampi(_focus + direction, -1, _row_count() - 1)
			if next == _focus:
				# End of the list: the screen glitches instead of moving.
				(_panels[_panel_index()].light as NeonLight).flicker_bright()
				return
			_focus = next


## Rows on the screen the current display shows (the BACK button not included).
func _row_count() -> int:
	match _mode:
		Mode.LOAD, Mode.SAVE, Mode.NEW_GAME:
			# Three slots, then the page row.
			return SAVE_SLOTS.PAGE_SIZE + 1
		Mode.SETTINGS:
			# The category list ends with the DEVMODE checkbox.
			if _settings_page < 0:
				return _category_rows.size() + 1
			return (_pages[_settings_page] as Array).size()
		Mode.EXIT:
			# The CANCEL / EXIT pair.
			return 1
	return 0


## A, Enter or Z on a display.
func _panel_confirm() -> void:
	if _focus < 0:
		_back_press.play([
			{"to": 1.0, "dur": 0.03, "ease": 2.0},
			{"dur": 0.07},
			{"to": 0.0, "dur": 0.05},
		])
		var r := _panel_rect(_panel_index())
		var spot := Vector2(r.position + back_rect.position) + Vector2(_rng.randi_range(2, 26), 1)
		_sparks.emit(spot, 2, -PI / 2.0, 1.0, 15.0, 40.0, 0.1, 0.25)
		_go_back()
		return
	match _mode:
		Mode.LOAD, Mode.SAVE, Mode.NEW_GAME:
			_slot_confirm()
		Mode.SETTINGS:
			if _settings_page >= 0:
				_activate_option()
			elif _focus == _category_rows.size():
				GameSettings.dev_mode = not GameSettings.dev_mode
				GameSettings.save()
			else:
				_settings_page = _focus
				_option_scroll = 0
				_option_col = 0
				_focus = 0 if _row_count() > 0 else -1
				_glitch_left = GLITCH_TIME
		Mode.EXIT:
			if _exit_choice == 1:
				_exit_to_menu()
			else:
				_go_back()


## One screen back: a settings page to the category list, a display to the buttons.
func _go_back() -> void:
	_capturing = -1
	_conflict = {}
	if _mode == Mode.SETTINGS and _settings_page >= 0:
		_focus = _settings_page
		_settings_page = -1
		_glitch_left = GLITCH_TIME
		return
	_back()


## Pulls the buttons out and pushes the display for mode in once they're clear.
func _show_panel(mode: Mode, delay: float = 0.3) -> void:
	_mode = mode
	_retract_buttons()
	var panel := _panels[_panel_index()]
	(panel.light as NeonLight).snap_off()
	var track: MechTrack = panel.track
	track.play(_panel_open_steps(delay))
	_settings_page = -1
	_slot_box = {}
	_exit_choice = 0
	_focus = 0 if _row_count() > 0 else -1
	if mode == Mode.LOAD or mode == Mode.SAVE or mode == Mode.NEW_GAME:
		# Open on the active slot's page, with it highlighted (a new game: the first free one).
		var active := SAVE_SLOTS.get_active()
		if mode == Mode.NEW_GAME:
			active = maxi(SAVE_SLOTS.first_empty(), 0)
		_slot_page = floori(float(active) / SAVE_SLOTS.PAGE_SIZE)
		_focus = active % SAVE_SLOTS.PAGE_SIZE


## Sends the display back and brings the buttons in again, the same one still selected.
func _back() -> void:
	if _mode == Mode.SAVE:
		# The save screen came up on its own: leaving it closes the menu.
		close()
		return
	var index := _panel_index()
	if index < 0:
		return
	_retract_panel(_panels[index])
	_mode = Mode.BUTTONS
	for i in _buttons.size():
		var b := _buttons[i]
		(b.light as NeonLight).snap_off()
		(b.track as MechTrack).play(_button_open_steps(i, 0.3))


func _panel_index() -> int:
	match _mode:
		Mode.LOAD:
			return 0
		Mode.SETTINGS:
			return 1
		Mode.SAVE:
			return 2
		Mode.NEW_GAME:
			return 3
		Mode.EXIT:
			return 4
	return -1


func _retract_buttons() -> void:
	var count := _buttons.size()
	for i in count:
		var track: MechTrack = _buttons[i].track
		if track.value > 0.0 or track.is_busy():
			# Bottom button goes first, so the stack peels away upwards.
			track.play(_button_close_steps(count - 1 - i, track.value))


func _retract_panel(panel: Dictionary) -> void:
	var track: MechTrack = panel.track
	if track.value > 0.0 or track.is_busy():
		track.play(_panel_close_steps(track.value))
		(panel.light as NeonLight).turn_off()


## The display is heavier than a button: slower shoves, longer stalls.
func _panel_open_steps(delay: float) -> Array:
	var steps: Array = [
		{"dur": delay},
		{"to": _rng.randf_range(0.28, 0.36), "dur": 0.11, "ease": 2.4},
		{"dur": _rng.randf_range(0.08, 0.15), "shake": 1, "tag": "catch"},
	]
	if _rng.randf() < 0.4:
		steps.append({"to": 0.24, "dur": 0.06, "ease": 0.6})
		steps.append({"dur": 0.06, "shake": 1})
	steps.append_array([
		{"to": 0.7, "dur": 0.09, "ease": 1.8},
		{"dur": _rng.randf_range(0.05, 0.1), "shake": 1, "tag": "catch"},
		{"to": 1.05, "dur": 0.08, "ease": 2.0},
		{"to": 1.0, "dur": 0.05, "tag": "locked"},
		{"dur": 0.12, "shake": 1},
	])
	return steps


func _panel_close_steps(from: float) -> Array:
	var steps: Array = []
	if from > 0.9:
		steps.append_array([
			{"to": 1.04, "dur": 0.04, "tag": "release"},
			{"dur": 0.07, "shake": 1},
		])
	steps.append_array([
		{"to": minf(_rng.randf_range(0.45, 0.6), from), "dur": 0.1, "ease": 2.2},
		{"dur": _rng.randf_range(0.06, 0.12), "shake": 1, "tag": "catch"},
		{"to": -0.02, "dur": 0.1, "ease": 2.2, "tag": "gone"},
	])
	return steps


func _on_panel_tag(index: int, tag: String) -> void:
	var r := _panel_rect(index)
	var edge := _screen_size().x - 2
	match tag:
		"locked":
			for y in PANEL_ROD_YS:
				_vent(Vector2(edge, r.position.y + y), -PI / 2.0, 7, 28.0)
				_vent(Vector2(edge, r.position.y + y + 2), PI * 0.9, 4, 30.0)
			_vent(Vector2(r.position.x + 2, r.end.y - 2), PI * 0.75, 4, 18.0)
			(_panels[index].light as NeonLight).strike()
			for k in 4:
				_ice.emit(Vector2(r.position.x + _rng.randi_range(8, r.size.x - 8), r.end.y), 1,
						PI / 2.0, 0.6, 5.0, 20.0, 0.4, 0.9)
		"catch":
			for y in PANEL_ROD_YS:
				_vent(Vector2(edge, r.position.y + y), -PI / 2.0, 2, 14.0)
		"release":
			for y in PANEL_ROD_YS:
				_vent(Vector2(edge, r.position.y + y), -PI / 2.0, 5, 32.0)
		"gone":
			for y in PANEL_ROD_YS:
				_vent(Vector2(edge + 1, r.position.y + y), PI, 2, 12.0)


func _panel_rect(index: int) -> Rect2i:
	var track: MechTrack = _panels[index].track
	var screen := _screen_size()
	var hidden_x := screen.x + 6.0
	var rest_x := screen.x - RIGHT_MARGIN - panel_size.x
	var x := floori(lerpf(hidden_x, rest_x, track.value))
	var y := maxi(roundi(screen.y * STACK_CENTER - panel_size.y * 0.5), 2)
	return Rect2i(Vector2i(x, y) + _shake_offset(211 + index, track.shake), panel_size)


func _draw_panel(index: int) -> void:
	var panel := _panels[index]
	var r := _panel_rect(index)
	var screen_w := int(_screen_size().x)
	if r.position.x >= screen_w:
		return
	var p := r.position
	var w := panel_size.x
	var h := panel_size.y
	var c := PANEL_CHAMFER

	# Two rods from the housing's back out through the screen edge.
	for ry in PANEL_ROD_YS:
		var rod_x := p.x + w
		if rod_x < screen_w:
			for k in ROD_COLORS.size():
				draw_rect(Rect2(rod_x, p.y + ry - 1 + k, screen_w - rod_x, 1), ROD_COLORS[k])
			var mark_x := rod_x + 3
			while mark_x < screen_w:
				draw_rect(Rect2(mark_x, p.y + ry, 1, 1), ROD_COLORS[2])
				mark_x += 6

	# Housing.
	draw_colored_polygon(_panel_polygon(p), PLAQUE_COLOR)
	draw_rect(Rect2(p.x + c, p.y, w - c - 4, 1), PLAQUE_LIGHT)
	for k in c:
		draw_rect(Rect2(p.x + c - 1 - k, p.y + 1 + k, 1, 1), PLAQUE_LIGHT)
		draw_rect(Rect2(p.x + k, p.y + h - c + k, 1, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x, p.y + c, 1, h - c * 2), PLAQUE_LIGHT.darkened(0.25))
	draw_rect(Rect2(p.x + c, p.y + h - 1, w - c, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 4, p.y, 1, h), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + w - 3, p.y + 1, 3, h - 2), PLAQUE_COLOR.darkened(0.25))
	for ry in PANEL_ROD_YS:
		draw_rect(Rect2(p.x + w - 3, p.y + ry - 2, 3, 5), PLAQUE_SHADOW)
		draw_rect(Rect2(p.x + w - 2, p.y + ry - 1, 2, 3), ROD_COLORS[1])
		draw_rect(Rect2(p.x + w - 2, p.y + ry - 1, 1, 1), ROD_COLORS[0])
	# Vent grille low on the front, and worn hazard paint on the leading edge.
	for k in 4:
		draw_rect(Rect2(p.x + 3, p.y + h - 30 + k * 3, 4, 1), PLAQUE_SHADOW)
	for k in 3:
		draw_rect(Rect2(p.x + 1, p.y + 60 + k * 4, 2, 2), Color(0.42, 0.3, 0.08))
	for g in panel.grime:
		draw_rect(Rect2(Vector2(p) + g[0], Vector2.ONE), g[1])
	for rv in PANEL_RIVETS:
		draw_rect(Rect2(Vector2(p + rv), Vector2.ONE), HudDraw.RIVET_COLOR)

	var light: NeonLight = panel.light
	var level := light.level * (0.95 + 0.05 * sin(_time * 23.0))

	# Title strip: lamp and neon heading.
	draw_rect(Rect2(p.x + 4, p.y + 7, 3, 4), PLAQUE_SHADOW)
	draw_rect(Rect2(p.x + 5, p.y + 8, 1, 2), LAMP_OFF.lerp(LAMP_ON, clampf(level, 0.0, 1.0)))
	var title_channel := Rect2(p.x + 10, p.y + 4, back_rect.position.x - 13, 11)
	draw_rect(title_channel, CHANNEL_COLOR)
	draw_rect(Rect2(title_channel.position, Vector2(title_channel.size.x, 1)), PLAQUE_SHADOW)
	_draw_neon(panel.title, p + Vector2i(13, 6), level, 1.0, BUTTON_TUBE, BUTTON_CORE,
			BUTTON_GHOST)
	var active := is_open and index == _panel_index()
	_draw_back_button(p, level, active and _focus < 0)

	# The screen: bezel, dark glass, then contents.
	var s := Rect2i(p + panel_screen.position, panel_screen.size)
	draw_rect(Rect2(s.grow(1)), PLAQUE_SHADOW)
	draw_rect(Rect2(s.position.x - 1, s.end.y, s.size.x + 2, 1), PLAQUE_LIGHT.darkened(0.3))
	draw_rect(Rect2(s.end.x, s.position.y - 1, 1, s.size.y + 2), PLAQUE_LIGHT.darkened(0.3))
	draw_rect(Rect2(s), SCREEN_BG)
	if level > 0.02:
		var scrambled := active and _glitch_left > GLITCH_TIME * 0.5
		if not scrambled:
			_draw_screen(index, s, level, active)
		if active and _glitch_left > 0.0:
			_draw_glitch(s, level)
		# Scanlines and a slow rolling band over everything on the glass.
		var scan := Color(0, 0, 0, 0.28)
		for y in range(s.position.y + 1, s.end.y, 2):
			draw_rect(Rect2(s.position.x, y, s.size.x, 1), scan)
		var band_y := s.position.y + int(fmod(_time * 22.0, s.size.y + 12.0)) - 6
		var band := PHOSPHOR
		band.a = 0.05 * level
		for k in 6:
			var y := band_y + k
			if y >= s.position.y and y < s.end.y:
				draw_rect(Rect2(s.position.x, y, s.size.x, 1), band)
	_draw_glass_frost(s, 500 + index, 0.6, false)
	# Glass glint in the top left corner.
	draw_rect(Rect2(s.position.x + 1, s.position.y + 1, 6, 1), Color(1, 1, 1, 0.06))
	draw_rect(Rect2(s.position.x + 1, s.position.y + 2, 1, 4), Color(1, 1, 1, 0.06))
	# Frost along the housing's top, icicles under it.
	_draw_frost(_panel_frost[index], p + Vector2i(c, 0))
	_draw_icicles(_panel_icicles[index], Vector2i(p.x + 5, p.y + h))


## The small BACK plate in the housing's top right corner, pressed in a pixel when used.
func _draw_back_button(p: Vector2i, level: float, focused: bool) -> void:
	var bp := p + back_rect.position + Vector2i(roundi(_back_press.value), 0)
	var size_px := back_rect.size
	draw_rect(Rect2(Vector2(bp - Vector2i.ONE), Vector2(size_px + Vector2i(2, 2))), PLAQUE_SHADOW)
	draw_rect(Rect2(Vector2(bp), Vector2(size_px)), PLAQUE_COLOR.lightened(0.04))
	draw_rect(Rect2(bp.x, bp.y, size_px.x, 1), PLAQUE_LIGHT)
	draw_rect(Rect2(bp.x, bp.y, 1, size_px.y), PLAQUE_LIGHT.darkened(0.2))
	draw_rect(Rect2(bp.x, bp.y + size_px.y - 1, size_px.x, 1), PLAQUE_SHADOW)
	draw_rect(Rect2(bp.x + 2, bp.y + 2, size_px.x - 4, size_px.y - 4), CHANNEL_COLOR)
	var glow := level * (1.0 if focused else 0.42)
	if focused:
		glow *= 0.93 + 0.07 * sin(_time * 31.0)
	_draw_neon(_back_text, bp + Vector2i(3, 3), glow, 1.0 if focused else 0.0, BUTTON_TUBE,
			BUTTON_CORE, BUTTON_GHOST)


## What the display's glass shows: index 1 settings, 4 the exit warning, the rest save slots.
func _draw_screen(index: int, s: Rect2i, level: float, active: bool) -> void:
	match index:
		1:
			_draw_settings(s, level, active)
		4:
			_draw_exit(s, level, active)
		_:
			_draw_slots(s, level, active)


# --- Exit ------------------------------------------------------------------------------------


## EXIT confirmed: the screen scrambles and dies, then the main menu loads. The game still runs
## until the scene changes.
func _exit_to_menu() -> void:
	if _exiting:
		return
	_exiting = true
	_glitch_left = GLITCH_TIME * 3.0
	var panel := _panels[_panel_index()]
	(panel.light as NeonLight).fault(EXIT_DELAY)
	var r := _panel_rect(_panel_index())
	_sparks.emit(Vector2(r.position) + Vector2(1, _rng.randi_range(PANEL_CHAMFER, 40)), 6, PI,
			1.2, 20.0, 60.0, 0.15, 0.35)
	get_tree().create_timer(EXIT_DELAY, true).timeout.connect(_load_main_menu)


func _load_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## How long ago the slot being played was saved, in words, or "" with nothing saved in it.
func _last_save_age() -> String:
	var data := SAVE_SLOTS.get_slot(SAVE_SLOTS.get_active())
	if data.is_empty():
		return ""
	var seconds := maxi(int(Time.get_unix_time_from_system() - float(data.get("unix", 0.0))), 0)
	var minutes := floori(seconds / 60.0)
	if minutes < 1:
		return "JUST NOW"
	if minutes < 60:
		return "%d MIN AGO" % minutes
	var hours := floori(minutes / 60.0)
	if hours < 24:
		return "%d H %d MIN AGO" % [hours, minutes % 60]
	var days := floori(hours / 24.0)
	return "1 DAY AGO" if days == 1 else "%d DAYS AGO" % days


## The exit warning: when the slot being played was last saved, that anything since then is
## lost, and CANCEL / EXIT.
func _draw_exit(s: Rect2i, level: float, active: bool) -> void:
	var cx := s.position.x + (s.size.x >> 1)
	var y := s.position.y + 8
	# Warning triangle with a blinking mark.
	var red := DEV_TUBE
	red.a = level * (0.75 + 0.25 * sin(_time * 5.0))
	for row in 9:
		var half := row >> 1
		draw_rect(Rect2(cx - half, y + row, 1, 1), red)
		draw_rect(Rect2(cx + half, y + row, 1, 1), red)
	draw_rect(Rect2(cx - 4, y + 9, 9, 1), red)
	if fmod(_time, 1.0) < 0.7:
		draw_rect(Rect2(cx, y + 3, 1, 3), red)
		draw_rect(Rect2(cx, y + 7, 1, 1), red)

	y += 15
	_draw_centered(_txt("LAST SAVE"), cx, y, level * 0.6, PHOSPHOR, PHOSPHOR_CORE, 0.0)
	y += 8
	var age := _last_save_age()
	var data := SAVE_SLOTS.get_slot(SAVE_SLOTS.get_active())
	if age == "":
		_draw_centered(_txt("NEVER SAVED", true), cx, y, level, DEV_TUBE, DEV_CORE, 1.0)
	else:
		_draw_centered(_txt(age, true), cx, y, level, PHOSPHOR, PHOSPHOR_CORE, 1.0)
		var where := "SLOT %02d  %s" % [SAVE_SLOTS.get_active() + 1,
				str(data.get("station", "")).to_upper()]
		_draw_centered(_txt(where), cx, y + 11, level * 0.7, PHOSPHOR, PHOSPHOR_CORE, 0.0)
		_draw_centered(_txt(str(data.get("area", "")).to_upper()), cx, y + 18, level * 0.55,
				PHOSPHOR, PHOSPHOR_CORE, 0.0)

	# Dotted rule, then the warning.
	y += 31
	var rule := PHOSPHOR_DIM
	rule.a = level
	for x in range(s.position.x + 8, s.end.x - 8, 2):
		draw_rect(Rect2(x, y, 1, 1), rule)
	y += 7
	_draw_centered(_txt("UNSAVED PROGRESS"), cx, y, level, DEV_TUBE, DEV_CORE, 0.0)
	_draw_centered(_txt("WILL BE LOST"), cx, y + 7, level, DEV_TUBE, DEV_CORE, 0.0)
	_draw_centered(_txt("RETURN TO MAIN MENU?"), cx, y + 20, level * 0.8, PHOSPHOR,
			PHOSPHOR_CORE, 0.0)

	# CANCEL and EXIT plates along the bottom.
	var on := active and _focus == 0
	var plate_w := 46
	var plate_y := s.end.y - 24
	var labels: Array[String] = ["CANCEL", "EXIT"]
	for i in 2:
		var px := cx - 4 - plate_w if i == 0 else cx + 4
		var plate := Rect2i(px, plate_y, plate_w, 14)
		var picked := on and _exit_choice == i
		var is_exit := i == 1
		var tube := DEV_TUBE if is_exit else PHOSPHOR
		var core := DEV_CORE if is_exit else PHOSPHOR_CORE
		if picked:
			var fill := Color(0.2, 0.04, 0.03) if is_exit else ROW_SELECT
			fill.a = level
			draw_rect(Rect2(plate), fill)
		var edge := tube
		edge.a = level * (1.0 if picked else (0.55 if _exit_choice == i else 0.3))
		draw_rect(Rect2(plate), edge, false, 1.0)
		var t := _txt(labels[i], true)
		var glow := level * (1.0 if picked else (0.65 if _exit_choice == i else 0.4))
		if picked:
			glow *= 0.93 + 0.07 * sin(_time * 31.0)
		_draw_neon(t, Vector2i(plate.position.x + ((plate_w - int(t.dims.x)) >> 1), plate_y + 4),
				glow, 1.0 if picked else 0.0, tube, core, SCREEN_BG)


func _draw_centered(t: Dictionary, cx: int, y: int, level: float, tube: Color, core: Color,
		halo: float) -> void:
	_draw_neon(t, Vector2i(cx - (int(t.dims.x) >> 1), y), level, halo, tube, core, SCREEN_BG)


# --- Drawing: ice ----------------------------------------------------------------------------


## Frost pixels from _roll_frost or _roll_edge_frost, offset by origin.
func _draw_frost(frost: Array, origin: Vector2i) -> void:
	for f in frost:
		var c := FROST
		c.a = f[1]
		draw_rect(Rect2(Vector2(origin) + f[0], Vector2.ONE), c)


## A thin crust along a top edge w wide: [pixel, alpha].
func _roll_edge_frost(w: int, rng_seed: int, amount: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var frost: Array = []
	for x in range(1, w - 1):
		if rng.randf() < 0.75 * amount:
			frost.append([Vector2(x, 0), rng.randf_range(0.35, 0.7)])
		if rng.randf() < 0.3 * amount:
			frost.append([Vector2(x, -1), rng.randf_range(0.25, 0.55)])
	return frost


func _draw_icicles(icicles: Array, base: Vector2i) -> void:
	for ic in icicles:
		var x: int = ic[0]
		var length: int = ic[1]
		for y in length:
			var thick := 2 if y < (length >> 1) and length >= 4 else 1
			var c := ICE if y < length - 1 else FROST
			c.a = 0.85
			draw_rect(Rect2(base.x + x, base.y + y, thick, 1), c)
			if thick == 2:
				var hl := FROST
				hl.a = 0.7
				draw_rect(Rect2(base.x + x, base.y + y, 1, 1), hl)


## Frost along the top edge and creeping in from a couple of corners: [pixel, alpha].
func _roll_frost(w: int, h: int, rng_seed: int, amount: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var frost: Array = []
	for x in range(PLAQUE_CHAMFER + 1, w - 4):
		if rng.randf() < 0.55 * amount:
			frost.append([Vector2(x, 0), rng.randf_range(0.5, 0.9)])
		if rng.randf() < 0.25 * amount:
			frost.append([Vector2(x, -1), rng.randf_range(0.4, 0.8)])
		if rng.randf() < 0.12 * amount:
			frost.append([Vector2(x, 1), rng.randf_range(0.25, 0.5)])
	var corners := [Vector2(w - 5, 1), Vector2(PLAQUE_CHAMFER + 1, h - 2)]
	if rng.randf() < 0.5:
		corners.append(Vector2(w - 5, h - 2))
	for corner in corners:
		var dir := Vector2(-1 if corner.x > w * 0.5 else 1, 1 if corner.y < h * 0.5 else -1)
		for k in int(26 * amount):
			var d := Vector2(rng.randi_range(0, 8), rng.randi_range(0, 5))
			if d.x + d.y * 1.5 > 9.0:
				continue
			frost.append([corner + d * dir, rng.randf_range(0.15, 0.45)])
	return frost


## Icicles under an edge w wide: [x, length].
func _roll_icicles(w: int, rng_seed: int, amount: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var icicles: Array = []
	var x := rng.randi_range(6, 14)
	while x < w - 8:
		if rng.randf() < 0.6:
			icicles.append([x, rng.randi_range(1, roundi(2 + 4 * amount))])
			if rng.randf() < 0.4:
				icicles.append([x + 2, rng.randi_range(1, 2)])
		x += rng.randi_range(5, 16)
	return icicles


## Frost grown over the glass in from its corners, and a crack across one.
## amount scales how far it reaches and how thick it is; crack adds a hairline across one corner.
func _draw_glass_frost(
	s: Rect2i, salt: int, amount: float = 1.0, crack_it: bool = true
) -> void:
	for corner in 4:
		var origin := Vector2(s.position.x if corner % 2 == 0 else s.end.x - 1,
				s.position.y if corner < 2 else s.end.y - 1)
		var dir := Vector2(1 if corner % 2 == 0 else -1, 1 if corner < 2 else -1)
		var reach := roundi((14 if corner == 1 else 9) * amount)
		for k in 90:
			var hsh := hash(Vector3i(salt, corner, k))
			var d := Vector2(hsh % (reach + 1), (hsh >> 8) % (reach + 1))
			if d.x + d.y > reach:
				continue
			var f := FROST
			f.a = 0.28 * amount * (1.0 - (d.x + d.y) / float(reach + 1))
			draw_rect(Rect2(origin + d * dir, Vector2.ONE), f)
	if not crack_it:
		return
	var crack := Color(0.75, 0.9, 1.0, 0.12)
	var q := Vector2(s.end.x - 1, s.position.y + 30)
	for k in 26:
		draw_rect(Rect2(q.floor(), Vector2.ONE), crack)
		q += Vector2(-1, 0.6 if k % 5 != 3 else -0.4)


## The settings screen: the category list, or the open category's (still empty) page.
func _draw_settings(s: Rect2i, level: float, active: bool) -> void:
	var rule := PHOSPHOR_DIM
	rule.a = level
	if _settings_page >= 0 and active:
		var page := _category_rows[_settings_page]
		_draw_neon(page.name, s.position + Vector2i(5, 5), level, 1.0, PHOSPHOR, PHOSPHOR_CORE,
				SCREEN_BG)
		draw_rect(Rect2(s.position.x + 1, s.position.y + 15, s.size.x - 2, 1), rule)
		var options: Array = _pages[_settings_page]
		if options.is_empty() and fmod(_time, 1.0) < 0.55:
			# Nothing here yet: a lone cursor blinks under the heading.
			var cursor := PHOSPHOR
			cursor.a = level
			draw_rect(Rect2(s.position.x + 5, s.position.y + 20, 3, 5), cursor)
		var shown := _visible_options()
		_keep_option_in_view(options.size())
		for i in range(_option_scroll, mini(_option_scroll + shown, options.size())):
			_draw_option(s, i, options[i], level)
		# Little arrows on the right when rows are hidden above or below.
		var hint := PHOSPHOR
		hint.a = level * (0.55 + 0.45 * sin(_time * 6.0))
		var ax := s.end.x - 5
		if _option_scroll > 0:
			var ay := s.position.y + option_top - 3
			draw_rect(Rect2(ax, ay, 1, 1), hint)
			draw_rect(Rect2(ax - 1, ay + 1, 3, 1), hint)
		if _option_scroll + shown < options.size():
			var by := s.position.y + option_top + shown * option_h
			draw_rect(Rect2(ax - 1, by, 3, 1), hint)
			draw_rect(Rect2(ax, by + 1, 1, 1), hint)
		if not _conflict.is_empty():
			_draw_conflict(s, level)
		return

	var dotted := PHOSPHOR_DIM
	dotted.a = level * 0.6
	for i in _category_rows.size():
		var row := _category_rows[i]
		var ry := s.position.y + SETTINGS_TOP + i * settings_row_h
		var mid := ry + ((settings_row_h - 1) >> 1)
		var on := active and i == _focus
		if on:
			var fill := ROW_SELECT
			fill.a = level
			draw_rect(Rect2(s.position.x + 1, ry, s.size.x - 2, settings_row_h - 1), fill)
			var notch := PHOSPHOR
			notch.a = level
			draw_rect(Rect2(s.position.x + 1, ry, 1, settings_row_h - 1), notch)
			# Chevron pointing into the page.
			for k in 3:
				draw_rect(Rect2(s.end.x - 8 + k, mid - 2 + k, 1, 1), notch)
				draw_rect(Rect2(s.end.x - 8 + k, mid + 2 - k, 1, 1), notch)
		var bright := level * (1.0 if on else 0.55)
		_draw_neon(row.number, Vector2i(s.position.x + 4, ry + ((settings_row_h - 5) >> 1)),
				bright * 0.6, 0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
		_draw_neon(row.name, Vector2i(s.position.x + 16, ry + ((settings_row_h - 7) >> 1)), bright,
				1.0 if on else 0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
		for x in range(s.position.x + 2, s.end.x - 2, 2):
			draw_rect(Rect2(x, ry + settings_row_h - 1, 1, 1), dotted)
	_draw_dev_checkbox(s, level, active)


## Option rows for each settings category, in SETTINGS_CATEGORIES order. Kinds: "choice" (left
## and right cycle), "toggle", "slider", "key" (confirm, then press the new key) and "action".
func _build_pages() -> void:
	var graphics: Array = [
		{"kind": "choice", "id": "display_mode", "label": "DISPLAY MODE"},
		{"kind": "toggle", "id": "vsync", "label": "V-SYNC"},
		{"kind": "slider", "id": "brightness", "label": "BRIGHTNESS"},
		{"kind": "action", "id": "reset_brightness", "label": "RESET BRIGHTNESS"},
		{"kind": "choice", "id": "particles", "label": "PARTICLES"},
		{"kind": "toggle", "id": "screen_shake", "label": "SCREEN SHAKE"},
	]
	var audio: Array = [
		{"kind": "slider", "id": "general", "label": "GENERAL"},
		{"kind": "slider", "id": "music", "label": "MUSIC"},
		{"kind": "slider", "id": "game", "label": "GAME"},
		{"kind": "slider", "id": "ui", "label": "UI"},
	]
	var controls: Array = []
	for i in GameSettings.REMAPPABLE.size():
		controls.append({
			"kind": "key", "id": "key", "label": GameSettings.REMAP_NAMES[i],
			"action": GameSettings.REMAPPABLE[i],
		})
	controls.append({"kind": "action", "id": "reset_controls", "label": "RESET ALL TO DEFAULT"})
	var accessibility: Array = [
		{"kind": "choice", "id": "colorblind", "label": "COLORBLIND MODE"},
		{"kind": "slider", "id": "colorblind_strength", "label": "STRENGTH"},
		{"kind": "preview", "id": "colorblind_preview", "label": "PREVIEW"},
	]
	_pages = [graphics, audio, controls, [], accessibility]


## Left or right on a settings page: cycles a choice, flips a toggle, nudges a slider.
func _adjust(direction: int) -> void:
	if _mode == Mode.EXIT:
		if _focus < 0:
			return
		var choice := clampi(_exit_choice + direction, 0, 1)
		if choice == _exit_choice:
			(_panels[_panel_index()].light as NeonLight).flicker_bright()
			return
		_exit_choice = choice
		return
	if _mode == Mode.LOAD or _mode == Mode.SAVE or _mode == Mode.NEW_GAME:
		if _focus >= 0:
			_turn_page(direction)
		return
	if _mode != Mode.SETTINGS or _settings_page < 0 or _focus < 0:
		return
	var item: Dictionary = _pages[_settings_page][_focus]
	if item.kind in ["choice", "toggle", "slider"]:
		_change_option(item, direction)
	elif item.kind == "key":
		var col := clampi(_option_col + direction, 0, 1)
		if col == _option_col:
			(_panels[_panel_index()].light as NeonLight).flicker_bright()
		_option_col = col


## Confirm on a settings row.
func _activate_option() -> void:
	var item: Dictionary = _pages[_settings_page][_focus]
	match item.kind:
		"choice", "toggle":
			_change_option(item, 1)
		"key":
			if _option_col == 1:
				_reset_one_key(item)
			else:
				_capturing = _focus
		"action":
			match item.id:
				"reset_controls":
					GameSettings.reset_controls()
				"reset_brightness":
					GameSettings.brightness = 0.5
					GameSettings.save()
					_update_brightness()
			_glitch_left = GLITCH_TIME


## The reset symbol on a controls row: that action goes back to its default key.
func _reset_one_key(item: Dictionary) -> void:
	GameSettings.reset_key(item.action)
	_glitch_left = GLITCH_TIME * 0.6
	var r := _panel_rect(_panel_index())
	var s := Rect2i(r.position + panel_screen.position, panel_screen.size)
	var icon := _key_reset_rect(s, _focus)
	_sparks.emit(Vector2(icon.get_center()), 2, -PI / 2.0, 1.0, 12.0, 30.0, 0.1, 0.25)


## Where a controls row's reset symbol sits on the glass.
func _key_reset_rect(s: Rect2i, index: int) -> Rect2i:
	var size_px := 7 if settings_big else 5
	var ry := s.position.y + option_top + (index - _option_scroll) * option_h
	var mid := ry + ((option_h - 1) >> 1)
	return Rect2i(s.end.x - 5 - size_px, mid - (size_px >> 1), size_px, size_px)


func _change_option(item: Dictionary, direction: int) -> void:
	match item.id:
		"display_mode":
			var mode := posmod(GameSettings.display_mode + direction, 3)
			GameSettings.set_display_mode(mode as GameSettings.DisplayMode)
		"vsync":
			GameSettings.set_vsync(not GameSettings.vsync)
		"particles":
			var level := posmod(GameSettings.particles + direction, 3)
			GameSettings.particles = level as GameSettings.Particles
			GameSettings.save()
		"screen_shake":
			GameSettings.screen_shake = not GameSettings.screen_shake
			GameSettings.save()
		"colorblind":
			var filter := posmod(GameSettings.colorblind + direction, 4)
			GameSettings.colorblind = filter as GameSettings.Colorblind
			GameSettings.save()
			_update_brightness()
		_:
			if item.kind == "slider":
				_apply_slider(item, _nudge(_slider_value(item), direction))


## Sets a slider row's setting to v (0 to 1) and saves it.
func _apply_slider(item: Dictionary, v: float) -> void:
	match item.id:
		"brightness":
			GameSettings.brightness = v
			_update_brightness()
		"colorblind_strength":
			GameSettings.colorblind_strength = v
			_update_brightness()
		_:
			if GameSettings.volumes.has(item.id):
				GameSettings.volumes[item.id] = v
	GameSettings.save()


func _nudge(value: float, direction: int) -> float:
	return clampf(snappedf(value + direction * SLIDER_STEP, SLIDER_STEP), 0.0, 1.0)


## While a controls row waits: the next key pressed becomes its binding; Esc cancels.
func _capture_key(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var item: Dictionary = _pages[_settings_page][_capturing]
	_capturing = -1
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_ESCAPE:
		return
	var other := GameSettings.action_on_key(code, item.action)
	if other != &"":
		# Taken: put up the warning and let the player choose.
		_conflict = {"action": item.action, "other": other, "code": code, "choice": 0,
				"row": _focus, "age": 0.0}
		var r := _panel_rect(_panel_index())
		var spot := Vector2(r.position + panel_screen.position) + Vector2(10, 52)
		_sparks.emit(spot, 3, -PI / 2.0, 1.2, 20.0, 50.0, 0.12, 0.3)
		_glitch_left = GLITCH_TIME * 0.6
		return
	GameSettings.rebind(item.action, code)
	_glitch_left = GLITCH_TIME * 0.6


## Input while the key-in-use warning is up: left/right pick, confirm applies, back reverts.
func _conflict_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("menu_left", true) or event.is_action_pressed("menu_right", true):
		_conflict.choice = 1 - int(_conflict.choice)
	elif event.is_action_pressed("menu_confirm"):
		if int(_conflict.choice) == 1:
			GameSettings.rebind(_conflict.action, _conflict.code)
		_conflict = {}
		_glitch_left = GLITCH_TIME * 0.6
	elif event.is_action_pressed("pause_menu") or event.is_action_pressed("menu_back"):
		_conflict = {}


## The red key-in-use notice over the controls page, with REVERT and SWAP.
func _draw_conflict(s: Rect2i, level: float) -> void:
	_conflict.age = float(_conflict.age) + get_process_delta_time()
	var box := Rect2i(s.position.x + 5, s.position.y + 44, s.size.x - 10, 52)
	draw_rect(Rect2(box.grow(1)), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(box), Color(0.13, 0.02, 0.02, 0.96))
	# Border strikes on with a stutter, then flickers now and then.
	var age: float = _conflict.age
	var border_on := (age > 0.09 or fmod(age, 0.04) < 0.02) and fmod(_time, 1.7) > 0.05
	var red := DEV_TUBE
	red.a = level * (1.0 if border_on else 0.35)
	var halo := DEV_TUBE
	halo.a = level * 0.15
	draw_rect(Rect2(box.grow(2)), halo, false, 1.0)
	draw_rect(Rect2(box), red, false, 1.0)
	# Warning triangle.
	var tri := box.position + Vector2i(6, 6)
	for k in 6:
		draw_rect(Rect2(tri.x + 5 - k, tri.y + k, 1, 1), red)
		draw_rect(Rect2(tri.x + 5 + k, tri.y + k, 1, 1), red)
	draw_rect(Rect2(tri.x, tri.y + 6, 11, 1), red)
	draw_rect(Rect2(tri.x + 5, tri.y + 2, 1, 2), red)
	draw_rect(Rect2(tri.x + 5, tri.y + 5, 1, 1), red)

	var other_index := GameSettings.REMAPPABLE.find(_conflict.other)
	var other_name: String = GameSettings.REMAP_NAMES[other_index]
	var line1 := _txt("KEY ALREADY IN USE")
	var line2 := _txt(GameSettings.code_name(_conflict.code) + " IS ON " + other_name)
	_draw_neon(line1, box.position + Vector2i(22, 5), level, 1.0, DEV_TUBE, DEV_CORE, DEV_GHOST)
	_draw_neon(line2, box.position + Vector2i(22, 13), level * 0.8, 0.0, DEV_TUBE, DEV_CORE,
			DEV_GHOST)

	var labels := ["REVERT", "SWAP"]
	var plate_w := 44
	var gap := box.size.x - plate_w * 2 - 12
	for i in 2:
		var px := box.position.x + 6 + i * (plate_w + gap)
		var py := box.position.y + 30
		var picked := int(_conflict.choice) == i
		var plate := Color(0.2, 0.04, 0.03) if picked else Color(0.08, 0.02, 0.02)
		draw_rect(Rect2(px, py, plate_w, 15), plate)
		var edge := DEV_TUBE
		edge.a = level * (1.0 if picked else 0.4)
		draw_rect(Rect2(px, py, plate_w, 15), edge, false, 1.0)
		var t := _txt(labels[i])
		var tx: int = px + ((plate_w - int(t.dims.x)) >> 1)
		_draw_neon(t, Vector2i(tx, py + 5), level * (1.0 if picked else 0.5),
				1.0 if picked else 0.0, DEV_TUBE, DEV_CORE, DEV_GHOST)


func _option_text(item: Dictionary) -> String:
	match item.id:
		"display_mode":
			return ["FULLSCREEN", "WINDOWED", "BORDERLESS"][GameSettings.display_mode]
		"vsync":
			return "ON" if GameSettings.vsync else "OFF"
		"particles":
			return ["DEFAULT", "REDUCED", "NONE"][GameSettings.particles]
		"screen_shake":
			return "ON" if GameSettings.screen_shake else "OFF"
		"colorblind":
			return GameSettings.COLORBLIND_NAMES[GameSettings.colorblind]
		"key":
			return GameSettings.key_name(item.action)
	return ""


func _slider_value(item: Dictionary) -> float:
	if item.id == "brightness":
		return GameSettings.brightness
	if item.id == "colorblind_strength":
		return GameSettings.colorblind_strength
	return GameSettings.volumes.get(item.id, 0.0)


## One settings row: label on the left, its value right-aligned.
func _draw_option(s: Rect2i, index: int, item: Dictionary, level: float) -> void:
	var ry := s.position.y + option_top + (index - _option_scroll) * option_h
	var ty := ry + ((option_h - _text_h()) >> 1)
	var mid := ry + ((option_h - 1) >> 1)
	var on := _focus == index
	var lit := PHOSPHOR
	lit.a = level
	if on:
		var fill := ROW_SELECT
		fill.a = level
		draw_rect(Rect2(s.position.x + 1, ry, s.size.x - 2, option_h - 1), fill)
		draw_rect(Rect2(s.position.x + 1, ry, 1, option_h - 1), lit)
	var bright := level * (1.0 if on else 0.6)
	# While a key row waits for a key, PRESS A KEY can be wider than the room a long label
	# (ANTIMATTER CANNON) leaves, so the label steps aside until the key is pressed.
	if not (_capturing == index and _txt(item.label, settings_big).dims.x > s.size.x / 2):
		_draw_neon(_txt(item.label, settings_big), Vector2i(s.position.x + 5, ty), bright, 0.0,
				PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
	# Values end short of the edge so a selected row's arrows fit either side.
	var right := s.end.x - 8
	match item.kind:
		"action":
			if on:
				for k in 3:
					draw_rect(Rect2(s.end.x - 7 + k, mid - 2 + k, 1, 1), lit)
					draw_rect(Rect2(s.end.x - 7 + k, mid + 2 - k, 1, 1), lit)
		"preview":
			# Swatches of the colours that matter most in play, seen through the filter: the
			# integrity lights from healthy to fault, amber warnings and the cyan neon.
			var cell := 7 if settings_big else 5
			var gap := 2
			var x := right + 3 - PREVIEW_COLORS.size() * (cell + gap) + gap
			var y := mid - (cell >> 1)
			for c in PREVIEW_COLORS:
				var sw: Color = c
				sw.a = level
				draw_rect(Rect2(x, y, cell, cell), sw)
				x += cell + gap
		"slider":
			var v := _slider_value(item)
			var track_x := right + 3 - slider_w
			var groove := PHOSPHOR_DIM
			groove.a = level
			draw_rect(Rect2(track_x, mid - 1, slider_w, 3), groove)
			var fill_w := roundi(slider_w * v)
			var bar := PHOSPHOR
			bar.a = bright
			draw_rect(Rect2(track_x, mid - 1, fill_w, 3), bar)
			var knob := PHOSPHOR_CORE if on else PHOSPHOR
			knob.a = bright
			draw_rect(Rect2(track_x + clampi(fill_w - 1, 0, slider_w - 2), mid - 3, 2, 7), knob)
			var pct := _txt(str(roundi(v * 100.0)), settings_big)
			_draw_neon(pct, Vector2i(track_x - 4 - pct.dims.x, ty), bright, 0.0, PHOSPHOR,
					PHOSPHOR_CORE, SCREEN_BG)
		_:
			if item.kind == "key":
				# Reset symbol on the right; the key name sits left of it.
				var icon := _key_reset_rect(s, index)
				_draw_reset_icon(icon, level, on and _option_col == 1,
						GameSettings.is_default_key(item.action))
				right = icon.position.x - 5
			var waiting := _capturing == index
			if waiting and fmod(_time, 0.5) >= 0.3:
				return
			var value := _txt("PRESS A KEY" if waiting else _option_text(item), settings_big)
			var vx: int = right - value.dims.x
			_draw_neon(value, Vector2i(vx, ty), level if waiting or on else bright,
					1.0 if waiting else 0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
			if on and item.kind in ["choice", "toggle"]:
				var arrow_y := mid - 2
				_draw_neon(_txt("<"), Vector2i(vx - 6, arrow_y), level, 0.0, PHOSPHOR,
						PHOSPHOR_CORE, SCREEN_BG)
				_draw_neon(_txt(">"), Vector2i(right + 3, arrow_y), level, 0.0, PHOSPHOR,
						PHOSPHOR_CORE, SCREEN_BG)


## A small circular arrow. Picked: lit plate behind it. Already on the default key: faint.
func _draw_reset_icon(r: Rect2i, level: float, picked: bool, is_default: bool) -> void:
	var art: Array = RESET_ICON_BIG if settings_big else RESET_ICON
	if picked:
		var plate := PHOSPHOR
		plate.a = level * 0.9
		draw_rect(Rect2(r.grow(2)), plate, false, 1.0)
	var c := PHOSPHOR_CORE if picked else PHOSPHOR
	c.a = level * (1.0 if picked else (0.25 if is_default else 0.6))
	for y in art.size():
		var row: String = art[y]
		for x in row.length():
			if row[x] == "#":
				draw_rect(Rect2(r.position.x + x, r.position.y + y, 1, 1), c)


## How many option rows fit on the glass under a page's heading.
func _visible_options() -> int:
	return maxi(floori(float(panel_screen.size.y - option_top - 3) / option_h), 1)


## Scrolls a long page so the highlighted row stays on the glass.
func _keep_option_in_view(count: int) -> void:
	var shown := _visible_options()
	if _focus >= 0:
		if _focus < _option_scroll:
			_option_scroll = _focus
		elif _focus >= _option_scroll + shown:
			_option_scroll = _focus - shown + 1
	_option_scroll = clampi(_option_scroll, 0, maxi(count - shown, 0))


## Height of settings text: the big font in the main menu, the small one in the pause menu.
func _text_h() -> int:
	return 7 if settings_big else 5


## The small DEVMODE checkbox under the category list.
func _draw_dev_checkbox(s: Rect2i, level: float, active: bool) -> void:
	var n := _category_rows.size()
	var ry := s.position.y + SETTINGS_TOP + n * settings_row_h + 4
	var on := active and _focus == n
	var lit := PHOSPHOR
	lit.a = level * (1.0 if on else 0.6)
	var row_h := _text_h() + 4
	if on:
		var fill := ROW_SELECT
		fill.a = level
		draw_rect(Rect2(s.position.x + 1, ry - 2, s.size.x - 2, row_h), fill)
		draw_rect(Rect2(s.position.x + 1, ry - 2, 1, row_h), lit)
	var bx := s.position.x + 5
	var by := ry + ((_text_h() - 5) >> 1)
	draw_rect(Rect2(bx, by, 5, 1), lit)
	draw_rect(Rect2(bx, by + 4, 5, 1), lit)
	draw_rect(Rect2(bx, by + 1, 1, 3), lit)
	draw_rect(Rect2(bx + 4, by + 1, 1, 3), lit)
	if GameSettings.dev_mode:
		var tick := DEV_TUBE
		tick.a = level
		draw_rect(Rect2(bx + 1, by + 1, 3, 3), tick)
	_draw_neon(_txt("DEVMODE", settings_big), Vector2i(bx + 8, ry), level * (1.0 if on else 0.6),
			0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)


func _update_dev_sign(delta: float) -> void:
	var on := GameSettings.dev_mode
	if on and not _dev_was_on:
		_dev_light.strike()
	elif not on and _dev_was_on:
		_dev_light.turn_off()
	_dev_was_on = on
	_dev_light.update(delta)


## Small red neon "DEV MODE ENABLED" in the top right, on two little wall brackets.
func _draw_dev_sign() -> void:
	var level := _dev_light.level
	if level <= 0.0:
		return
	var dims: Vector2i = _dev_text.dims
	var pos := Vector2i(int(_screen_size().x) - dims.x - 8, 7)
	for bx in [pos.x - 4, pos.x + dims.x + 2]:
		draw_rect(Rect2(bx, pos.y - 2, 2, dims.y + 4), TRUSS_DARK)
		draw_rect(Rect2(bx, pos.y - 2, 2, 1), TRUSS_MID)
		draw_rect(Rect2(bx + 1, pos.y + (dims.y >> 1), 2, 1), TRUSS_MID)
	var ms := Time.get_ticks_msec()
	var hum := 0.9 + 0.1 * sin(ms * 0.04)
	# Now and then the tube stutters.
	if int(ms / 90.0) % 47 == 0:
		hum *= 0.3
	_draw_neon(_dev_text, pos, level * hum, 1.0, DEV_TUBE, DEV_CORE, DEV_GHOST)


func _make_brightness_overlay() -> void:
	var layer := CanvasLayer.new()
	# Above the world and the HUD, so brightness covers everything on screen.
	layer.layer = 120
	add_child(layer)
	_brightness_rect = ColorRect.new()
	_brightness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brightness_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = BRIGHTNESS_SHADER
	var overlay_mat := ShaderMaterial.new()
	overlay_mat.shader = shader
	_brightness_rect.material = overlay_mat
	layer.add_child(_brightness_rect)
	_update_brightness()


## Pushes brightness and the colorblind filter to the screen overlay, and hides it when it
## would change nothing.
func _update_brightness() -> void:
	var gamma := GameSettings.brightness_gamma()
	var filter := int(GameSettings.colorblind)
	if GameSettings.colorblind_strength <= 0.001:
		filter = 0
	_brightness_rect.visible = absf(gamma - 1.0) > 0.001 or filter > 0
	var overlay_mat := _brightness_rect.material as ShaderMaterial
	overlay_mat.set_shader_parameter("gamma", gamma)
	overlay_mat.set_shader_parameter("colorblind", filter)
	overlay_mat.set_shader_parameter("strength", GameSettings.colorblind_strength)


## Prepared text for strings that change at runtime, cached. Small 3x5 font unless big.
func _txt(text: String, big: bool = false) -> Dictionary:
	var cache_key := ("B:" if big else "S:") + text
	if not _text_cache.has(cache_key):
		_text_cache[cache_key] = _build_text(text, 1, 1, GLYPHS if big else SMALL_GLYPHS)
	return _text_cache[cache_key]


## A gap the width of a normal glyph, for characters the font doesn't have.
func _blank_glyph(font: Dictionary) -> Array:
	var rows: Array = []
	for row in font["O"]:
		rows.append(".".repeat((row as String).length()))
	return rows


## Scrambled glass while the display changes screen: torn bright lines and static.
func _draw_glitch(s: Rect2i, level: float) -> void:
	var strength := _glitch_left / GLITCH_TIME
	var line := PHOSPHOR
	for k in 7:
		var y := s.position.y + _rng.randi_range(0, s.size.y - 1)
		var x := s.position.x + _rng.randi_range(0, s.size.x >> 1)
		line.a = level * strength * _rng.randf_range(0.15, 0.5)
		draw_rect(Rect2(x, y, _rng.randi_range(10, s.size.x - (x - s.position.x)), 1), line)
	var speck := PHOSPHOR_CORE
	for k in 40:
		speck.a = level * strength * _rng.randf_range(0.1, 0.5)
		var q := s.position + Vector2i(_rng.randi_range(0, s.size.x - 1),
				_rng.randi_range(0, s.size.y - 1))
		draw_rect(Rect2(Vector2(q), Vector2.ONE), speck)


# --- Save slots ------------------------------------------------------------------------------


## Confirm on the load or save screen: a slot, or the page row (which turns the page).
func _slot_confirm() -> void:
	if _focus >= SAVE_SLOTS.PAGE_SIZE:
		_turn_page(1)
		return
	var index := _slot_page * SAVE_SLOTS.PAGE_SIZE + _focus
	var empty := SAVE_SLOTS.is_empty(index)
	if _mode == Mode.NEW_GAME:
		# Picking a slot for a new game isn't wired yet: the screen just glitches.
		(_panels[_panel_index()].light as NeonLight).fault(0.2)
		_glitch_left = GLITCH_TIME
		return
	if _mode == Mode.SAVE:
		if empty:
			_save_into(index)
		else:
			# Something's there already: ask before writing over it. CANCEL comes up first.
			_slot_box = {"slot": index, "choice": 0, "armed": false}
			_glitch_left = GLITCH_TIME * 0.6
		return
	if empty:
		# Nothing to load: the screen just glitches.
		(_panels[_panel_index()].light as NeonLight).fault(0.2)
		return
	_slot_box = {"slot": index, "choice": 0, "armed": false}
	_glitch_left = GLITCH_TIME * 0.6


## Input while a slot's choice box is up: left/right pick, confirm applies, back closes it.
func _slot_box_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_left", true) or event.is_action_pressed("menu_right", true):
		_slot_box.choice = 1 - int(_slot_box.choice)
		_slot_box.armed = false
	elif event.is_action_pressed("menu_confirm"):
		var index := int(_slot_box.slot)
		var right := int(_slot_box.choice) == 1
		if _mode == Mode.SAVE:
			_slot_box = {}
			if right:
				_save_into(index)
		elif not right:
			_slot_box = {}
			_load_slot(index)
		elif not bool(_slot_box.armed):
			# Delete asks twice.
			_slot_box.armed = true
		else:
			_slot_box = {}
			SAVE_SLOTS.delete(index)
			_glitch_left = GLITCH_TIME
			var spot := Vector2(_slot_rect(_panel_rect(_panel_index()), index % 3).get_center())
			_sparks.emit(spot, 4, -PI / 2.0, 1.3, 20.0, 50.0, 0.12, 0.3)
	elif event.is_action_pressed("pause_menu") or event.is_action_pressed("menu_back"):
		_slot_box = {}
	else:
		return
	get_viewport().set_input_as_handled()


func _turn_page(direction: int) -> void:
	_slot_page = posmod(_slot_page + direction, SAVE_SLOTS.PAGE_COUNT)
	(_page_press[0 if direction < 0 else 1]).play([
		{"to": 1.0, "dur": 0.03, "ease": 2.0},
		{"dur": 0.08},
		{"to": 0.0, "dur": 0.05},
	])
	_glitch_left = GLITCH_TIME * 0.5


func _save_into(index: int) -> void:
	var data := SAVE_SLOTS.capture(player, _clock(), str(_save_info.get("area", "")),
			str(_save_info.get("station", "")))
	SAVE_SLOTS.store(index, data)
	_saved_slot = index
	_saved_left = SAVED_TIME
	_glitch_left = GLITCH_TIME
	var r := _slot_rect(_panel_rect(_panel_index()), index % SAVE_SLOTS.PAGE_SIZE)
	_sparks.emit(Vector2(r.end.x - 8, r.position.y + 1), 4, -PI / 2.0, 1.2, 20.0, 55.0, 0.12, 0.3)


## Loads a slot and puts the menu away; the robot wakes up where the slot was saved. Once dead,
## the scene is loaded fresh instead, the way the main menu loads a save.
func _load_slot(index: int) -> void:
	if _dead:
		_reload_slot(index)
		return
	SAVE_SLOTS.set_active(index)
	SAVE_SLOTS.apply(SAVE_SLOTS.get_slot(index), player, _clock())
	close()


## Dead: back to the last save station, i.e. the save being played (or else the newest one). With
## no save at all, the area starts over.
func _reload_last_station() -> void:
	var index := SAVE_SLOTS.get_active()
	if SAVE_SLOTS.is_empty(index):
		index = SAVE_SLOTS.latest()
	if index >= 0:
		_reload_slot(index)
		return
	SAVE_SLOTS.pending_load = {}
	_leave_dead(get_tree().current_scene.scene_file_path)


func _reload_slot(index: int) -> void:
	var data := SAVE_SLOTS.get_slot(index)
	SAVE_SLOTS.set_active(index)
	SAVE_SLOTS.pending_load = data.duplicate(true)
	var scene := str(data.get("scene", ""))
	if scene.is_empty():
		scene = get_tree().current_scene.scene_file_path
	_leave_dead(scene)


## Leaves the dead game for scene: the chosen plaque (or display) shorts out, then it loads.
func _leave_dead(scene: String) -> void:
	if _exiting:
		return
	_exiting = true
	_glitch_left = GLITCH_TIME * 3.0
	var spot := Vector2.ZERO
	if _mode == Mode.BUTTONS:
		(_buttons[selected].light as NeonLight).fault(EXIT_DELAY)
		var r := _button_rect(selected)
		spot = Vector2(r.position) + Vector2(1, HALF_PLAQUE_H)
	else:
		(_panels[_panel_index()].light as NeonLight).fault(EXIT_DELAY)
		var r := _panel_rect(_panel_index())
		spot = Vector2(r.position) + Vector2(1, _rng.randi_range(PANEL_CHAMFER, 40))
	_sparks.emit(spot, 6, PI, 1.2, 20.0, 60.0, 0.15, 0.35)
	get_tree().create_timer(EXIT_DELAY, true).timeout.connect(_change_scene.bind(scene))


func _change_scene(scene: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


func _clock() -> Node:
	if status_panel != null:
		return status_panel
	return get_parent().get_node_or_null("StatusPanel") if get_parent() != null else null


## The k-th slot box on the page, for the display whose housing is at panel.
func _slot_rect(panel: Rect2i, k: int) -> Rect2i:
	var s := Rect2i(panel.position + panel_screen.position, panel_screen.size)
	return _slot_box_rect(s, k)


func _slot_box_rect(s: Rect2i, k: int) -> Rect2i:
	var y := s.position.y + slot_top + k * (slot_h + slot_gap)
	return Rect2i(s.position.x + 3, y, s.size.x - 6, slot_h)


## The load and save screens: three slot boxes and the page row under them.
func _draw_slots(s: Rect2i, level: float, active: bool) -> void:
	for k in SAVE_SLOTS.PAGE_SIZE:
		_draw_slot(s, k, level, active)
	_draw_page_row(s, level, active)


func _draw_slot(s: Rect2i, k: int, level: float, active: bool) -> void:
	var index := _slot_page * SAVE_SLOTS.PAGE_SIZE + k
	var r := _slot_box_rect(s, k)
	var on := active and _focus == k
	var data := SAVE_SLOTS.get_slot(index)
	var lit := PHOSPHOR
	lit.a = level
	if on:
		var fill := ROW_SELECT
		fill.a = level
		draw_rect(Rect2(r), fill)
		draw_rect(Rect2(r), lit, false, 1.0)
		draw_rect(Rect2(r.position.x, r.position.y, 2, r.size.y), lit)
	else:
		# Dotted frame.
		var dotted := PHOSPHOR_DIM
		dotted.a = level * 0.8
		for x in range(r.position.x, r.end.x, 2):
			draw_rect(Rect2(x, r.position.y, 1, 1), dotted)
			draw_rect(Rect2(x, r.end.y - 1, 1, 1), dotted)
		for y in range(r.position.y, r.end.y, 2):
			draw_rect(Rect2(r.position.x, y, 1, 1), dotted)
			draw_rect(Rect2(r.end.x - 1, y, 1, 1), dotted)
	var bright := level * (1.0 if on else 0.6)
	_draw_neon(_txt("%02d" % (index + 1)), r.position + Vector2i(5, 4), bright * 0.7, 0.0,
			PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)

	# Tag in the top right: SAVED blinks after a save, otherwise ACTIVE marks the active slot.
	var tag := ""
	if index == _saved_slot and _saved_left > 0.0:
		if fmod(_saved_left, 0.3) > 0.1:
			tag = "SAVED"
	elif index == SAVE_SLOTS.get_active():
		tag = "ACTIVE"
	if tag != "":
		var t := _txt(tag)
		var box := Rect2i(r.end.x - int(t.dims.x) - 8, r.position.y + 3, int(t.dims.x) + 4, 7)
		var plate := PHOSPHOR if tag == "SAVED" else PHOSPHOR_DIM
		plate.a = level
		draw_rect(Rect2(box), plate)
		_draw_neon(t, box.position + Vector2i(2, 1), level, 0.0, PHOSPHOR_CORE, PHOSPHOR_CORE,
				SCREEN_BG)

	if data.is_empty():
		var empty := _txt("EMPTY")
		var ex: int = r.position.x + ((r.size.x - int(empty.dims.x)) >> 1)
		_draw_neon(empty, Vector2i(ex, r.position.y + 18), level * (0.6 if on else 0.3), 0.0,
				PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
	else:
		var area := _txt(str(data.get("area", "")).to_upper(), true)
		_draw_neon(area, r.position + Vector2i(5, 12), bright, 1.0 if on else 0.0, PHOSPHOR,
				PHOSPHOR_CORE, SCREEN_BG)
		var station := _txt(str(data.get("station", "")).to_upper())
		_draw_neon(station, r.position + Vector2i(5, 22), bright * 0.85, 0.0, PHOSPHOR,
				PHOSPHOR_CORE, SCREEN_BG)
		var date := _txt(str(data.get("date", "")))
		_draw_neon(date, r.position + Vector2i(5, 29), bright * 0.7, 0.0, PHOSPHOR,
				PHOSPHOR_CORE, SCREEN_BG)
		var time := _txt(str(data.get("time", "")))
		_draw_neon(time, Vector2i(r.end.x - 5 - int(time.dims.x), r.position.y + 29),
				bright * 0.7, 0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)

	if not _slot_box.is_empty() and int(_slot_box.slot) == index:
		_draw_slot_box(r, level)


## The choice box over a slot: LOAD / DELETE on the load screen, CANCEL / SAVE on the save one.
func _draw_slot_box(r: Rect2i, level: float) -> void:
	draw_rect(Rect2(r), Color(0.01, 0.025, 0.03, 0.96))
	var lit := PHOSPHOR
	lit.a = level
	draw_rect(Rect2(r), lit, false, 1.0)
	var saving := _mode == Mode.SAVE
	var title := _txt(("OVERWRITE SLOT %02d?" if saving else "SLOT %02d") % (int(_slot_box.slot) + 1))
	_draw_neon(title, r.position + Vector2i(6, 5), level, 0.0, PHOSPHOR, PHOSPHOR_CORE, SCREEN_BG)
	var labels: Array[String] = ["CANCEL", "SAVE"]
	if not saving:
		labels = ["LOAD", "DELETE"]
	var armed := bool(_slot_box.armed)
	if armed:
		labels[1] = "SURE?"
	var plate_w := 46
	for i in 2:
		var px := r.position.x + 8 if i == 0 else r.end.x - 8 - plate_w
		var plate := Rect2i(px, r.position.y + 17, plate_w, 14)
		var picked := int(_slot_box.choice) == i
		var red := i == 1 and not saving
		var tube := DEV_TUBE if red else PHOSPHOR
		var core := DEV_CORE if red else PHOSPHOR_CORE
		var fill := Color(0.2, 0.04, 0.03) if red else ROW_SELECT
		if picked:
			fill.a = level
			draw_rect(Rect2(plate), fill)
		var edge := tube
		edge.a = level * (1.0 if picked else 0.4)
		draw_rect(Rect2(plate), edge, false, 1.0)
		if picked and armed and i == 1 and fmod(_time, 0.4) < 0.15:
			continue
		var t := _txt(labels[i], true)
		var tx: int = plate.position.x + ((plate_w - int(t.dims.x)) >> 1)
		_draw_neon(t, Vector2i(tx, plate.position.y + 4), level * (1.0 if picked else 0.5),
				1.0 if picked else 0.0, tube, core, SCREEN_BG)


## Left button, page number, right button.
func _draw_page_row(s: Rect2i, level: float, active: bool) -> void:
	var on := active and _focus == SAVE_SLOTS.PAGE_SIZE
	var y := s.position.y + page_row_y
	var cx := s.position.x + (s.size.x >> 1)
	if on:
		var fill := ROW_SELECT
		fill.a = level
		draw_rect(Rect2(s.position.x + 3, y - 2, s.size.x - 6, PAGE_BUTTON.y + 4), fill)
	for i in 2:
		var bx := cx - 34 if i == 0 else cx + 34 - PAGE_BUTTON.x
		var b := Rect2i(bx, y, PAGE_BUTTON.x, PAGE_BUTTON.y)
		var pressed := _page_press[i].value > 0.5
		var edge := PHOSPHOR if on else PHOSPHOR_DIM
		edge.a = level
		if pressed:
			draw_rect(Rect2(b), edge)
		else:
			draw_rect(Rect2(b), edge, false, 1.0)
			# A second line along the bottom makes it read as a button.
			draw_rect(Rect2(b.position.x + 1, b.end.y - 2, b.size.x - 2, 1), edge)
		var arrow := _arrow_texts[i]
		var ap := b.position + Vector2i((b.size.x - int(arrow.dims.x)) >> 1, 1)
		if pressed:
			_draw_neon(arrow, ap, 1.0, 0.0, SCREEN_BG, SCREEN_BG, SCREEN_BG)
		else:
			_draw_neon(arrow, ap, level * (1.0 if on else 0.6), 0.0, PHOSPHOR, PHOSPHOR_CORE,
					SCREEN_BG)
	var number := _page_texts[_slot_page]
	_draw_neon(number, Vector2i(cx - (int(number.dims.x) >> 1), y + 2), level, 1.0, PHOSPHOR,
			PHOSPHOR_CORE, SCREEN_BG)
	# Three pips under the number, one per page.
	for p in _page_texts.size():
		var pip := PHOSPHOR if p == _slot_page else PHOSPHOR_DIM
		pip.a = level
		draw_rect(Rect2(cx - 4 + p * 3, y + PAGE_BUTTON.y + 1, 2, 1), pip)


func _panel_polygon(p: Vector2i) -> PackedVector2Array:
	var w := panel_size.x
	var h := panel_size.y
	var c := PANEL_CHAMFER
	var o := Vector2(p)
	return PackedVector2Array([
		o + Vector2(c, 0), o + Vector2(w, 0), o + Vector2(w, h), o + Vector2(c, h),
		o + Vector2(0, h - c), o + Vector2(0, c),
	])


func _roll_panel_grime(rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var grime: Array = []
	var keep_clear := Rect2(panel_screen.grow(1))
	var title := Rect2(9, 3, panel_size.x - 16, 13)
	var poly := _panel_polygon(Vector2i.ZERO)
	var tries := 0
	while grime.size() < 70 and tries < 5000:
		tries += 1
		var g := Vector2(
			rng.randi_range(1, panel_size.x - 5), rng.randi_range(1, panel_size.y - 2)
		)
		if keep_clear.has_point(g) or title.has_point(g):
			continue
		if not Geometry2D.is_point_in_polygon(g, poly):
			continue
		grime.append([g, RUST_COLORS[rng.randi_range(0, RUST_COLORS.size() - 1)]])
		# Rust bleeds down from rivets and seams.
		var run := rng.randi_range(1, 3) if rng.randf() < 0.35 else 0
		for k in run:
			if g.y + k + 1 < panel_size.y - 1:
				grime.append([g + Vector2(0, k + 1), RUST_COLORS[1]])
	return grime


# --- Steam and sparks ------------------------------------------------------------------------


## Puffs count steam blobs from origin, aimed at angle (radians, 0 = right, -PI/2 = up).
func _vent(origin: Vector2, angle: float, count: int, speed: float) -> void:
	for k in count:
		var a := angle + _rng.randf_range(-0.45, 0.45)
		var life := _rng.randf_range(0.35, 0.8)
		_steam.append({
			"pos": origin + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)),
			"vel": Vector2.from_angle(a) * speed * _rng.randf_range(0.5, 1.3),
			"life": life,
			"max": life,
			"grow": _rng.randf_range(2.0, 4.0),
		})


func _update_steam(delta: float) -> void:
	var keep := pow(0.02, delta)
	var i := _steam.size() - 1
	while i >= 0:
		var s := _steam[i]
		s.life -= delta
		if s.life <= 0.0:
			_steam.remove_at(i)
		else:
			# Strong drag, then it lifts and spreads.
			s.vel = s.vel * keep + Vector2(_rng.randf_range(-6, 6), -14.0) * delta
			s.pos += s.vel * delta
		i -= 1


func _draw_steam() -> void:
	for s in _steam:
		var t: float = 1.0 - s.life / s.max
		var side := 1 + int(t * s.grow)
		var c := STEAM_COLOR
		c.a = 0.4 * (1.0 - t) * (1.0 - t)
		var p := (s.pos as Vector2).floor() - Vector2.ONE * floorf(side * 0.5)
		draw_rect(Rect2(p, Vector2(side, side)), c)
		if side >= 3:
			# Rough the square's corners off so puffs read as clouds.
			var clear := c
			clear.a *= 0.5
			draw_rect(Rect2(p + Vector2(1, -1), Vector2(side - 2, 1)), clear)
			draw_rect(Rect2(p + Vector2(1, side), Vector2(side - 2, 1)), clear)


func _emit_ambient_sparks(delta: float) -> void:
	_panel_spark_wait -= delta
	if _panel_spark_wait <= 0.0:
		_panel_spark_wait = _rng.randf_range(spark_interval.x * 2.0, spark_interval.y * 2.5)
		var index := _panel_index()
		if index >= 0 and (_panels[index].light as NeonLight).level > 0.5:
			# A loose contact on the housing's leading edge.
			var r := _panel_rect(index)
			var spot := Vector2(r.position) + Vector2(1, _rng.randi_range(PANEL_CHAMFER, 40))
			_sparks.emit(spot, _rng.randi_range(1, 2), PI + _rng.randf_range(-0.6, 0.6), 0.8,
					15.0, 40.0, 0.12, 0.28)
	_button_spark_wait -= delta
	var b := _buttons[selected]
	if _button_spark_wait <= 0.0:
		_button_spark_wait = _rng.randf_range(spark_interval.x, spark_interval.y)
		if (b.light as NeonLight).level > 0.5:
			var r := _button_rect(selected)
			var spots := [
				Vector2(r.position) + Vector2(1, PLAQUE_CHAMFER),
				Vector2(r.position) + Vector2(TEXT_X + _rng.randi_range(0, 40), 3),
				Vector2(r.position) + Vector2(PLAQUE_SIZE.x - 2, PLAQUE_SIZE.y - 2),
			]
			var spot: Vector2 = spots[_rng.randi_range(0, spots.size() - 1)]
			_sparks.emit(spot, _rng.randi_range(1, 3), -PI / 2.0 + _rng.randf_range(-1, 1), 0.9,
					20.0, 55.0, 0.12, 0.3)
	_sign_spark_wait -= delta
	if _sign_spark_wait <= 0.0:
		_sign_spark_wait = _rng.randf_range(spark_interval.x * 1.5, spark_interval.y * 1.8)
		if _sign_light.level > 0.5 and not _sign_letters.is_empty():
			var r := _sign_rect()
			var index := _faulty_letter if _rng.randf() < 0.5 else _rng.randi_range(
					0, _sign_letters.size() - 1)
			var letter := _sign_letters[index]
			var spot := Vector2(r.position + SIGN_PAD) + Vector2(
					letter.x + _rng.randi_range(0, letter.w), _rng.randi_range(0, _sign_text_size.y - 1))
			_sparks.emit(spot, _rng.randi_range(1, 3), PI / 2.0, 1.2, 15.0, 45.0, 0.15, 0.35)
	# Now and then a drop of melt or a chip falls off an icicle.
	_ice_wait -= delta
	if _ice_wait <= 0.0:
		_ice_wait = _rng.randf_range(1.2, 3.5)
		var icicles: Array = []
		var base := Vector2.ZERO
		var index := _panel_index()
		if index >= 0:
			icicles = _panel_icicles[index]
			var pr := _panel_rect(index)
			base = Vector2(pr.position.x + 5, pr.end.y)
		elif _mode == Mode.BUTTONS:
			var i := _rng.randi_range(0, _buttons.size() - 1)
			icicles = _buttons[i].icicles
			var br := _button_rect(i)
			base = Vector2(br.position.x, br.end.y)
		if not icicles.is_empty():
			var ic: Array = icicles[_rng.randi_range(0, icicles.size() - 1)]
			_ice.emit(base + Vector2(int(ic[0]), int(ic[1])), 1, PI / 2.0, 0.2, 2.0, 8.0, 0.5,
					1.0)


## The faulty letter cuts out for a moment now and then, with a fizz.
func _update_fault(delta: float) -> void:
	if _fault_left > 0.0:
		_fault_left -= delta
		return
	if not is_open or _sign_light.level < 0.9:
		return
	_fault_wait -= delta
	if _fault_wait <= 0.0:
		_fault_wait = _rng.randf_range(1.2, 4.0)
		_fault_left = _rng.randf_range(0.08, 0.3)
		if _faulty_letter >= 0 and _rng.randf() < 0.6:
			var r := _sign_rect()
			var letter := _sign_letters[_faulty_letter]
			var spot := Vector2(r.position + SIGN_PAD)
			spot += Vector2(letter.x + letter.w * 0.5, _sign_text_size.y)
			_sparks.emit(spot, 2, PI / 2.0, 1.0, 15.0, 40.0, 0.1, 0.3)


func _ensure_actions() -> void:
	_add_action("pause_menu", [KEY_ESCAPE], [JOY_BUTTON_START])
	_add_action("menu_up", [KEY_UP], [JOY_BUTTON_DPAD_UP])
	_add_action("menu_down", [KEY_DOWN], [JOY_BUTTON_DPAD_DOWN])
	_add_action("menu_confirm", [KEY_A, KEY_Z, KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A])
	_add_action("menu_back", [KEY_BACKSPACE], [JOY_BUTTON_B])
	_add_action("menu_left", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT])
	_add_action("menu_right", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT])


func _add_action(action: StringName, keys: Array, buttons: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)
	for button in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = button
		InputMap.action_add_event(action, j)


## Plays a list of mechanical steps on one value (see the step scripts above).
class MechTrack:
	var value: float = 0.0
	## Pixels of chatter the current step asks for.
	var shake: int = 0
	var _steps: Array = []
	var _index: int = 0
	var _t: float = 0.0
	var _from: float = 0.0

	func play(steps: Array) -> void:
		_steps = steps
		_index = 0
		_t = 0.0
		_from = value
		shake = 0

	func snap(to: float) -> void:
		_steps = []
		_index = 0
		value = to
		_from = to
		shake = 0

	func is_busy() -> bool:
		return _index < _steps.size()

	## Advances by delta. Returns the tags of the steps that finished.
	func update(delta: float) -> Array[String]:
		var tags: Array[String] = []
		var left := delta
		while _index < _steps.size():
			var step: Dictionary = _steps[_index]
			var dur: float = step.get("dur", 0.0)
			var to: float = step.get("to", _from)
			shake = step.get("shake", 0)
			if left < dur - _t:
				_t += left
				value = lerpf(_from, to, ease(_t / dur, step.get("ease", 1.0)))
				return tags
			left -= dur - _t
			value = to
			_from = to
			_t = 0.0
			_index += 1
			if step.has("tag"):
				tags.append(step.tag)
		shake = 0
		return tags


## Neon tube brightness: strikes on with a stutter, cuts out with a flicker.
class NeonLight:
	var level: float = 0.0
	var _on: bool = false
	var _t: float = 0.0
	var _fault_left: float = 0.0
	var _boost_left: float = 0.0

	func strike() -> void:
		_on = true
		_t = 0.0

	func turn_off() -> void:
		if _on:
			_on = false
			_t = 0.0

	func snap_off() -> void:
		_on = false
		_t = 99.0
		level = 0.0

	## Cuts out briefly, as when a dead circuit is pressed.
	func fault(duration: float) -> void:
		_fault_left = duration

	## A quick double flash, when the tube is selected.
	func flicker_bright() -> void:
		_boost_left = 0.1

	func update(delta: float) -> void:
		_t += delta
		var k := int(_t / PauseMenu.STRIKE_STEP)
		if _on:
			level = PauseMenu.STRIKE_PATTERN[k] if k < PauseMenu.STRIKE_PATTERN.size() else 1.0
		else:
			level = PauseMenu.SHUTOFF_PATTERN[k] if k < PauseMenu.SHUTOFF_PATTERN.size() else 0.0
		if _boost_left > 0.0:
			_boost_left -= delta
			if _on and _t > 0.3:
				level = 0.5 if fmod(_boost_left, 0.05) < 0.025 else 1.0
		if _fault_left > 0.0:
			_fault_left -= delta
			level *= 0.1 if fmod(_fault_left, 0.07) < 0.045 else 0.7
