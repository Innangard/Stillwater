extends Node
## Manages the three save slots: writes, reads, lists, deletes.
##
## ── Save file shape ─────────────────────────────────────────────────────
## Each slot is a single ConfigFile at user://save_slot_<N>.cfg with
## four sections:
##
##   [meta]       slot, version, timestamp, difficulty, scene_path,
##                scene_display, summary cache for title-screen rendering
##                (so listing slots doesn't have to hydrate every system)
##   [game_state] soul_currency, death_count, story_flags, last_arch_id
##   [run_state]  current_health, max_health, smell, world_seed,
##                dungeon_seeds, consumed_node_paths, kill counters,
##                inventory + equipment as resource-path references
##   [player]     position_x, position_y (so quit-and-resume lands the
##                player where they were, not at the scene spawn marker)
##
## Item / weapon / armor references are stored as the `.tres` resource
## path strings. On load we resolve them via load(path); a removed or
## renamed resource file silently drops from the loaded inventory, which
## is the right failure mode for a stale save (better than crashing).
##
## ── Auto-save policy ────────────────────────────────────────────────────
## Triggered automatically by:
##   - SceneTransition.go_to (after the new scene loads)
##   - Arch._activate (after the arch is awakened)
## The player can also trigger a save explicitly from the pause menu's
## "Save & Quit to Title" flow.
##
## ── Reset on title return ───────────────────────────────────────────────
## Returning to the title screen calls reset_all_state() which wipes
## every autoload's runtime state to defaults. This guarantees that
## loading a different save (or starting a new game) doesn't inherit
## any leftover data from the previous session — kennings, quests,
## inventory, currency, story flags, all reset before the new save's
## data is poured in.
##
## NOTE: No class_name — registered as autoload "SaveManager".

const SAVE_VERSION: int = 1
const SAVE_PATH_TEMPLATE: String = "user://save_slot_%d.cfg"
const NUM_SLOTS: int = 3
const TITLE_SCENE_PATH: String = "res://ui/title_screen.tscn"
## Default starting scene when a new save is created. Ginnungagap is
## the introductory void-between-worlds tutorial — the player reads
## the controls on the floor, then steps through a passage to south_cliff
## (where the south arch sits as the initial respawn anchor, the way
## play used to begin pre-tutorial). The tutorial passage sets the
## `tutorial_completed` story flag on transit, so any future system can
## detect "this save has been past the introduction" without ambiguity.
##
## Note that GameState.reset_to_defaults() wipes story_flags, so every
## new game (a fresh save slot) replays the tutorial. The flag is for
## within-session gating, not cross-save persistence.
const NEW_GAME_SCENE_PATH: String = "res://world/regions/ginnungagap.tscn"
const NEW_GAME_SCENE_DISPLAY: String = "Ginnungagap"


## Currently-loaded slot. Zero means "no save loaded yet"; the title
## screen runs in that state and auto-save is gated on this being > 0.
var current_slot: int = 0


## Catch the window-close request (Alt-F4, X button, OS signal) and
## auto-save before the engine shuts down. Without this, any progress
## since the last scene transition is silently lost on a non-menu quit.
## _notification fires even when the tree is paused (which it is when
## the pause menu is open), so the save happens regardless of game state.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if current_slot > 0:
			save_game(current_slot)

## When the next scene loads, RegionRoot consults this and (if set)
## teleports the player to this position instead of the spawn marker.
## Set by load_game and consumed by the next RegionRoot._ready. Stored
## here rather than on RunState because RunState resets on death, and
## the load-time teleport would be wiped if a death somehow happened
## before the consume — defensive, even if unlikely.
var pending_load_position: Vector2 = Vector2.ZERO
var has_pending_load_position: bool = false


# ============================================================================
# SLOT QUERIES (used by the title screen)
# ============================================================================

func save_path_for_slot(slot: int) -> String:
	return SAVE_PATH_TEMPLATE % slot


func save_exists(slot: int) -> bool:
	return FileAccess.file_exists(save_path_for_slot(slot))


## Lightweight read for the title screen: returns just the meta
## section as a Dictionary, without hydrating the rest of the systems.
## Empty dict means no save in this slot (or unreadable). Listing all
## three slots is cheap because we skip the heavy [run_state] block.
func get_slot_summary(slot: int) -> Dictionary:
	if not save_exists(slot):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(save_path_for_slot(slot)) != OK:
		return {}
	# Validate version. A mismatched-version save is shown as "Corrupt"
	# rather than crashing the title screen when a load is attempted.
	# (Future migrations can replace this with explicit upgrade paths.)
	var version: int = cfg.get_value("meta", "version", 0)
	if version != SAVE_VERSION:
		return {
			"corrupt": true,
			"version": version,
		}
	return {
		"slot": slot,
		"version": version,
		"difficulty": cfg.get_value("meta", "difficulty", DifficultySettings.Difficulty.NORMAL),
		"timestamp": cfg.get_value("meta", "timestamp", 0),
		"scene_display": cfg.get_value("meta", "scene_display", "Unknown"),
		"soul_currency": cfg.get_value("game_state", "soul_currency", 0),
		"death_count": cfg.get_value("game_state", "death_count", 0),
		"current_health": cfg.get_value("run_state", "current_health", 0.0),
		"max_health": cfg.get_value("run_state", "max_health", 100.0),
	}


# ============================================================================
# WRITE
# ============================================================================

## Save the current game state into the given slot. If slot is 0 (no
## active save) this is a no-op — auto-save fires at the title screen
## otherwise, and we don't want to manufacture a save without the player
## having chosen one. Pass an explicit slot for "Save As" semantics if
## that's ever exposed.
func save_game(slot: int = current_slot) -> bool:
	if slot <= 0 or slot > NUM_SLOTS:
		return false

	var cfg := ConfigFile.new()

	# --- [meta] ---
	cfg.set_value("meta", "slot", slot)
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "timestamp", int(Time.get_unix_time_from_system()))
	cfg.set_value("meta", "difficulty", DifficultySettings.current)
	# scene_path is the file we'll restore to on load. We snapshot it
	# from the current scene; if there's no current scene (e.g. saving
	# during a transition) fall back to the new-game starting scene so
	# the save still loads to *somewhere* runnable.
	var scene_path: String = NEW_GAME_SCENE_PATH
	var scene_display: String = NEW_GAME_SCENE_DISPLAY
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and current_scene.scene_file_path != "":
		scene_path = current_scene.scene_file_path
		scene_display = _pretty_scene_name(scene_path)
	cfg.set_value("meta", "scene_path", scene_path)
	cfg.set_value("meta", "scene_display", scene_display)

	# --- [game_state] ---
	cfg.set_value("game_state", "soul_currency", GameState.soul_currency)
	cfg.set_value("game_state", "death_count", GameState.death_count)
	cfg.set_value("game_state", "story_flags", GameState.story_flags)
	cfg.set_value("game_state", "last_arch_id", GameState.last_arch_id)

	# --- [run_state] ---
	# Snapshot active quests into story_flags first — QuestManager's
	# active_quests dict lives in RAM and only mirrors into flags when
	# something changes, so a save mid-quest would otherwise persist a
	# stale flag set. Calling _save_quests pushes the current dict into
	# the flags we're about to write.
	if QuestManager.has_method("_save_quests"):
		QuestManager._save_quests()
		# Re-read story_flags now that they've been updated.
		cfg.set_value("game_state", "story_flags", GameState.story_flags)

	cfg.set_value("run_state", "current_health", RunState.current_health)
	cfg.set_value("run_state", "max_health", RunState.max_health)
	cfg.set_value("run_state", "smell", RunState.smell)
	cfg.set_value("run_state", "world_seed", RunState.world_seed)
	cfg.set_value("run_state", "dungeon_seeds", RunState.dungeon_seeds)
	cfg.set_value("run_state", "consumed_node_paths", RunState.consumed_node_paths)
	cfg.set_value("run_state", "current_region", RunState.current_region)
	cfg.set_value("run_state", "run_kills_melee", RunState.run_kills_melee)
	cfg.set_value("run_state", "run_kills_ranged", RunState.run_kills_ranged)

	# Inventory: array of {path, count}. Resources without a resource_path
	# (i.e. authored only in-memory) get silently dropped — there's no
	# way to round-trip them through a save file anyway.
	var inv_data: Array = []
	for slot_entry in RunState.inventory:
		var item: Item = slot_entry.get("item")
		if item != null and item.resource_path != "":
			inv_data.append({
				"path": item.resource_path,
				"count": int(slot_entry.get("count", 1)),
			})
	cfg.set_value("run_state", "inventory", inv_data)

	# Rune collection — same shape as inventory save.
	var rune_data: Array = []
	for slot_entry in RunState.rune_collection:
		var item: Item = slot_entry.get("item")
		if item != null and item.resource_path != "":
			rune_data.append({
				"path": item.resource_path,
				"count": int(slot_entry.get("count", 1)),
			})
	cfg.set_value("run_state", "rune_collection", rune_data)

	# Equipment slots — store resource path or empty string.
	cfg.set_value("run_state", "primary_weapon", _path_of(RunState.primary_weapon))
	cfg.set_value("run_state", "secondary_weapon", _path_of(RunState.secondary_weapon))
	cfg.set_value("run_state", "prepared_primary", _path_of(RunState.prepared_primary))
	cfg.set_value("run_state", "prepared_secondary", _path_of(RunState.prepared_secondary))
	cfg.set_value("run_state", "helmet", _path_of(RunState.helmet))
	cfg.set_value("run_state", "chest", _path_of(RunState.chest))
	cfg.set_value("run_state", "boots", _path_of(RunState.boots))

	# --- [player] ---
	# Look up the live player node to snapshot its world position. If
	# nothing is in the player group (we're in a non-gameplay scene,
	# or the player hasn't spawned yet), we just skip — load_game will
	# fall back to the scene's spawn marker.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node2D:
		var p2: Node2D = player
		cfg.set_value("player", "position_x", p2.global_position.x)
		cfg.set_value("player", "position_y", p2.global_position.y)
		cfg.set_value("player", "has_position", true)
	else:
		cfg.set_value("player", "has_position", false)

	var err: int = cfg.save(save_path_for_slot(slot))
	if err != OK:
		push_error("SaveManager: failed to write slot %d (err %d)" % [slot, err])
		return false
	return true


## Convenience helper used by the auto-save hooks. Silently no-ops when
## no slot is active (e.g. during the title screen) so the trigger code
## doesn't have to guard.
func autosave_if_active() -> void:
	if current_slot <= 0:
		return
	save_game(current_slot)


# ============================================================================
# READ
# ============================================================================

## Load the given slot's contents into all the autoloads (GameState,
## RunState, DifficultySettings, QuestManager). The caller is then
## expected to transition into the saved scene — see start_loaded_slot.
##
## Returns false if the slot doesn't exist or is unreadable; the caller
## should keep the title screen up in that case.
func load_game(slot: int) -> bool:
	if not save_exists(slot):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(save_path_for_slot(slot)) != OK:
		return false
	if cfg.get_value("meta", "version", 0) != SAVE_VERSION:
		# Version mismatch — refuse rather than silently mis-loading.
		# A future migration system would handle older versions here.
		return false

	# Wipe every system to defaults BEFORE writing in the saved values,
	# so any data that was present in the previous session (e.g. story
	# flags from a different save we already loaded) doesn't leak through.
	reset_all_state()

	# --- difficulty ---
	DifficultySettings.set_difficulty(
		cfg.get_value("meta", "difficulty", DifficultySettings.Difficulty.NORMAL)
	)

	# --- game state ---
	GameState.soul_currency = cfg.get_value("game_state", "soul_currency", 0)
	GameState.death_count = cfg.get_value("game_state", "death_count", 0)
	GameState.story_flags = cfg.get_value("game_state", "story_flags", {})
	GameState.last_arch_id = cfg.get_value("game_state", "last_arch_id", "south_arch")
	# Ensure the south arch flag stays set even on imported saves where
	# the pre-mark didn't run — it's a "first activation" gate, not data
	# the save should ever be able to clear by omission.
	GameState.story_flags["arch_activated_south_arch"] = true

	# --- run state ---
	RunState.max_health = cfg.get_value("run_state", "max_health", RunState.BASE_MAX_HEALTH)
	RunState.current_health = cfg.get_value("run_state", "current_health", RunState.max_health)
	RunState.smell = cfg.get_value("run_state", "smell", 0.0)
	RunState.world_seed = cfg.get_value("run_state", "world_seed", randi())
	RunState.dungeon_seeds = cfg.get_value("run_state", "dungeon_seeds", {})
	RunState.consumed_node_paths = cfg.get_value("run_state", "consumed_node_paths", {})
	RunState.current_region = cfg.get_value("run_state", "current_region", "")
	RunState.run_kills_melee = cfg.get_value("run_state", "run_kills_melee", 0)
	RunState.run_kills_ranged = cfg.get_value("run_state", "run_kills_ranged", 0)

	# Inventory & equipment.
	RunState.inventory.clear()
	var inv_data: Array = cfg.get_value("run_state", "inventory", [])
	for entry in inv_data:
		if not (entry is Dictionary):
			continue
		var path: String = String(entry.get("path", ""))
		var count: int = int(entry.get("count", 1))
		if path == "":
			continue
		var item: Resource = _safe_load(path)
		if item is Item:
			RunState.inventory.append({"item": item, "count": count})

	# Rune collection — same load shape as inventory.
	RunState.rune_collection.clear()
	var rune_data: Array = cfg.get_value("run_state", "rune_collection", [])
	for entry in rune_data:
		if not (entry is Dictionary):
			continue
		var path: String = String(entry.get("path", ""))
		var count: int = int(entry.get("count", 1))
		if path == "":
			continue
		var item: Resource = _safe_load(path)
		if item is RunestoneItem:
			RunState.rune_collection.append({"item": item, "count": count})

	RunState.primary_weapon = _load_as(_safe_load(
		cfg.get_value("run_state", "primary_weapon", "")), "Weapon") as Weapon
	RunState.secondary_weapon = _load_as(_safe_load(
		cfg.get_value("run_state", "secondary_weapon", "")), "Weapon") as Weapon
	# Prepared weapon slots — same Weapon type as active slots.
	RunState.prepared_primary = _load_as(_safe_load(
		cfg.get_value("run_state", "prepared_primary", "")), "Weapon") as Weapon
	RunState.prepared_secondary = _load_as(_safe_load(
		cfg.get_value("run_state", "prepared_secondary", "")), "Weapon") as Weapon
	RunState.helmet = _load_as(_safe_load(
		cfg.get_value("run_state", "helmet", "")), "Armor") as Armor
	RunState.chest = _load_as(_safe_load(
		cfg.get_value("run_state", "chest", "")), "Armor") as Armor
	RunState.boots = _load_as(_safe_load(
		cfg.get_value("run_state", "boots", "")), "Armor") as Armor

	# --- player position ---
	if cfg.get_value("player", "has_position", false):
		pending_load_position = Vector2(
			cfg.get_value("player", "position_x", 0.0),
			cfg.get_value("player", "position_y", 0.0),
		)
		has_pending_load_position = true

	# --- rehydrate quests from the restored story_flags ---
	# Same flag set we just wrote into GameState — QuestManager reads
	# them back out into its in-memory active_quests dict. Has to run
	# AFTER GameState.story_flags is restored.
	if QuestManager.has_method("load_quests"):
		QuestManager.load_quests()

	# Tell the world the run is starting (kenning unlock listeners,
	# HUD currency refresh, inventory UI rebuild, PathManager chain
	# regeneration based on the freshly-restored world_seed).

	current_slot = slot
	# is_restore=true tells PathManager NOT to wipe map-reveal flags —
	# this is a save restore, not a death-restart. This replaces the old
	# snapshot-reveals-before-emit / restore-after dance that was fragile
	# and documented as a caveat.
	EventBus.run_started.emit(true)

	# Re-prime starting kennings after the save's story_flags have been
	# fully restored. This is a no-op for saves created after this fix
	# (where the saved _kenning_unlocked_ids array already includes the
	# starting kennings), but it RESTORES them for any save written
	# before this fix where the starting kennings were missing from
	# the persisted list. _unlock_internal is idempotent so the no-op
	# case is free.
	if KenningManager:
		KenningManager.reprime_unlocks()

	EventBus.currency_changed.emit(GameState.soul_currency)
	EventBus.inventory_changed.emit()
	EventBus.smell_changed.emit(RunState.smell, RunState.max_smell)
	EventBus.weapon_equipped.emit(RunState.primary_weapon, "primary")
	EventBus.weapon_equipped.emit(RunState.secondary_weapon, "secondary")
	EventBus.weapon_equipped.emit(RunState.prepared_primary, "prepared_primary")
	EventBus.weapon_equipped.emit(RunState.prepared_secondary, "prepared_secondary")
	EventBus.armor_equipped.emit(RunState.helmet)
	EventBus.armor_equipped.emit(RunState.chest)
	EventBus.armor_equipped.emit(RunState.boots)
	# QuestManager only fires quest_progress_updated when something
	# actively changes; emit one ourselves so the Quests UI repopulates
	# from the freshly-hydrated active_quests dict.
	EventBus.quest_progress_updated.emit()

	return true


## Load + scene-transition combo. The title screen calls this once the
## player has chosen a slot to continue. We use change_scene_to_file
## directly rather than going through SceneTransition.go_to because the
## SceneTransition path uses RunState.requested_spawn_point to position
## the player, and we want the saved coordinates instead — RegionRoot
## consults SaveManager.pending_load_position for exactly this case.
func start_loaded_slot(slot: int, scene_path_override: String = "") -> void:
	if not load_game(slot):
		push_error("SaveManager: load_game(%d) failed" % slot)
		return
	var scene_path: String = scene_path_override
	if scene_path == "":
		var cfg := ConfigFile.new()
		if cfg.load(save_path_for_slot(slot)) == OK:
			scene_path = cfg.get_value("meta", "scene_path", NEW_GAME_SCENE_PATH)
		else:
			scene_path = NEW_GAME_SCENE_PATH
	# Ensure no stale spawn-point request leaks in from the title
	# screen — we want the saved position only.
	RunState.requested_spawn_point = ""
	get_tree().change_scene_to_file(scene_path)


# ============================================================================
# NEW GAME
# ============================================================================

## Wipe the slot's existing data (if any), seed a fresh state with the
## chosen difficulty, and transition into the starting scene. Used by
## the title screen's "[ New Game ]" → difficulty picker flow.
func start_new_game(slot: int, difficulty: int) -> void:
	if slot <= 0 or slot > NUM_SLOTS:
		return

	# Hard reset so the new game starts genuinely clean — particularly
	# important if the user just returned to title from another save.
	reset_all_state()
	DifficultySettings.set_difficulty(difficulty)

	# Re-prime the south-arch flag (cleared by GameState.reset_to_defaults).
	GameState.story_flags["arch_activated_south_arch"] = true
	GameState.last_arch_id = "south_arch"

	# Seed a new world. Without this, two new games would generate
	# identical procedural chains, which leaks slightly between saves.
	RunState.world_seed = randi()

	current_slot = slot
	# Write a baseline save up-front so the slot shows up as occupied
	# even before the player triggers their first auto-save. Crucial
	# for the "I just made a new game and quit" flow.
	save_game(slot)

	# We DON'T set pending_load_position here — a new game should spawn
	# at the scene's default marker, not at (0, 0).
	has_pending_load_position = false
	RunState.requested_spawn_point = ""

	# Tell the world a fresh run is starting. PathManager listens and
	# regenerates its procedural chains with the new world_seed; without
	# this, the first new game after launch uses chains generated from
	# seed=0 at engine init and the world layout would never reflect the
	# seed we just rolled. Other run-started subscribers (HUD reset,
	# QuestManager re-eval) also fire here, but with empty RunState
	# they're no-ops.
	EventBus.run_started.emit(false)  # fresh new game, not a restore
	EventBus.currency_changed.emit(GameState.soul_currency)

	get_tree().change_scene_to_file(NEW_GAME_SCENE_PATH)


# ============================================================================
# DELETE
# ============================================================================

func delete_save(slot: int) -> bool:
	var path: String = save_path_for_slot(slot)
	if not FileAccess.file_exists(path):
		return false
	var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# DirAccess.remove_absolute may not work with user:// on some
	# platforms — fall back to DirAccess.open("user://").remove.
	if err != OK:
		var d := DirAccess.open("user://")
		if d != null:
			err = d.remove("save_slot_%d.cfg" % slot)
	return err == OK


# ============================================================================
# RESET / RETURN TO TITLE
# ============================================================================

## Wipe every system's runtime state back to engine defaults. Called
## before loading a different slot OR starting a new game OR returning
## to the title screen — guarantees no residual data from the prior
## session leaks into the next one.
func reset_all_state() -> void:
	current_slot = 0
	has_pending_load_position = false
	pending_load_position = Vector2.ZERO
	DifficultySettings.reset_to_defaults()
	GameState.reset_to_defaults()
	RunState.reset_to_defaults()
	# Quests live as in-memory mirrors of story flags; the GameState
	# reset above already cleared the flags, but the QuestManager dicts
	# still hold stale Quest objects from the previous session.
	if QuestManager:
		QuestManager.active_quests.clear()
		QuestManager.completed_quest_ids.clear()
		QuestManager.seen_quest_ids.clear()
	# Re-prime the south arch's activation flag so a subsequent new
	# game / load doesn't show the "first activation" dialogue again —
	# the south arch is *always* known by design (see GameState._ready).
	GameState.story_flags["arch_activated_south_arch"] = true

	# Re-prime starting kennings (Bare-Knuckled, Cliff-Born, All-Seer,
	# and any other unlock_flag="" kenning). KenningManager's initial
	# unlock pass runs in its own _ready(), which fires once at engine
	# startup — but the GameState reset above just wiped the
	# _kenning_unlocked_ids array from story_flags, so we have to
	# re-do the pass here. Without this, a "start new game" or
	# "load slot" wipes the player's starting names and they're
	# never re-applied. The wipe-then-reapply order is intentional:
	# wipe clears any *non-starting* kenning that was unlocked in a
	# previous session, then reapply restores only the ones that
	# should be free at the start.
	if KenningManager:
		KenningManager.reprime_unlocks()


## Save (if a slot is active), then wipe state and bring the title
## screen up. The pause menu's "Save & Quit to Title" button calls this.
func quit_to_title() -> void:
	if current_slot > 0:
		save_game(current_slot)
	# get_tree().paused can be true from the pause menu — unpause before
	# the scene swap or the title screen comes up paused and unresponsive.
	get_tree().paused = false
	reset_all_state()
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)


# ============================================================================
# HELPERS
# ============================================================================

## Safely load a resource path. Returns null on missing/invalid paths
## instead of pushing engine errors — saves that reference a deleted
## .tres file should degrade gracefully (item silently missing) rather
## than failing the entire load.
func _safe_load(path: Variant) -> Resource:
	if not (path is String) or path == "":
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Cast helper for typed slots. Returns null if the loaded resource
## isn't the expected class — protects against a save that has an
## inventory item path stored in a weapon slot, say.
func _load_as(res: Resource, expected_class: String) -> Resource:
	if res == null:
		return null
	if res.get_class() == expected_class:
		return res
	# get_class() returns "Resource" for our custom script classes, so
	# we also check via script name via duck typing — Weapon, Armor
	# both have unique exports / class_name. Cheapest is to is-check.
	match expected_class:
		"Weapon":
			return res if res is Weapon else null
		"Armor":
			return res if res is Armor else null
	return res


func _path_of(res: Resource) -> String:
	if res == null:
		return ""
	if res.resource_path == "":
		return ""
	return res.resource_path


## Pull a human-readable display name out of a scene file path. We
## strip the directory prefix and ".tscn" suffix, then turn underscores
## into spaces and capitalize. Lazy but works for everything in
## world/regions/. Returns the raw path if parsing fails.
func _pretty_scene_name(scene_path: String) -> String:
	if scene_path == "":
		return "Unknown"
	var file: String = scene_path.get_file()
	if not file.ends_with(".tscn"):
		return scene_path
	file = file.substr(0, file.length() - 5)
	# Special-cased prefixes so dungeon scenes don't read as raw
	# slugs ("sprekken_a3" → "Sprekken: A3"). We just strip the
	# folder hint when it'd be redundant in the title.
	var parts: PackedStringArray = file.split("_")
	var result: String = ""
	for i in parts.size():
		var word: String = parts[i]
		if word.length() > 0:
			word = word.substr(0, 1).to_upper() + word.substr(1)
		if i > 0:
			result += " "
		result += word
	return result
