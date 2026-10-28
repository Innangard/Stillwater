extends Node
## Autoloaded manager for the kenning meta-progression system.
##
## Responsibilities:
##   - Holds the catalog (all Kenning resources discovered on disk).
##   - Tracks unlocked + equipped via GameState.story_flags. This means
##     the data persists across death automatically — RunState.reset_for_new_run
##     only touches RunState's own fields and never touches story_flags,
##     so a kenning earned mid-run survives the death that ends that run.
##     (Persistence across QUIT-and-resume requires GameState.save_game /
##     load_game to be wired up at startup and shutdown, which is future
##     work — the save functions exist but aren't called yet.)
##   - Listens on EventBus.story_flag_set to auto-unlock kennings whose
##     unlock_flag now reads true. This is the only unlock channel — quests
##     and boss kills both feed into it (QuestManager sets quest_<id> flags
##     on turn-in, GameState.mark_boss_dead sets boss_dead_<id> flags).
##   - Exposes aggregate multiplier getters for combat code to consume.
##
## NOTE: No class_name — registered as autoload "KenningManager".

## All discovered Kenning resources, keyed by kenning_id. Built once at
## startup by scanning the catalog directory.
var catalog: Dictionary = {}

## Cached list of the currently-equipped Kenning resources. Rebuilt ONLY
## when the loadout changes (see _recompute_kenning_cache); the aggregate
## getters at the bottom of this file read it instead of rebuilding a
## fresh Array[Kenning] on every call. Those getters run in the combat
## hot path — get_move_speed_multiplier every physics frame, the damage
## getters on every hit with persistent hitboxes ticking multiple
## enemies — so the per-call allocation they used to make (via
## equipped_kennings()) was the only steady per-frame allocation in that
## path. Invalidated through _announce_loadout_change, the single choke
## point every equip / unequip / armor / weapon change already routes
## through (and which every save-load slot-restore fires via
## armor_equipped / weapon_equipped).
var _equipped_kennings_cache: Array[Kenning] = []

## Maximum kennings equipped at once. Hardcoded; the UI assumes 4.
const MAX_EQUIPPED: int = 4

## Directory scanned at startup for .tres kennings.
const CATALOG_DIR: String = "res://kennings/instances/"

## GameState flag keys (kept here so any persistence change is a one-line edit).
const FLAG_UNLOCKED: String = "_kenning_unlocked_ids"
const FLAG_EQUIPPED: String = "_kenning_equipped_ids"

## Set of monologue resource paths the player has read. Stored as an
## Array in story_flags but used as a deduplicated set — we check
## membership and append only on first sight.
const FLAG_MONOLOGUES_READ: String = "_monologue_ids_read"

## Path constants for the four act pools. These are the ONLY data this
## manager hardcodes about the lore catalog — every other detail
## (which monologues are in which pool, which altars wire to which pool)
## lives in the .tres files themselves and is queried dynamically.
## So adding act-5 monologues later means: add a constant here, add a
## flag to ACT_COMPLETION_FLAGS, add an entry to ACT_POOL_PATHS, write
## an act_5_pool.tres. Three lines and a file.
const ACT_POOL_PATHS: Array[String] = [
	"res://dialogue/monologues/act_1_pool.tres",
	"res://dialogue/monologues/act_2_pool.tres",
	"res://dialogue/monologues/act_3_pool.tres",
	"res://dialogue/monologues/act_4_pool.tres",
]

## Story flag set when the corresponding act's monologue set is fully
## read. Index-aligned with ACT_POOL_PATHS. Lorebearer kennings key
## their unlock_flag off these exact strings.
const ACT_COMPLETION_FLAGS: Array[String] = [
	"all_monologues_read_act_1",
	"all_monologues_read_act_2",
	"all_monologues_read_act_3",
	"all_monologues_read_act_4",
]

## Flag set when EVERY monologue across EVERY act pool has been read.
## Gates the apex "Long-Memoried" lorebearer kenning.
const ALL_MONOLOGUES_FLAG: String = "all_monologues_read_total"

## Kenning id of the debug All-Seer kenning. When this kenning is unlocked,
## the path manager's scene_graph gets blanket-marked visited every time
## it's regenerated — exposing the entire map for development inspection
## and enabling fast-travel anywhere. Tracked by id rather than by flag
## because the effect is "while unlocked," not "when a flag gets set" —
## the world map can be regenerated multiple times per session and the
## effect must re-apply each time.
const ALL_SEER_KENNING_ID: String = "all_seer"


func _ready() -> void:
	_load_catalog()
	# Listen for unlock conditions. story_flag_set fires on every flag
	# write, so we catch quest completions (via QuestManager setting
	# "quest_<id>") and boss kills (GameState.mark_boss_dead → "boss_dead_<id>")
	# through one channel. No special-casing required.
	EventBus.story_flag_set.connect(_on_story_flag_set)

	# Lore carvings. Each time the player reads a monologue we accumulate
	# its identity into a story_flags Set, then re-check each act pool's
	# full identity list against that Set. When a pool's identities are
	# all present, we set the matching completion flag, which in turn
	# unlocks the matching lorebearer kenning via the normal flag path.
	#
	# Critically, the unlock condition is POOL-LEVEL, not altar-level.
	# Adding more altars to the game does NOT make the kenning harder
	# (the same pool of monologues is still all you have to read). Adding
	# more monologues to a pool DOES make the kenning take longer — by
	# design, since the unlock is "you've heard every lore beat in this
	# act," not "you've interacted with N altars."
	EventBus.monologue_read.connect(_on_monologue_read)

	# All-Seer debug kenning: applies its effect on EQUIP, not on unlock.
	# The kenning is auto-unlocked at game start (empty unlock_flag), so
	# it always sits in the catalog — but the player has to spend one of
	# their 4 equip slots to actually get the map reveal. This means:
	#   - Off by default; no automatic reveal at launch for fresh players
	#   - Costs an equip slot when active (intentional — debug power
	#     shouldn't be free alongside a full combat loadout)
	#   - Survives across launches because FLAG_EQUIPPED persists in
	#     story_flags, so a player with All-Seer equipped on Monday still
	#     has it equipped (and revealed) on Tuesday
	#
	# Two listener connections handle the two trigger paths:
	#   - kenning_equipped: fires whenever the player equips a kenning;
	#     the handler fires the reveal if it was All-Seer.
	#   - map_graph_rebuilt: fires on world regenerate; the handler
	#     re-applies the reveal if All-Seer is currently equipped (since
	#     a fresh graph starts with all visited=false).
	# Unequip intentionally does NOT undo the reveal — visited is a
	# normally-additive flag and forcing it back to false would lose
	# legitimately-visited rooms.
	EventBus.kenning_equipped.connect(_on_kenning_equipped)
	EventBus.map_graph_rebuilt.connect(_on_map_graph_rebuilt)

	# Armor changes can affect max HP (max_health_bonus field). The
	# loadout-recompute is the same code path used for kennings, so we
	# just point armor_equipped at it. The signal carries the armor
	# argument; the recompute doesn't need it (it re-reads RunState),
	# so unbind(1) drops it cleanly. Unequip emits armor_equipped(null);
	# our listener handles that case identically — re-reads the slots,
	# sees the null, contributes nothing.
	EventBus.armor_equipped.connect(_announce_loadout_change.unbind(1))
	# Shields contribute max_health_bonus while equipped (same field
	# convention as Armor), so weapon swaps need to trigger the same
	# max-HP recompute that armor swaps do. weapon_equipped fires for
	# all weapon slot changes — not just shields — but the recompute
	# is idempotent and the cost is trivial, so we listen unconditionally
	# rather than filter on slot or weapon type.
	EventBus.weapon_equipped.connect(_announce_loadout_change.unbind(2))

	# Pick up any always-unlocked kennings (unlock_flag == "") right away,
	# and re-check any flag-gated ones whose flag is already true (e.g. on
	# game launch when south_arch is pre-activated).
	_initial_unlock_pass()
	# Re-check monologue completion on launch. If a save was loaded with
	# the read-set already populated (or with all-but-one read), the
	# completion flag may need to be set now even though no fresh
	# monologue_read signal will fire this session.
	_check_all_monologue_completions()
	# Re-apply All-Seer on launch IF a previous session equipped it.
	# The equipped-ids set persists in story_flags, so this handles the
	# "I quit yesterday with All-Seer equipped, want it back today"
	# case without requiring the player to re-equip every session.
	_apply_all_seer_if_equipped()
	# Prime the equipped-kenning cache from whatever equip state loaded
	# with the save, so the first combat frame reads a populated cache
	# rather than composing it live.
	_recompute_kenning_cache()


# ============================================================================
# CATALOG LOADING
# ============================================================================

func _load_catalog() -> void:
	var dir := DirAccess.open(CATALOG_DIR)
	if dir == null:
		push_warning("KenningManager: catalog dir '%s' not found." % CATALOG_DIR)
		return
	dir.list_dir_begin()
	while true:
		var fname := dir.get_next()
		if fname == "":
			break
		if dir.current_is_dir():
			continue
		# Export-safety: in a PCK export, Godot renames resources to
		# "<name>.tres.remap". DirAccess enumerates the remapped name,
		# but load() still works on the original path — so strip the
		# suffix before the extension check.
		fname = fname.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var res: Resource = load(CATALOG_DIR + fname)
		if res is Kenning:
			var k: Kenning = res
			if k.kenning_id == "":
				push_warning("KenningManager: kenning at %s has no kenning_id, skipped." % fname)
				continue
			catalog[k.kenning_id] = k
	dir.list_dir_end()


func _initial_unlock_pass() -> void:
	# Always-unlocked kennings (unlock_flag empty). Avoids the player ever
	# seeing an entirely greyed-out catalog on a fresh save.
	for id in catalog:
		var k: Kenning = catalog[id]
		if k.unlock_flag == "":
			_unlock_internal(id, false)
	# Flag-gated kennings whose flag is already true (e.g. boss kills from
	# a previous run). Important on game load — story flags persist but
	# story_flag_set isn't re-emitted on load, so we sweep manually.
	for id in catalog:
		var k: Kenning = catalog[id]
		if k.unlock_flag != "" and GameState.has_flag(k.unlock_flag):
			_unlock_internal(id, false)


## Public re-entry point for the initial unlock pass.
##
## SaveManager.reset_all_state() calls this AFTER it wipes
## GameState.story_flags, to put back the entries that have to exist
## from the moment a new game starts:
##   - Always-unlocked kennings (unlock_flag = ""): Bare-Knuckled,
##     Cliff-Born, All-Seer, etc.
##   - Flag-gated kennings whose flag survived the wipe (today, none
##     — story_flags.clear() removes them all — but if the future ever
##     introduces persistent cross-run flags, this catches them).
##
## KenningManager's own _ready() also fires this once at engine
## startup, so the typical play session goes through it twice: once
## on launch, again on every new-game / slot-load. Re-running is
## safe because _unlock_internal is idempotent (skips already-unlocked
## ids).
##
## Named "reprime" rather than "reset" to signal that it ADDS unlocks
## back — it doesn't clear anything. A caller who wants to truly
## reset a player's kenning progress should wipe the FLAG_UNLOCKED
## list first and then call this.
func reprime_unlocks() -> void:
	_initial_unlock_pass()


# ============================================================================
# MONOLOGUE TRACKING
# ============================================================================
##
## Each time the player reads a carving, AltarCarving emits
## EventBus.monologue_read with the Dialogue's resource_path as the
## identity. We accumulate identities into the FLAG_MONOLOGUES_READ
## set (stored as an Array in story_flags, used as a set via has-check
## + append). After every read we re-run completion against each act
## pool's full ID list; pools whose IDs are now ALL present in the
## read-set get their completion flag set, which the normal
## story_flag_set → _on_story_flag_set pipeline then translates into
## kenning unlocks.

func _on_monologue_read(monologue_id: String) -> void:
	if monologue_id == "":
		return
	var read_set: Array = GameState.get_flag(FLAG_MONOLOGUES_READ, [])
	# Dedup: if we've already recorded this identity, no work to do.
	# Re-reading the same monologue should be free, not a state change.
	if monologue_id in read_set:
		return
	read_set.append(monologue_id)
	# Write back. We use set_flag so this flows through the normal
	# persistence path (story_flags writes are what GameState.save_game
	# captures), and so any future listener that wants to react to the
	# read-set growing can do so via story_flag_set on FLAG_MONOLOGUES_READ.
	GameState.set_flag(FLAG_MONOLOGUES_READ, read_set)
	_check_all_monologue_completions()


## Walk each act pool, load it, get its full ID set, compare to the
## read-set, and set the matching completion flag when complete.
## Also handles the "all monologues read" apex flag.
##
## Idempotent: setting an already-set flag is a no-op. Safe to call
## on every read.
##
## Why iterate every act every call rather than tracking per-act
## progress: pools are small (<100 entries each in any realistic
## design), the comparison is O(n) per pool, and the simplicity of
## "one source of truth, recomputed from scratch" beats the
## maintenance cost of incremental tracking. If pools ever grow into
## the thousands, this is where to optimize first.
func _check_all_monologue_completions() -> void:
	var read_set: Array = GameState.get_flag(FLAG_MONOLOGUES_READ, [])
	var all_pools_complete: bool = true
	var any_pool_has_content: bool = false

	for i in ACT_POOL_PATHS.size():
		var pool_path: String = ACT_POOL_PATHS[i]
		var flag: String = ACT_COMPLETION_FLAGS[i]
		var pool: Resource = load(pool_path)
		if not pool is MonologuePool:
			# Missing or wrong-type pool — skip this act. Don't crash
			# the manager just because someone hasn't shipped the
			# pool file for act_3_pool yet during development.
			continue
		var ids: Array[String] = (pool as MonologuePool).get_monologue_ids()
		if ids.is_empty():
			# Empty pool — by convention this act has no content yet
			# (acts 2/3/4 ship as empty stubs). Treat as "no act
			# completion possible," do NOT set the flag, and skip
			# this pool for the apex-all check below. This is what
			# keeps the apex from auto-unlocking on a save where
			# only act_1 has content.
			all_pools_complete = false
			continue
		any_pool_has_content = true
		var complete: bool = true
		for id in ids:
			if not (id in read_set):
				complete = false
				break
		if complete:
			if not GameState.has_flag(flag):
				GameState.set_flag(flag, true)
		else:
			all_pools_complete = false

	# Apex flag: only set if EVERY non-empty act pool is complete AND
	# at least one act pool actually had content (so an empty-catalog
	# save can't accidentally unlock the apex on first launch).
	if all_pools_complete and any_pool_has_content:
		if not GameState.has_flag(ALL_MONOLOGUES_FLAG):
			GameState.set_flag(ALL_MONOLOGUES_FLAG, true)


# ============================================================================
# ALL-SEER (debug map reveal)
# ============================================================================
##
## All-Seer is a development convenience kenning: when EQUIPPED, every
## scene on the world map is treated as visited. This serves two purposes:
##   1. Authors can inspect generated map layouts at a glance, including
##      seeds that would normally require running through the whole
##      corridor to verify connectivity.
##   2. Authors can fast-travel to any POI (town, altar, dungeon entrance)
##      from launch, to spot-check new content (enemies, items, rooms) in
##      its actual deployment context without playing through the unlock
##      gate first.
##
## Trigger contract:
##   - On EQUIP → reveal everything immediately
##   - On UNEQUIP → no-op (visited is normally additive; reverting would
##     lose legitimately-explored rooms)
##   - On world regenerate while equipped → re-apply the reveal
##
## The effect is map-state-only — it doesn't touch combat, doesn't unlock
## doors, doesn't bypass section reveal flags (those still gate display
## of *whole regions* on the world map). It only writes visited=true on
## scene_graph nodes that ARE displayed.


func _on_kenning_equipped(kenning_id: String) -> void:
	# Fired by KenningManager.equip() after the equipped_ids set is
	# updated. If this was All-Seer being equipped, fire the reveal now.
	# Other kennings fall through silently.
	if kenning_id == ALL_SEER_KENNING_ID:
		_apply_all_seer_reveal()


func _on_map_graph_rebuilt() -> void:
	# Fired by PathManager._build_graph and PathManager.mark_all_visited.
	# Re-apply the reveal only if All-Seer is currently equipped — an
	# unequipped All-Seer should let a regenerated world start with the
	# normal fog-of-war, even though the kenning is still unlocked.
	#
	# Self-recursion is prevented because _apply_all_seer_reveal writes
	# scene_graph directly rather than going through PathManager.mark_all_visited,
	# which would re-fire this signal.
	if is_equipped(ALL_SEER_KENNING_ID):
		_apply_all_seer_reveal()


func _apply_all_seer_if_equipped() -> void:
	# Used at _ready to handle the "previous session equipped this and we
	# just loaded the save" case. FLAG_EQUIPPED persists in story_flags,
	# so is_equipped is correct on first launch frame even before the
	# player touches the menu.
	if is_equipped(ALL_SEER_KENNING_ID):
		_apply_all_seer_reveal()


func _apply_all_seer_reveal() -> void:
	# Write visited flags directly on PathManager.scene_graph rather than
	# calling PathManager.mark_all_visited(). mark_all_visited emits
	# map_graph_rebuilt, which is the signal that triggers our handler;
	# calling it would recurse infinitely. So we mutate the dict directly
	# here. The world map UI listens to other events besides
	# map_graph_rebuilt for redraws (queue_redraw on toggle-open), so
	# skipping the re-emit doesn't lose the visual update — the next
	# time the player opens the map, they'll see the reveal.
	for k in PathManager.scene_graph.keys():
		PathManager.scene_graph[k]["visited"] = true


# ============================================================================
# QUERIES
# ============================================================================

func get_kenning(kenning_id: String) -> Kenning:
	return catalog.get(kenning_id)


func is_unlocked(kenning_id: String) -> bool:
	var arr: Array = GameState.get_flag(FLAG_UNLOCKED, [])
	return arr.has(kenning_id)


func is_equipped(kenning_id: String) -> bool:
	var arr: Array = GameState.get_flag(FLAG_EQUIPPED, [])
	return arr.has(kenning_id)


func unlocked_ids() -> Array:
	return GameState.get_flag(FLAG_UNLOCKED, [])


func equipped_ids() -> Array:
	return GameState.get_flag(FLAG_EQUIPPED, [])


func equipped_kennings() -> Array[Kenning]:
	var out: Array[Kenning] = []
	for id in equipped_ids():
		if catalog.has(id):
			out.append(catalog[id])
	return out


func all_kennings() -> Array[Kenning]:
	# Sorted: unlocked first (so the player's roster sits at top), then by
	# category for visual grouping, then alphabetical for stability.
	var out: Array[Kenning] = []
	for k in catalog.values():
		out.append(k)
	out.sort_custom(func(a: Kenning, b: Kenning) -> bool:
		var au: bool = is_unlocked(a.kenning_id)
		var bu: bool = is_unlocked(b.kenning_id)
		if au != bu:
			return au  # true sorts first
		if a.category != b.category:
			return a.category < b.category
		return a.display_name < b.display_name
	)
	return out


# ============================================================================
# MUTATIONS
# ============================================================================

## Equip a kenning into the first empty slot. Returns false if no slot
## is empty or the kenning isn't unlocked. Tells the player via a Toast
## why it failed.
func equip(kenning_id: String) -> bool:
	if not is_unlocked(kenning_id):
		Toast.show_message("Kenning not yet earned.", Color(0.7, 0.5, 0.4))
		return false
	if is_equipped(kenning_id):
		return false
	var arr: Array = equipped_ids().duplicate()
	if arr.size() >= MAX_EQUIPPED:
		Toast.show_message("Only %d names can be borne at once." % MAX_EQUIPPED,
			Color(0.7, 0.5, 0.4))
		return false
	arr.append(kenning_id)
	GameState.set_flag(FLAG_EQUIPPED, arr)
	EventBus.kenning_equipped.emit(kenning_id)
	_announce_loadout_change()
	return true


func unequip(kenning_id: String) -> void:
	var arr: Array = equipped_ids().duplicate()
	arr.erase(kenning_id)
	GameState.set_flag(FLAG_EQUIPPED, arr)
	EventBus.kenning_unequipped.emit(kenning_id)
	_announce_loadout_change()


## Re-emit the run-time stat signals that consumers (player, HUD) listen on.
## Called on equip/unequip so caps update mid-run.
##
## HP coordination is intentionally minimal here — we just update
## RunState.max_health and emit player_health_changed for the HUD. The
## Player listens on kenning_equipped/unequipped separately and runs the
## actual delta arithmetic against its HealthComponent (the source of
## truth for current_health while alive). Doing the delta math here too
## would cause a double-update where the Player's clamp overrode our
## fresh value.
func _announce_loadout_change() -> void:
	# Loadout changed — refresh the equipped-kenning cache FIRST, so the
	# get_max_health_bonus() call below (and every combat-frame getter
	# after) reads the new loadout. This also fires on armor/weapon swaps
	# that don't touch kennings; rebuilding a <=4-element array then is
	# trivial and keeps one invalidation path for the whole cache.
	_recompute_kenning_cache()
	# Max HP composes from four sources: the run-scope base, kenning
	# bonuses (e.g. Bear-Hearted), armor bonuses (build pieces like
	# Striker's Vest that trade defense for offense don't necessarily
	# add HP, but the system supports armor that does), and shield
	# bonuses (the mail-backed late-act-2 shields carry HP passively).
	var new_max: float = RunState.BASE_MAX_HEALTH \
		+ get_max_health_bonus() \
		+ RunState.get_armor_max_health_bonus() \
		+ RunState.get_shield_max_health_bonus()
	# Rune MAX_HP bonus is percentage-based: add it as a fraction of the
	# base after all flat bonuses, so the percentage scales with the total.
	new_max *= RunState.get_rune_multiplier(RunestoneItem.RuneStat.MAX_HP)
	RunState.max_health = new_max
	# Clamp the cached RunState value — Player will overwrite it in its
	# own listener once the HealthComponent settles, but this keeps any
	# code that reads RunState.current_health before that listener fires
	# from seeing an above-cap number.
	RunState.current_health = minf(RunState.current_health, new_max)
	EventBus.player_health_changed.emit(RunState.current_health, new_max)


# ============================================================================
# UNLOCKS
# ============================================================================

func _on_story_flag_set(flag: String, value: Variant) -> void:
	# Only act on truthy bool writes. story_flag_set fires for EVERY
	# GameState.set_flag call — including our own array-valued mirrors
	# (_kenning_unlocked_ids, _kenning_equipped_ids). Comparing an Array
	# directly to `false` is a runtime error in GDScript, so we filter
	# by type first and ignore anything that isn't a bool true.
	#
	# Side effect: if a future system sets a flag to an int / string /
	# enum and wants kennings to unlock from it, that flag has to come
	# in as `true` (bool) — set the descriptive value in a different
	# flag, and emit a bool true on the unlock flag. Keeps the unlock
	# channel narrow on purpose.
	if not (value is bool):
		return
	if not value:
		return
	for id in catalog:
		var k: Kenning = catalog[id]
		if k.unlock_flag == flag and not is_unlocked(id):
			_unlock_internal(id, true)


func _unlock_internal(kenning_id: String, announce: bool) -> void:
	if not catalog.has(kenning_id):
		return
	var arr: Array = GameState.get_flag(FLAG_UNLOCKED, []).duplicate()
	if arr.has(kenning_id):
		return
	arr.append(kenning_id)
	# Write without re-triggering story_flag_set's unlock pass — set_flag
	# does emit story_flag_set, but our handler skips non-matching keys, so
	# this is fine (it's not a recursive loop).
	GameState.set_flag(FLAG_UNLOCKED, arr)
	EventBus.kenning_unlocked.emit(kenning_id)
	if announce:
		var k: Kenning = catalog[kenning_id]
		Toast.show_message("Name earned: %s" % k.display_name, Color(0.95, 0.80, 0.35))


# ============================================================================
# AGGREGATE STAT GETTERS — composed multiplicatively across equipped kennings
# ============================================================================
##
## These read _equipped_kennings_cache rather than equipped_kennings() so
## the hot path allocates nothing. The cache is rebuilt by
## _recompute_kenning_cache below, driven off loadout changes only.


## Rebuild the equipped-kenning cache from the persisted equipped-ids set.
## Cheap (<= MAX_EQUIPPED lookups); only ever called on a loadout change,
## never per frame.
func _recompute_kenning_cache() -> void:
	_equipped_kennings_cache.clear()
	for id in equipped_ids():
		if catalog.has(id):
			_equipped_kennings_cache.append(catalog[id])

## Multiplier on outgoing damage for a given weapon (so weapon-type-gated
## kennings can filter on the weapon's category). Pass null if the source
## isn't a Weapon — only the unfiltered (ANY) kennings will apply.
func get_damage_dealt_multiplier(weapon: Resource = null) -> float:
	var m: float = 1.0
	var weapon_cat: String = ""
	if weapon != null and "category" in weapon:
		weapon_cat = weapon.category
	for k in _equipped_kennings_cache:
		# Conditional kennings (HEALTH_BELOW / HEALTH_ABOVE) contribute
		# nothing while their condition isn't met. is_active() is two
		# float reads against RunState — hot-path safe.
		if not k.is_active():
			continue
		# Broad multiplier — gated by weapon_filter if the kenning specifies one.
		if k.damage_dealt_multiplier != 1.0:
			var applies: bool = true
			match k.weapon_filter:
				Kenning.WeaponFilter.MELEE:  applies = weapon_cat == "melee"
				Kenning.WeaponFilter.RANGED: applies = weapon_cat == "ranged"
				Kenning.WeaponFilter.SPELL:  applies = weapon_cat == "spell"
				_:                           applies = true
			if applies:
				m *= k.damage_dealt_multiplier
		# Per-element multiplier — always layers on if the weapon's element matches.
		if weapon != null and "element" in weapon:
			var elem: int = int(weapon.element)
			if k.element_damage_multipliers.has(elem):
				m *= float(k.element_damage_multipliers[elem])
	return m


## Multiplier on incoming damage. `info` is the damage_info dict — used to
## look up element-specific resistances.
func get_damage_taken_multiplier(info: Dictionary = {}) -> float:
	var m: float = 1.0
	var elem: int = int(info.get("element", 0))
	for k in _equipped_kennings_cache:
		if not k.is_active():
			continue
		m *= k.damage_taken_multiplier
		if k.element_resistance_multipliers.has(elem):
			m *= float(k.element_resistance_multipliers[elem])
	return m


func get_move_speed_multiplier() -> float:
	var m: float = 1.0
	for k in _equipped_kennings_cache:
		if not k.is_active():
			continue
		m *= k.move_speed_multiplier
	return m


func get_dash_cooldown_multiplier() -> float:
	var m: float = 1.0
	for k in _equipped_kennings_cache:
		if not k.is_active():
			continue
		m *= k.dash_cooldown_multiplier
	return m


## NOT gated on is_active(): a health-conditional max-HP bonus would be
## circular (the HP fraction the condition reads depends on max HP), and
## max HP is only recomputed on loadout changes, so a conditional value
## would go stale the instant HP crossed the threshold mid-combat.
## Conditional kennings should stick to multiplier effects — see the
## Condition enum docs in kenning.gd.
func get_max_health_bonus() -> float:
	var bonus: float = 0.0
	for k in _equipped_kennings_cache:
		bonus += k.max_health_bonus
	return bonus


## True if any equipped, currently-active kenning grants binding immunity
## (Net-Cutter). Consumed by StatusEffectComponent.apply (blocks binding
## status effects on the player) and by the player's knockback receiver
## (negates pull impulses). Respects Condition via is_active() so a
## hypothetical conditional binding-immunity kenning composes correctly.
func is_binding_immune() -> bool:
	for k in _equipped_kennings_cache:
		if k.binding_immunity and k.is_active():
			return true
	return false
