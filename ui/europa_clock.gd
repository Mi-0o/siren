extends RefCounted
## The one Europa clock everything reads: the HUD clock in every area, and the main menu's sky.
## It is the same for every save and area. Each time the game boots it starts at a random time,
## then runs the whole time the game is open (menu included), whatever scenes come and go.
##
## A Europa day is 85 hours (00:00 to 84:59) and takes DAY_SECONDS of real time (one hour).
## 00:00 is sunrise; at 42:30, halfway, the sun sets behind Jupiter and night begins.
## Preload this script rather than naming a class, so it works before the editor's class cache
## catches up.

const DAY_MINUTES: float = 85.0 * 60.0
## Real seconds in one Europa day.
const DAY_SECONDS: float = 3600.0

## Dev menu: holds the clock at this many minutes past 00:00, or -1 to let it run.
static var override_minutes: float = -1.0
## Where this boot's clock started, picked at random the first time anything asks.
static var _start_minutes: float = -1.0


## Minutes past 00:00, Europa time.
static func minutes() -> float:
	if override_minutes >= 0.0:
		return override_minutes
	if _start_minutes < 0.0:
		_start_minutes = randf() * DAY_MINUTES
	var running := Time.get_ticks_msec() / 1000.0 / DAY_SECONDS * DAY_MINUTES
	return fmod(_start_minutes + running, DAY_MINUTES)


## How far through the day it is, from 0 (sunrise) to 1.
static func phase() -> float:
	return minutes() / DAY_MINUTES


## Dev menu: lets go of a held time so the clock runs on from it, instead of jumping back.
static func release() -> void:
	if override_minutes < 0.0:
		return
	var running := Time.get_ticks_msec() / 1000.0 / DAY_SECONDS * DAY_MINUTES
	_start_minutes = fposmod(override_minutes - running, DAY_MINUTES)
	override_minutes = -1.0
