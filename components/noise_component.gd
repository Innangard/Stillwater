class_name NoiseComponent
extends Node
## Player's transient noise stat. State-driven: each frame, noise is
## recomputed from "what is the player doing right now?" — there is no
## decay-back-to-zero behavior. Stop the activity, the noise is gone.
##
## Two kinds of sources:
##   - SUSTAINED (movement). Has a per-second fill rate and a hard cap.
##     Rises toward the cap while active, snaps to 0 when removed.
##   - BURST (dash, attacks). Holds its level for a short TTL then clears.
##     Stacks ON TOP of sustained level so a dash while running spikes
##     above the sustained cap.
##
## Total displayed noise = sustained_level + max(active burst levels),
## clamped to max_noise.

@export var max_noise: float = 100.0

# Sustained sources keyed by ID. Each value: { rate, cap, current }
# - rate:    pct/sec the level rises while this source is active
# - cap:     max contribution this source can make (in absolute units, 0..max_noise)
# - current: current contribution, in absolute units. Rises toward cap.
var _sustained: Dictionary = {}

# Burst sources. Each: { level, ttl }
# - level: absolute units to add while alive
# - ttl:   seconds remaining; when <= 0 the burst is removed
var _bursts: Dictionary = {}

# Used to compute "what changed" so we don't emit signals when nothing did.
var _last_emitted: float = -1.0


func _process(delta: float) -> void:
	# Tick sustained sources. Two paths:
	#   - Active (no linger pending): ramp toward cap.
	#   - Lingering: hold level, count down linger; clear when expired.
	var to_remove: Array = []
	for id in _sustained.keys():
		var s: Dictionary = _sustained[id]
		if s.get("linger", 0.0) > 0.0:
			s.linger -= delta
			if s.linger <= 0.0:
				to_remove.append(id)
		else:
			s.current = minf(s.cap, s.current + s.rate * delta)
	for id in to_remove:
		_sustained.erase(id)

	# Tick bursts down. Bursts hold full level until ttl expires, then clear.
	var expired: Array = []
	for id in _bursts.keys():
		var b: Dictionary = _bursts[id]
		b.ttl -= delta
		if b.ttl <= 0.0:
			expired.append(id)
	for id in expired:
		_bursts.erase(id)

	_emit_if_changed()


# ============================================================================
# SUSTAINED SOURCES
# ============================================================================

## Start (or update) a sustained noise source. The source ramps from its
## current level up to `cap` at `rate_per_sec` per second.
##   id: short string ("move", "armor"). Same id replaces the old entry.
##   rate_per_sec: how fast the bar fills toward the cap, in absolute units.
##   cap: max contribution from this source, in absolute units (0..max_noise).
##
## If a linger was previously started for this id, it's cancelled — the
## source resumes ramping from wherever it was held.
func start_sustained(id: String, rate_per_sec: float, cap: float) -> void:
	if rate_per_sec <= 0.0 or cap <= 0.0:
		stop_sustained(id)
		return
	var existing: Dictionary = _sustained.get(id, {"current": 0.0})
	_sustained[id] = {
		"rate": rate_per_sec,
		"cap": cap,
		"current": existing.get("current", 0.0),
		"linger": 0.0,
	}


## Stop a sustained source. Default behavior SNAPS to 0 immediately.
## Pass linger_seconds > 0 to hold the current level briefly before
## clearing — useful for masking input-frame gaps (e.g., switching
## directions: A released then D pressed produces a momentary zero-input
## frame that we don't want to read as "stopped moving").
func stop_sustained(id: String, linger_seconds: float = 0.0) -> void:
	if not _sustained.has(id):
		return
	if linger_seconds <= 0.0:
		_sustained.erase(id)
	else:
		var s: Dictionary = _sustained[id]
		# Only set linger if not already lingering — calling stop twice
		# in quick succession shouldn't extend the linger.
		if s.get("linger", 0.0) <= 0.0:
			s.linger = linger_seconds
	_emit_if_changed()


# ============================================================================
# BURSTS
# ============================================================================

## Add a one-shot burst that holds for `ttl` seconds then disappears.
## Multiple bursts can coexist; we use the max of active bursts (not sum)
## so spamming dashes doesn't multiply.
func add_burst(id: String, level: float, ttl: float = 0.4) -> void:
	if level <= 0.0 or ttl <= 0.0:
		return
	# If a burst with this ID already exists, take whichever is louder/longer.
	var existing: Dictionary = _bursts.get(id, {"level": 0.0, "ttl": 0.0})
	_bursts[id] = {
		"level": maxf(existing.get("level", 0.0), level),
		"ttl": maxf(existing.get("ttl", 0.0), ttl),
	}
	_emit_if_changed()


# ============================================================================
# QUERIES
# ============================================================================

## Total noise: sum of sustained contributions + sum of distinct burst
## sources. Bursts with different IDs are independent and stack. Repeated
## bursts on the same ID don't compound (max-of), so spamming the same
## attack doesn't multiply its noise — but firing primary + secondary
## + spell simultaneously sums their three burst levels.
func current() -> float:
	var sustained_total: float = 0.0
	for s in _sustained.values():
		sustained_total += s.current
	var burst_total: float = 0.0
	for b in _bursts.values():
		burst_total += b.level
	return clampf(sustained_total + burst_total, 0.0, max_noise)


## 0..1 fraction of max — used by enemies as a detection multiplier.
func factor() -> float:
	return current() / max_noise if max_noise > 0.0 else 0.0


# ============================================================================
# INTERNAL
# ============================================================================

func _emit_if_changed() -> void:
	var now: float = current()
	if absf(now - _last_emitted) > 0.05 or now == 0.0 and _last_emitted != 0.0:
		_last_emitted = now
		EventBus.noise_changed.emit(now, max_noise)
