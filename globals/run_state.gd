extends Node
## Per-run state. Wiped clean on death.
##
## Death-resets to: empty inventory, no equipment, full HP, no smell.
## The player respawns barehanded — fists are the always-available
## fallback, see Player._attack_with for the unarmed melee path.
##
## Story progress, currency, and last-activated arch live in GameState
## and survive across deaths.

# --- Weapon slots (Weapon = MeleeWeapon | RangedWeapon) ---
var primary_weapon: Weapon = null
var secondary_weapon: Weapon = null

# --- Prepared weapon slots (swappable with active via Q) ---
## The prepared set mirrors the active set: two hands worth of weapons
## that sit ready and swap in with the Q key. Inert while stowed — no
## passive speed multipliers, no stat contributions. They exist purely
## so the player can switch combat styles mid-fight without opening
## the inventory (which will eventually not pause the game).
var prepared_primary: Weapon = null
var prepared_secondary: Weapon = null

# --- Armor slots ---
var helmet: Armor = null
var chest: Armor = null
var boots: Armor = null

# --- Inventory: array of {item: Item, count: int} slots ---
var inventory: Array = []

# --- Rune collection: separate from inventory ---
## RunestoneItems are no longer equippable and live in their own
## collection (displayed by RunesUI). Stored as the same
## {item: RunestoneItem, count: int} shape so stacking works the
## same way. In a future pass, each rune will grant a small passive
## stat bonus — the collection IS the build system.
var rune_collection: Array = []

# --- Stats ---
## Base value before kenning bonuses. Recomputed on run start via
## KenningManager.get_max_health_bonus() so the player's HP cap reflects
## whatever they currently have equipped.
const BASE_MAX_HEALTH: float = 100.0
var max_health: float = BASE_MAX_HEALTH
var current_health: float = BASE_MAX_HEALTH

# --- Detection signature ---
var smell: float = 0.0
var max_smell: float = 100.0
var smell_natural_cap: float = 80.0
var smell_block_seconds: float = 0.0
var smell_block_threshold: float = 0.0

## How fast smell naturally fades when the player is doing nothing
## (no fighting, no fast movement). Tuned so a full 80-smell takes
## ~90 seconds to fully clear at rest — slow enough that the player
## still feels pressure to manage scent, fast enough that "wait it
## out" is a viable but boring strategy. Cinder Salt and the bath
## house remain the fast-clear options.
const SMELL_NATURAL_DECAY: float = 0.9

# --- World seeding ---
var world_seed: int = 0
var dungeon_seeds: Dictionary = {}

# --- Run-scope kill counters (for kenning unlocks) ---
## Spear-Dane = "Take a hundred close-quarters lives in a single run."
## Reset on every new run. Increments when an enemy dies and the
## killing-blow damage_info has weapon_category == "melee" — see
## _on_enemy_killed below.
var run_kills_melee: int = 0
## Arrow-Crow = "Drop seventy enemies at range without taking a hit in
## close quarters." Reset on every new run AND when the player gets hit
## by a melee-category source. Increments on ranged-category kills.
var run_kills_ranged: int = 0
## Tracks whether the Arrow-Crow streak is still clean (no close-quarters
## hits taken). The kenning requires `run_kills_ranged >= 70` while this
## remains true. Resetting to false on a melee-source hit means the
## player effectively has to "restart counting" — but the count itself
## isn't reset, only the eligibility for THIS run's unlock.
var _arrow_crow_streak_clean: bool = true

# --- Scene transition state ---
var requested_spawn_point: String = ""
var current_region: String = ""

# Last-emitted smell, throttles per-frame smell signal chatter.
var _smell_last_emitted: float = -1.0

## Set of "scene_path::node_path" strings — any consumable node (enemy
## that died, pickup that was collected) registers itself here on
## consumption. On scene re-entry, nodes check this set and despawn
## themselves if their identity is in it. Cleared on death/respawn so
## the world repopulates fresh each run. Used as a set; values are bool
## true (Godot doesn't have a native Set type for arbitrary keys).
var consumed_node_paths: Dictionary = {}

## Per-carving monologue choices, locked-in for this run. Keys are
## carving_id strings (set per-AltarCarving in the scene), values are
## the resource_path of the Dialogue chosen the first time the player
## interacts with that carving this run. Subsequent reads of the same
## carving in the same run show the same monologue — the carving feels
## like a static inscription, not a random oracle. On player death
## (reset_for_new_run), this clears and each carving rolls fresh on
## next interaction.
var carving_chosen_monologue: Dictionary = {}


func _ready() -> void:
	reset_for_new_run()
	# Subscribe to combat events so run-scope kill counters update for
	# kenning unlocks. RunState owns this data (it's per-run state that
	# resets on death — see reset_for_new_run) so the subscription
	# lives here rather than in KenningManager.
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.damage_dealt_visual.connect(_on_damage_dealt_visual)
	# Gear-multiplier cache invalidation. The move-speed aggregators
	# compose into Player._process_normal EVERY physics frame and the
	# damage aggregators into Weapon.compute_outgoing_damage on every
	# hit; computing them live rebuilt a [helmet,chest,boots] /
	# [primary,secondary] array per call. We recompute the cache only
	# when a slot changes. armor_equipped / weapon_equipped are emitted
	# (after the slot is written) by every path that mutates a slot —
	# equip, unequip, craft-replace, death reset, and save load — so
	# these two connections cover all of them. unbind drops the signal
	# args the recompute doesn't need. Prime once now for the fresh-run
	# baseline (all slots empty → identity multipliers).
	EventBus.armor_equipped.connect(_recompute_gear_cache.unbind(1))
	EventBus.weapon_equipped.connect(_recompute_gear_cache.unbind(2))
	_recompute_gear_cache()


## Called when starting a new run after death. Wipes inventory, equipment,
## HP, smell.
##
## CRITICAL: this function MUST NOT touch GameState. Everything in there
## is meta-progression — the player should never lose those things to a
## death. The persistence contract for each system:
##   - Currency           → GameState.soul_currency (persists)
##   - Story beats heard  → GameState.story_flags (persists)
##   - Activated arches   → GameState.story_flags (persists)
##   - Boss kill records  → GameState.story_flags (persists)
##   - Kennings unlocked  → GameState.story_flags["_kenning_unlocked_ids"]
##                          and ["_kenning_equipped_ids"] (persists)
##   - Quest state        → GameState.story_flags (QuestManager stores it
##                          inside _quest_active_data / _quest_completed_ids)
##   - Run inventory/gear → RunState fields below (RESETS — that's the
##                          roguelite loop, you start a new run "naked").
##
## If you add a future "fresh start" feature that wipes meta-progression,
## do it via an EXPLICIT method (GameState.clear_all_progress() or
## similar), NOT here. Death is just an island-respawn, not a save wipe.
func reset_for_new_run() -> void:
	primary_weapon = null
	secondary_weapon = null
	prepared_primary = null
	prepared_secondary = null
	helmet = null
	chest = null
	boots = null
	inventory.clear()
	rune_collection.clear()
	# Re-derive max HP from the equipped kenning loadout (kennings are
	# meta-progression, NOT wiped on death — see contract block above).
	# KenningManager is registered as an autoload that loads BEFORE
	# RunState (see project.godot), so it's always available here.
	# A player who died wearing Mead-Hall-Sated comes back at 130 HP.
	max_health = BASE_MAX_HEALTH + KenningManager.get_max_health_bonus()
	current_health = max_health
	smell = 0.0
	smell_block_seconds = 0.0
	smell_block_threshold = 0.0
	_smell_last_emitted = -1.0
	world_seed = randi()
	dungeon_seeds.clear()
	consumed_node_paths.clear()
	# Carving choices are per-run: on respawn the world's dead souls
	# speak fresh words to the new pilgrim. Each carving will roll a
	# new monologue on its next interaction.
	carving_chosen_monologue.clear()
	# Reset run-scope kill counters. Spear-Dane / Arrow-Crow are per-run
	# achievements, so the moment the player respawns they start
	# counting from zero again — same intuition as a fresh roguelike run.
	run_kills_melee = 0
	run_kills_ranged = 0
	_arrow_crow_streak_clean = true

	EventBus.run_started.emit(false)  # fresh run after death
	EventBus.inventory_changed.emit()
	EventBus.smell_changed.emit(smell, max_smell)
	# Notify all weapon slots are empty so HUD/inventory clear cleanly.
	EventBus.weapon_equipped.emit(null, "primary")
	EventBus.weapon_equipped.emit(null, "secondary")
	EventBus.weapon_equipped.emit(null, "prepared_primary")
	EventBus.weapon_equipped.emit(null, "prepared_secondary")
	EventBus.armor_equipped.emit(null)


## Distinct from reset_for_new_run by intent: this runs when the user
## is LEAVING the current save (load other slot / new game / return to
## title), not when they died inside it. The difference matters because
## reset_for_new_run re-derives max_health from KenningManager — which
## is the right move on death (kennings persist, so HP cap reflects
## them) but the WRONG move when we're tearing the save down, because
## KenningManager will be reset right after this call by SaveManager
## and we don't want to read stale kenning state in between. So we
## just zero everything to engine defaults; SaveManager handles
## re-seeding from the new save (or leaves it baseline for a brand-new
## game, which will go through reset_for_new_run on player spawn).
##
## Caller (SaveManager.reset_all_state) is responsible for clearing
## any external systems that mirror our state (Quests, HUD widgets).
## We just zero our own fields and emit the wipe signals so listeners
## update their visuals.
func reset_to_defaults() -> void:
	primary_weapon = null
	secondary_weapon = null
	prepared_primary = null
	prepared_secondary = null
	helmet = null
	chest = null
	boots = null
	inventory.clear()
	rune_collection.clear()
	max_health = BASE_MAX_HEALTH
	current_health = BASE_MAX_HEALTH
	smell = 0.0
	smell_block_seconds = 0.0
	smell_block_threshold = 0.0
	_smell_last_emitted = -1.0
	world_seed = 0
	dungeon_seeds.clear()
	consumed_node_paths.clear()
	carving_chosen_monologue.clear()
	run_kills_melee = 0
	run_kills_ranged = 0
	_arrow_crow_streak_clean = true
	requested_spawn_point = ""
	current_region = ""
	EventBus.inventory_changed.emit()
	EventBus.smell_changed.emit(smell, max_smell)
	EventBus.weapon_equipped.emit(null, "primary")
	EventBus.weapon_equipped.emit(null, "secondary")
	EventBus.weapon_equipped.emit(null, "prepared_primary")
	EventBus.weapon_equipped.emit(null, "prepared_secondary")
	EventBus.armor_equipped.emit(null)


# ============================================================================
# CONSUMED NODE TRACKING
# ============================================================================

## Build a stable identity for a node based on the current scene + the
## node's tree path. Used by enemies and pickups to register themselves
## as consumed. As long as the scene file isn't edited (or nodes
## reordered with renames), identity persists across reloads.
func node_identity(node: Node) -> String:
	var scene_path: String = ""
	var root := node.get_tree().current_scene
	if root:
		scene_path = root.scene_file_path
	return scene_path + "::" + str(node.get_path())


func mark_node_consumed(node: Node) -> void:
	consumed_node_paths[node_identity(node)] = true


func is_node_consumed(node: Node) -> bool:
	return consumed_node_paths.has(node_identity(node))


func get_dungeon_seed(dungeon_id: String, fresh: bool = false) -> int:
	if fresh or not dungeon_seeds.has(dungeon_id):
		dungeon_seeds[dungeon_id] = randi()
	return dungeon_seeds[dungeon_id]


# ============================================================================
# INVENTORY
# ============================================================================

func add_to_inventory(item: Item) -> void:
	if item == null:
		return
	# RunestoneItems go to the rune collection, not inventory.
	if item is RunestoneItem:
		add_to_rune_collection(item as RunestoneItem)
		return
	if item.max_stack > 1:
		for slot in inventory:
			if slot.item == item and slot.count < item.max_stack:
				slot.count += 1
				EventBus.item_picked_up.emit(item)
				EventBus.inventory_changed.emit()
				return
	inventory.append({"item": item, "count": 1})
	EventBus.item_picked_up.emit(item)
	EventBus.inventory_changed.emit()


func remove_one_from_inventory(item: Item) -> bool:
	for i in range(inventory.size()):
		if inventory[i].item == item:
			inventory[i].count -= 1
			if inventory[i].count <= 0:
				inventory.remove_at(i)
			EventBus.inventory_changed.emit()
			return true
	return false


func count_in_inventory(item: Item) -> int:
	var total := 0
	for slot in inventory:
		if slot.item == item:
			total += slot.count
	return total


func has_in_inventory(item: Item) -> bool:
	return count_in_inventory(item) > 0


# ============================================================================
# RUNE COLLECTION
# ============================================================================

func add_to_rune_collection(rune: RunestoneItem) -> void:
	if rune == null:
		return
	if rune.max_stack > 1:
		for slot in rune_collection:
			if slot.item == rune and slot.count < rune.max_stack:
				slot.count += 1
				EventBus.item_picked_up.emit(rune)
				EventBus.inventory_changed.emit()
				return
	rune_collection.append({"item": rune, "count": 1})
	EventBus.item_picked_up.emit(rune)
	EventBus.inventory_changed.emit()


# ============================================================================
# RUNE STAT AGGREGATION
# ============================================================================
## Sum the total bonus for a given RuneStat across all collected runes.
## Called by gameplay systems (damage pipeline, speed chain, dash system)
## to compose rune bonuses. Returns the additive total — a player with
## two +2% melee damage runes gets 4.0 from this call, which the caller
## then converts to a multiplier (1.04). Flat stats (dash charges,
## rerolls) return the raw count.

func get_rune_bonus(stat: int) -> float:
	var total: float = 0.0
	for slot in rune_collection:
		var rune: RunestoneItem = slot.item
		if rune.rune_stat == stat:
			total += rune.bonus_value * slot.count
	return total


## Convenience: get a rune percentage bonus as a multiplier (1.0 + pct/100).
## e.g. 6% total → returns 1.06. For composing into multiplicative chains.
func get_rune_multiplier(stat: int) -> float:
	return 1.0 + get_rune_bonus(stat) / 100.0


## All rune bonuses as a summary dict. Used by the RunesUI to display
## an aggregate overview without iterating the collection per-stat.
func get_all_rune_bonuses() -> Dictionary:
	var totals: Dictionary = {}
	for slot in rune_collection:
		var rune: RunestoneItem = slot.item
		var stat: int = rune.rune_stat
		if not totals.has(stat):
			totals[stat] = 0.0
		totals[stat] += rune.bonus_value * slot.count
	return totals


# ============================================================================
# EQUIPPING
# ============================================================================

func equip_primary(weapon: Weapon, _skip_inventory: bool = false) -> bool:
#	if weapon != null and weapon is MagicSpell:
#		return false
	# Two-handed enforcement. Two checks:
	#   (a) Equipping a 2H weapon while secondary is non-empty → fail.
	#   (b) Equipping anything (including null swap) into primary while
	#       a 2H weapon occupies secondary → fail. Without this you
	#       could equip a 1H into primary, then have a 2H in secondary
	#       AND a 1H in primary, which the 2H contract forbids.
	# Returning false on failure (not push_error) so the inventory UI's
	# equip click just silently no-ops, matching the rest of the
	# equip-failure pattern (e.g. spell-into-weapon-slot).
	if weapon != null and weapon.two_handed and secondary_weapon != null:
		return false
	if weapon != null and secondary_weapon != null and secondary_weapon.two_handed:
		return false
	if primary_weapon != null:
		_stash_old_weapon(primary_weapon)
	primary_weapon = weapon
	if weapon and not _skip_inventory:
		_pull_weapon_from_inventory(weapon)
	EventBus.weapon_equipped.emit(weapon, "primary")
	return true


func equip_secondary(weapon: Weapon, _skip_inventory: bool = false) -> bool:
#	if weapon != null and weapon is MagicSpell:
#		return false
	# Two-handed enforcement (see equip_primary for explanation).
	if weapon != null and weapon.two_handed and primary_weapon != null:
		return false
	if weapon != null and primary_weapon != null and primary_weapon.two_handed:
		return false
	if secondary_weapon != null:
		_stash_old_weapon(secondary_weapon)
	secondary_weapon = weapon
	if weapon and not _skip_inventory:
		_pull_weapon_from_inventory(weapon)
	EventBus.weapon_equipped.emit(weapon, "secondary")
	return true


func equip_prepared_primary(weapon: Weapon, _skip_inventory: bool = false) -> bool:
	# Two-handed enforcement mirrors active slots.
	if weapon != null and weapon.two_handed and prepared_secondary != null:
		return false
	if weapon != null and prepared_secondary != null and prepared_secondary.two_handed:
		return false
	if prepared_primary != null:
		_stash_old_weapon(prepared_primary)
	prepared_primary = weapon
	if weapon and not _skip_inventory:
		_pull_weapon_from_inventory(weapon)
	EventBus.weapon_equipped.emit(weapon, "prepared_primary")
	return true


func equip_prepared_secondary(weapon: Weapon, _skip_inventory: bool = false) -> bool:
	if weapon != null and weapon.two_handed and prepared_primary != null:
		return false
	if weapon != null and prepared_primary != null and prepared_primary.two_handed:
		return false
	if prepared_secondary != null:
		_stash_old_weapon(prepared_secondary)
	prepared_secondary = weapon
	if weapon and not _skip_inventory:
		_pull_weapon_from_inventory(weapon)
	EventBus.weapon_equipped.emit(weapon, "prepared_secondary")
	return true


## Swap the active and prepared weapon sets atomically. Called by
## Player.gd after the swap animation completes. Both pairs exchange
## in one operation so there is no intermediate "half-swapped" state.
## The gear cache recomputes via the weapon_equipped signals.
func swap_weapon_sets() -> void:
	var old_pri: Weapon = primary_weapon
	var old_sec: Weapon = secondary_weapon
	primary_weapon = prepared_primary
	secondary_weapon = prepared_secondary
	prepared_primary = old_pri
	prepared_secondary = old_sec
	# Emit for all four slots so HUD + inventory refresh atomically.
	EventBus.weapon_equipped.emit(primary_weapon, "primary")
	EventBus.weapon_equipped.emit(secondary_weapon, "secondary")
	EventBus.weapon_equipped.emit(prepared_primary, "prepared_primary")
	EventBus.weapon_equipped.emit(prepared_secondary, "prepared_secondary")
	EventBus.weapon_swap_completed.emit()


func equip_to_slot(slot_name: String, equipment: Resource) -> bool:
	match slot_name:
		"primary":            return equip_primary(equipment)
		"secondary":          return equip_secondary(equipment)
		"prepared_primary":   return equip_prepared_primary(equipment)
		"prepared_secondary": return equip_prepared_secondary(equipment)
		"helmet", "chest", "boots":
			if equipment is Armor:
				var a: Armor = equipment
				var expected: int = -1
				match slot_name:
					"helmet": expected = Armor.ArmorSlot.HELMET
					"chest":  expected = Armor.ArmorSlot.CHEST
					"boots":  expected = Armor.ArmorSlot.BOOTS
				if a.armor_slot != expected:
					return false
				equip_armor(a)
				return true
			return false
	return false


func can_equip_to_slot(slot_name: String, equipment: Resource) -> bool:
	match slot_name:
		"primary", "secondary", "prepared_primary", "prepared_secondary":
			return equipment is Weapon
		"helmet":
			return equipment is Armor and (equipment as Armor).armor_slot == Armor.ArmorSlot.HELMET
		"chest":
			return equipment is Armor and (equipment as Armor).armor_slot == Armor.ArmorSlot.CHEST
		"boots":
			return equipment is Armor and (equipment as Armor).armor_slot == Armor.ArmorSlot.BOOTS
	return false


func equip_armor(armor: Armor) -> void:
	if armor == null:
		return
	match armor.armor_slot:
		Armor.ArmorSlot.HELMET:
			if helmet: add_to_inventory(helmet)
			helmet = armor
		Armor.ArmorSlot.CHEST:
			if chest: add_to_inventory(chest)
			chest = armor
		Armor.ArmorSlot.BOOTS:
			if boots: add_to_inventory(boots)
			boots = armor
	remove_one_from_inventory(armor)
	EventBus.armor_equipped.emit(armor)


func unequip_armor(slot_name: String) -> void:
	var piece: Armor = null
	match slot_name:
		"helmet":
			piece = helmet
			helmet = null
		"chest":
			piece = chest
			chest = null
		"boots":
			piece = boots
			boots = null
	if piece:
		add_to_inventory(piece)
		EventBus.armor_equipped.emit(null)


func unequip_weapon_slot(slot_name: String) -> void:
	var w: Resource = null
	match slot_name:
		"primary":
			w = primary_weapon
			primary_weapon = null
		"secondary":
			w = secondary_weapon
			secondary_weapon = null
		"prepared_primary":
			w = prepared_primary
			prepared_primary = null
		"prepared_secondary":
			w = prepared_secondary
			prepared_secondary = null
	_stash_old_weapon(w)
	EventBus.weapon_equipped.emit(null, slot_name)


func _stash_old_weapon(w: Resource) -> void:
	if w is Item:
		add_to_inventory(w)


func _pull_weapon_from_inventory(w: Resource) -> void:
	if w is Item:
		remove_one_from_inventory(w)


# ============================================================================
# DETECTION SIGNATURE
# ============================================================================

func add_smell(amount: float) -> void:
	if amount == 0.0:
		return
	smell = clampf(smell + amount, 0.0, smell_natural_cap)
	if smell_block_seconds > 0.0:
		smell = minf(smell, smell_block_threshold * max_smell)
	_emit_smell_if_changed()


func reduce_smell(amount: float) -> void:
	smell = clampf(smell - amount, 0.0, max_smell)
	_emit_smell_if_changed()


func grant_smell_block(threshold_fraction: float, duration_seconds: float) -> void:
	if duration_seconds > smell_block_seconds:
		smell_block_seconds = duration_seconds
	if smell_block_threshold == 0.0 or threshold_fraction < smell_block_threshold:
		smell_block_threshold = threshold_fraction
	smell = minf(smell, smell_block_threshold * max_smell)
	_emit_smell_if_changed()


func tick_smell(delta: float, in_combat: bool = false) -> void:
	# Block-effect timer first (existing behavior).
	if smell_block_seconds > 0.0:
		smell_block_seconds = max(0.0, smell_block_seconds - delta)
		if smell_block_seconds == 0.0:
			smell_block_threshold = 0.0

	# Natural decay — README contract was "smell decays slowly" but the
	# original implementation only ticked the block timer. Now smell
	# actually falls toward zero at SMELL_NATURAL_DECAY/sec, but only
	# when the player isn't in combat. In-combat ticking smell down
	# would let the player cheese the detection system by tanking a
	# hit and waiting; pausing decay during fights keeps scent as a
	# pressure-builder while still letting it fade between encounters.
	if not in_combat and smell > 0.0:
		var new_smell: float = maxf(0.0, smell - SMELL_NATURAL_DECAY * delta)
		if new_smell != smell:
			smell = new_smell
			_emit_smell_if_changed()


func _emit_smell_if_changed() -> void:
	if absf(smell - _smell_last_emitted) > 0.5 or (smell == 0.0 and _smell_last_emitted != 0.0):
		_smell_last_emitted = smell
		EventBus.smell_changed.emit(smell, max_smell)


# ============================================================================
# AGGREGATE STATS
# ============================================================================

func apply_armor_to_damage(amount: float, info: Dictionary) -> float:
	for piece in [helmet, chest, boots]:
		if piece != null:
			amount = piece.apply_to_damage(amount, info)
	return amount


# ── Armor "build" stat aggregators ──────────────────────────────────────
# These compose modifiers across all three equipped slots. Each piece's
# field defaults to 1.0 (multipliers) or 0.0 (flat bonus), so missing
# pieces and pieces without offensive stats contribute the identity.
#
# Wired into:
#   - melee/ranged damage muls → Weapon.compute_outgoing_damage (gates
#     on category, so a "melee damage" hat doesn't accidentally buff
#     arrows fired through it)
#   - move speed mul → Player._physics_process speed chain (multiplies
#     onto status and kenning multipliers)
#   - max HP bonus → KenningManager._announce_loadout_change (the
#     existing HP-recompute pipeline; KenningManager also listens to
#     armor_equipped now so equipping a piece refreshes the cap)

# Cached gear multipliers (see _recompute_gear_cache). The move-speed
# pair composes into Player._process_normal every physics frame; the
# damage pair into Weapon.compute_outgoing_damage on every hit. Holding
# them as plain floats removes the per-frame / per-hit array builds the
# getters below used to do. Default to identity so a fresh run (no gear)
# reads correctly even before the first _recompute_gear_cache call.
var _cached_armor_move_speed: float = 1.0
var _cached_weapon_move_speed: float = 1.0
var _cached_armor_melee_dmg: float = 1.0
var _cached_armor_ranged_dmg: float = 1.0


## Recompute all four cached gear multipliers in a single pass over the
## equipped slots. Called on armor_equipped / weapon_equipped (which fire
## after any slot write) and once at _ready. Composition is identical to
## the old per-getter loops — multiplicative across slots, skipping nulls
## and non-matching types — so the values are byte-for-byte what the live
## getters returned.
func _recompute_gear_cache() -> void:
	var move: float = 1.0
	var melee: float = 1.0
	var ranged: float = 1.0
	for piece in [helmet, chest, boots]:
		if piece is Armor:
			var a: Armor = piece
			move *= a.move_speed_multiplier
			melee *= a.melee_damage_multiplier
			ranged *= a.ranged_damage_multiplier
	_cached_armor_move_speed = move
	_cached_armor_melee_dmg = melee
	_cached_armor_ranged_dmg = ranged

	var wmove: float = 1.0
	for w in [primary_weapon, secondary_weapon]:
		if w is Weapon:
			wmove *= (w as Weapon).wielder_speed_multiplier
	_cached_weapon_move_speed = wmove


func get_armor_melee_damage_multiplier() -> float:
	return _cached_armor_melee_dmg


func get_armor_ranged_damage_multiplier() -> float:
	return _cached_armor_ranged_dmg


func get_armor_move_speed_multiplier() -> float:
	return _cached_armor_move_speed


## Aggregate move-speed multipliers from equipped weapons (primary and
## secondary). Same composition rule as armor (multiplicative, skip
## nulls). Prepared weapons intentionally NOT included: those are
## stowed, not actively wielded, and stowed gear should be inert until
## swapped in.
func get_weapon_move_speed_multiplier() -> float:
	return _cached_weapon_move_speed


func get_armor_max_health_bonus() -> float:
	var bonus: float = 0.0
	for piece in [helmet, chest, boots]:
		if piece is Armor:
			bonus += (piece as Armor).max_health_bonus
	return bonus


## Same role as get_armor_max_health_bonus but for shields. Each
## equipped slot is inspected; if either holds a ShieldWeapon, its
## max_health_bonus contributes to the total. Lighter shields leave
## the field at 0 and contribute nothing; the heavier late-act-2
## shields (Moor-Mail Bulwark, Hoarfrost Aegis) carry +20-30 HP
## passively. Recomputed on weapon_equipped (see KenningManager's
## _ready) so swapping shields adjusts max HP immediately.
func get_shield_max_health_bonus() -> float:
	var bonus: float = 0.0
	for slot in [primary_weapon, secondary_weapon]:
		if slot is ShieldWeapon:
			bonus += (slot as ShieldWeapon).max_health_bonus
	return bonus


# ============================================================================
# KENNING UNLOCK COUNTERS
# ============================================================================
#
# Two kennings have run-scope thresholds:
#   Spear-Dane:   100 melee kills in a run.
#   Arrow-Crow:   70 ranged kills in a run, no close-quarters hits taken.
#
# Both write a story flag when their condition is met. KenningManager
# listens on story_flag_set and unlocks the matching kenning, then
# stops re-firing for it (its _unlock_internal early-returns when the
# kenning is already unlocked). So we can set the flag repeatedly
# without spamming the unlock toast — KenningManager handles dedup.
#
# Constants are defined here rather than read from the .tres because
# the .tres has them as flavor text in unlock_hint ("seventy", "a
# hundred"), and parsing English to integers would be silly. If the
# author wants to retune the thresholds, edit these constants AND
# the unlock_hint text together.

const SPEAR_DANE_THRESHOLD: int = 100
const ARROW_CROW_THRESHOLD: int = 70
const FLAG_SPEAR_DANE: String = "kenning_unlock_spear_dane"
const FLAG_ARROW_CROW: String = "kenning_unlock_arrow_crow"


func _on_enemy_killed(_entity: Node, kill_info: Dictionary) -> void:
	var category: String = String(kill_info.get("weapon_category", ""))
	match category:
		"melee":
			run_kills_melee += 1
			if run_kills_melee >= SPEAR_DANE_THRESHOLD \
					and not GameState.has_flag(FLAG_SPEAR_DANE):
				GameState.set_flag(FLAG_SPEAR_DANE, true)
		"ranged", "spell":
			# Spells count as ranged for Arrow-Crow — they're delivered
			# from a distance via projectiles, same intent as bow shots.
			# If a future kenning splits "true bow" from "spells", swap
			# this to "ranged" only.
			run_kills_ranged += 1
			if _arrow_crow_streak_clean \
					and run_kills_ranged >= ARROW_CROW_THRESHOLD \
					and not GameState.has_flag(FLAG_ARROW_CROW):
				GameState.set_flag(FLAG_ARROW_CROW, true)
		_:
			# "persistent" (cone/beam), "" (unknown), or a future category
			# don't credit either counter. The flamethrower DOES kill
			# enemies but isn't really "close-quarters" or "ranged" in a
			# way that maps onto these two specific kennings — better to
			# leave it uncounted than mis-categorize.
			pass


## Track close-quarters hits taken so the Arrow-Crow streak resets when
## the player gets hit by a melee-category source. We listen on
## damage_dealt_visual (which fires for both player and enemy targets)
## and filter to hits where the target IS the player.
##
## We compare via `target is Node` and look at its `team` field rather
## than holding a Player reference, because RunState is loaded before
## any Player scene exists.
func _on_damage_dealt_visual(target: Node, _amount: float, info: Dictionary) -> void:
	if not _arrow_crow_streak_clean:
		return
	if not is_instance_valid(target):
		return
	if not ("team" in target) or target.team != "player":
		return
	var src_cat: String = String(info.get("weapon_category", ""))
	if src_cat == "melee":
		# Player took a close-quarters hit. The streak is broken for the
		# rest of THIS run; reset_for_new_run will restore it on death.
		_arrow_crow_streak_clean = false
