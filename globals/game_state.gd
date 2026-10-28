extends Node
## Persistent state that survives death.
##
## Persistence model (per current design):
##   PERSISTS across death (these live here, not in RunState):
##     - Currency
##     - Story flags (dialogue beats heard, one-time events triggered)
##     - Activated arches (so the South Arch stays your respawn anchor
##       across deaths once you've woken it)
##     - Boss kill records
##     - Kennings unlocked AND the player's equipped loadout (stored
##       under _kenning_unlocked_ids / _kenning_equipped_ids inside
##       story_flags by KenningManager — names earned by the player are
##       a meta-progression story beat, never wiped by death)
##     - Quest state (active + completed; QuestManager mirrors these in
##       _quest_active_data / _quest_completed_ids inside story_flags)
##   RESETS on death (RunState):
##     - Inventory, equipped weapons & armor
##     - HP, smell
##
## Quit-and-resume saves both GameState AND RunState through the save
## file (stub at the bottom — flesh out when needed). Death-on-island
## only resets RunState.

var soul_currency: int = 0
var death_count: int = 0

# --- Story / progress (persists across deaths) ---
## Generic flag dictionary. Use for dialogue beats, one-time events,
## arch activations ("arch_activated_<id>"), boss kills ("boss_dead_<id>"),
## etc. The set/has/get helpers below are the public API.
var story_flags: Dictionary = {}

## Most-recently activated arch. Defaults to "south_arch" because the
## player begins their journey AT the south arch — they wake there with
## the world's first anchor already known to them. Death respawns at the
## last activated arch, so this default ensures a sensible starting
## point even before the player interacts with any arch in the world.
##
## Empty string is no longer used as a "first-run-ever" sentinel since
## starter gear was removed; the south arch is just always-known.
var last_arch_id: String = "south_arch"


func _ready() -> void:
	# Pre-mark the south arch's activation flag so that pressing E on it
	# doesn't re-trigger first-activation dialogue (which is gated on
	# `not has_flag("arch_activated_south_arch")`). The arch already
	# visually shows as activated because last_arch_id matches its id.
	#
	# Subsequent arches in the world are still un-activated by default —
	# the player has to discover and wake them in the usual way.
	story_flags["arch_activated_south_arch"] = true
	EventBus.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	death_count += 1


func add_currency(amount: int) -> void:
	soul_currency = max(0, soul_currency + amount)
	EventBus.currency_changed.emit(soul_currency)


func spend_currency(amount: int) -> bool:
	if soul_currency < amount:
		return false
	soul_currency -= amount
	EventBus.currency_changed.emit(soul_currency)
	return true


# ---------- Story flags ----------

func set_flag(flag: String, value: Variant = true) -> void:
	story_flags[flag] = value
	EventBus.story_flag_set.emit(flag, value)

func get_flag(flag: String, default: Variant = false) -> Variant:
	return story_flags.get(flag, default)

func has_flag(flag: String) -> bool:
	return story_flags.has(flag) and story_flags[flag] != false and story_flags[flag] != null


# ---------- Boss kills (convenience over story flags) ----------

func mark_boss_dead(boss_id: String) -> void:
	set_flag("boss_dead_" + boss_id, true)

func is_boss_dead(boss_id: String) -> bool:
	return has_flag("boss_dead_" + boss_id)


# ---------- Reset (used by SaveManager on slot switch / return to title) ----------

## Wipe every persistent field back to engine defaults. Called by
## SaveManager.reset_all_state when the player is leaving the current
## save (returning to title, loading a different slot, starting a new
## game). Restores the SAME initial state that GameState would have at
## a fresh game launch — including pre-marking the south arch flag,
## because that's an always-true invariant of the world design, not a
## save-specific datum.
##
## The old save_game / load_game stubs that used to live here were
## removed when SaveManager took over per-slot persistence; the entire
## save lifecycle is now SaveManager's responsibility.
func reset_to_defaults() -> void:
	soul_currency = 0
	death_count = 0
	story_flags.clear()
	last_arch_id = "south_arch"
	story_flags["arch_activated_south_arch"] = true
	EventBus.currency_changed.emit(soul_currency)
