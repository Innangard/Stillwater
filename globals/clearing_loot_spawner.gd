extends Node
## Runtime loot spawner for clearings. Populates every clearing scene
## with randomized pickups on entry, seeded from RunState.world_seed so
## the loot layout is deterministic per run but different across deaths.
##
## Each clearing gets:
##   - Exactly 1 rune (always) at the RuneMarker position
##   - 0-1 equippable item (weapon/armor/shield) at the EquipMarker
##   - 0-1 non-equippable item (reagent/consumable) at the MiscMarker
##
## Items are pulled from act-gated pools. Already-collected items
## (tracked via RunState.consumed_node_paths) don't respawn on re-entry.
##
## NOTE: No class_name — registered as autoload "ClearingLootSpawner".

const PICKUP_SCENE: PackedScene = preload("res://pickups/pickup.tscn")

## Probability that an equippable item spawns in a clearing.
const EQUIP_CHANCE: float = 0.55
## Probability that a non-equippable item spawns.
const MISC_CHANCE: float = 0.45

# ============================================================================
# REGION → ACT MAPPING
# ============================================================================
## Maps the region folder name (from the scene path) to an act number.
## Act determines which tier of loot can appear.
const REGION_ACT: Dictionary = {
	# Act 1
	"east_path": 1,
	"north_path": 1,
	"sprekken": 1,
	"sprekken_approach": 1,
	"eastreach_path": 1,
	"myrkfen": 1,
	"garnvik": 1,
	"coast_path": 1,
	"hollowmere_path": 1,
	"westmoor_path": 1,
	# Act 2
	"sundust_path": 2,
	"deep_desert_path": 2,
	"brann": 2,
	"hrimbjarg_path": 2,
	"thursdal_path": 2,
	"hindarfjall_path": 2,
}

# ============================================================================
# LOOT POOLS
# ============================================================================
# Each pool is an array of resource paths. The spawner loads one at random.
# Pools are split by act so early-game clearings don't drop endgame gear.

# --- Rune pools (by conduit = act gate) ---
# Act 1: slate + bone conduits
const RUNES_ACT1: Array = [
	"res://items/runestones/uruz_runestone.tres",
	"res://items/runestones/uruz_runebone.tres",
	"res://items/runestones/ansuz_runestone.tres",
	"res://items/runestones/ansuz_runebone.tres",
	"res://items/runestones/berkano_runestone.tres",
	"res://items/runestones/berkano_runebone.tres",
	"res://items/runestones/gebo_runestone.tres",
	"res://items/runestones/gebo_runebone.tres",
	"res://items/runestones/kenaz_runestone.tres",
	"res://items/runestones/kenaz_runebone.tres",
	"res://items/runestones/hagalaz_runestone.tres",
	"res://items/runestones/hagalaz_runebone.tres",
	"res://items/runestones/algiz_runestone.tres",
	"res://items/runestones/algiz_runebone.tres",
	"res://items/runestones/laguz_runestone.tres",
	"res://items/runestones/laguz_runebone.tres",
	"res://items/runestones/raido_runestone.tres",
	"res://items/runestones/raido_runebone.tres",
	"res://items/runestones/wunjo_runestone.tres",
	"res://items/runestones/wunjo_runebone.tres",
	"res://items/runestones/nauthiz_runestone.tres",
	"res://items/runestones/nauthiz_runebone.tres",
	"res://items/runestones/sowilo_runestone.tres",
	"res://items/runestones/sowilo_runebone.tres",
	"res://items/runestones/isa_runestone.tres",
	"res://items/runestones/isa_runebone.tres",
	"res://items/runestones/perthro_runestone.tres",
	"res://items/runestones/perthro_runebone.tres",
	"res://items/runestones/jera_runestone.tres",
	"res://items/runestones/jera_runebone.tres",
	"res://items/runestones/fehu_runestone.tres",
	"res://items/runestones/fehu_runebone.tres",
	"res://items/runestones/eihwaz_runestone.tres",
	"res://items/runestones/eihwaz_runebone.tres",
	# Rare letters at lower frequency (listed once vs twice for common)
	"res://items/runestones/tiwaz_runebone.tres",
	"res://items/runestones/dagaz_runebone.tres",
	"res://items/runestones/thurisaz_runebone.tres",
	"res://items/runestones/mannaz_runebone.tres",
	"res://items/runestones/ehwaz_runebone.tres",
	"res://items/runestones/ingwaz_runebone.tres",
	"res://items/runestones/othala_runebone.tres",
]

# Act 2: wood conduits + slate/bone still possible
const RUNES_ACT2: Array = [
	# Wood conduits (stronger)
	"res://items/runestones/uruz_runewood.tres",
	"res://items/runestones/ansuz_runewood.tres",
	"res://items/runestones/berkano_runewood.tres",
	"res://items/runestones/gebo_runewood.tres",
	"res://items/runestones/kenaz_runewood.tres",
	"res://items/runestones/hagalaz_runewood.tres",
	"res://items/runestones/algiz_runewood.tres",
	"res://items/runestones/laguz_runewood.tres",
	"res://items/runestones/raido_runewood.tres",
	"res://items/runestones/wunjo_runewood.tres",
	"res://items/runestones/nauthiz_runewood.tres",
	"res://items/runestones/sowilo_runewood.tres",
	"res://items/runestones/isa_runewood.tres",
	"res://items/runestones/perthro_runewood.tres",
	"res://items/runestones/jera_runewood.tres",
	"res://items/runestones/fehu_runewood.tres",
	"res://items/runestones/eihwaz_runewood.tres",
	# Rare wood
	"res://items/runestones/tiwaz_runewood.tres",
	"res://items/runestones/dagaz_runewood.tres",
	"res://items/runestones/thurisaz_runewood.tres",
	"res://items/runestones/mannaz_runewood.tres",
	"res://items/runestones/ehwaz_runewood.tres",
	"res://items/runestones/ingwaz_runewood.tres",
	"res://items/runestones/othala_runewood.tres",
	# Some slate/bone still appear (weaker but variety)
	"res://items/runestones/uruz_runestone.tres",
	"res://items/runestones/ansuz_runestone.tres",
	"res://items/runestones/raido_runestone.tres",
	"res://items/runestones/wunjo_runestone.tres",
	"res://items/runestones/fehu_runestone.tres",
	"res://items/runestones/eihwaz_runestone.tres",
]

# --- Equipment pools (weapons + armor + shields) ---
# Act 1: starter and early-mid gear
const EQUIP_ACT1: Array = [
	# 1H melee
	"res://weapons/instances/player_weapons/pilgrim_spear.tres",
	"res://weapons/instances/player_weapons/pilgrim_mace.tres",
	"res://weapons/instances/player_weapons/rusted_dagger.tres",
	"res://weapons/instances/player_weapons/worn_blade.tres",
	"res://weapons/instances/player_weapons/hearthbrand.tres",
	"res://weapons/instances/player_weapons/briar_fang.tres",
	"res://weapons/instances/player_weapons/shadowfang.tres",
	"res://weapons/instances/player_weapons/emberspear.tres",
	"res://weapons/instances/player_weapons/frostbite_spear.tres",
	"res://weapons/instances/player_weapons/venomfang_spear.tres",
	"res://weapons/instances/player_weapons/rimeblade.tres",
	"res://weapons/instances/player_weapons/vilethorn.tres",
	# 2H melee
	"res://weapons/instances/player_weapons/chipped_greatsword.tres",
	"res://weapons/instances/player_weapons/bog_iron_greataxe.tres",
	# Ranged
	"res://weapons/instances/player_weapons/crooked_bow.tres",
	"res://weapons/instances/player_weapons/longbow.tres",
	"res://weapons/instances/player_weapons/froststring_bow.tres",
	"res://weapons/instances/player_weapons/splinter_volley.tres",
	"res://weapons/instances/player_weapons/bone_crossbow.tres",
	# Shields
	"res://weapons/instances/player_weapons/oak_shield.tres",
	"res://weapons/instances/player_weapons/driftwood_buckler.tres",
	"res://weapons/instances/player_weapons/pale_ash_targe.tres",
	"res://weapons/instances/player_weapons/cold_iron_heater.tres",
	# Armor — helmets
	"res://items/armor/pilgrims_hood.tres",
	"res://items/armor/hunters_hood.tres",
	"res://items/armor/footpad_cap.tres",
	"res://items/armor/fenwalker_cowl.tres",
	"res://items/armor/peat_cured_hood.tres",
	"res://items/armor/frostlaced_hood.tres",
	"res://items/armor/tidewrack_hood.tres",
	"res://items/armor/cinder_cowl.tres",
	"res://items/armor/miasma_hood.tres",
	"res://items/armor/marksman_hood.tres",
	# Armor — chest
	"res://items/armor/footpad_jerkin.tres",
	"res://items/armor/bogplate_vest.tres",
	"res://items/armor/drifthide_coat.tres",
	"res://items/armor/marksman_jerkin.tres",
	# Armor — boots
	"res://items/armor/pilgrims_sandals.tres",
	"res://items/armor/footpad_boots.tres",
	"res://items/armor/drowned_sandals.tres",
	"res://items/armor/rootgrip_boots.tres",
	"res://items/armor/bog_wool_boots.tres",
	"res://items/armor/marksman_boots.tres",
]

# Act 2: mid-late gear
const EQUIP_ACT2: Array = [
	# 1H melee
	"res://weapons/instances/player_weapons/heartcoal_brand.tres",
	"res://weapons/instances/player_weapons/lichen_edge.tres",
	"res://weapons/instances/player_weapons/thunderstrike_spear.tres",
	"res://weapons/instances/player_weapons/sparkblade.tres",
	"res://weapons/instances/player_weapons/shroudfang_dagger.tres",
	"res://weapons/instances/player_weapons/wraithfoot_shiv.tres",
	"res://weapons/instances/player_weapons/wormgold_falchion.tres",
	"res://weapons/instances/player_weapons/blightcrusher.tres",
	"res://weapons/instances/player_weapons/wyrmstinger_spear.tres",
	# 2H melee
	"res://weapons/instances/player_weapons/cinder_maul.tres",
	"res://weapons/instances/player_weapons/permafrost_maul.tres",
	"res://weapons/instances/player_weapons/skalds_lament.tres",
	"res://weapons/instances/player_weapons/slagsworn_greataxe.tres",
	"res://weapons/instances/player_weapons/stormhammer.tres",
	"res://weapons/instances/player_weapons/stormcaller_hammer.tres",
	"res://weapons/instances/player_weapons/skyfathers_lance.tres",
	"res://weapons/instances/player_weapons/brood_iron_lance.tres",
	"res://weapons/instances/player_weapons/pyresand_maul.tres",
	# Ranged
	"res://weapons/instances/player_weapons/cindershot_bow.tres",
	"res://weapons/instances/player_weapons/glacial_arc.tres",
	"res://weapons/instances/player_weapons/hoarfrost_bow.tres",
	"res://weapons/instances/player_weapons/emberlance_bow.tres",
	"res://weapons/instances/player_weapons/stormpierce_bow.tres",
	"res://weapons/instances/player_weapons/gravecaller_crossbow.tres",
	"res://weapons/instances/player_weapons/venomfall_bow.tres",
	"res://weapons/instances/player_weapons/voltbow.tres",
	# Shields
	"res://weapons/instances/player_weapons/frost_banded_round.tres",
	"res://weapons/instances/player_weapons/bone_stitched_pavise.tres",
	"res://weapons/instances/player_weapons/moor_mail_bulwark.tres",
	"res://weapons/instances/player_weapons/hoarfrost_aegis.tres",
	# Armor — helmets
	"res://items/armor/ironmoss_helm.tres",
	"res://items/armor/peakwatch_cowl.tres",
	"res://items/armor/gravewalker_cowl.tres",
	"res://items/armor/sparkwoven_hood.tres",
	"res://items/armor/galewalker_hood.tres",
	"res://items/armor/skald_circlet.tres",
	"res://items/armor/pyresmith_helm.tres",
	"res://items/armor/reaver_helm.tres",
	"res://items/armor/bonebreaker_great_helm.tres",
	# Armor — chest
	"res://items/armor/cairnstone_cuirass.tres",
	"res://items/armor/stormwarden_hauberk.tres",
	"res://items/armor/moor_mail_hauberk.tres",
	"res://items/armor/gravewalker_robe.tres",
	"res://items/armor/galewalker_vest.tres",
	"res://items/armor/skald_robe.tres",
	"res://items/armor/pyresmith_apron.tres",
	"res://items/armor/pyrelined_cuirass.tres",
	"res://items/armor/reaver_brigandine.tres",
	"res://items/armor/bonebreaker_plate.tres",
	# Armor — boots
	"res://items/armor/ridgerunner_greaves.tres",
	"res://items/armor/mistwalker_sandals.tres",
	"res://items/armor/galestride_sandals.tres",
	"res://items/armor/gravewalker_slippers.tres",
	"res://items/armor/galewalker_runners.tres",
	"res://items/armor/skald_buskins.tres",
	"res://items/armor/embertread_sandals.tres",
	"res://items/armor/pyresmith_boots.tres",
	"res://items/armor/reaver_treads.tres",
	"res://items/armor/bonebreaker_greaves.tres",
	"res://items/armor/blightstep_sandals.tres",
]

# --- Non-equippable pools (reagents + consumables) ---
const MISC_ACT1: Array = [
	"res://items/instances/pale_ash.tres",
	"res://items/instances/hollow_bone.tres",
	"res://items/instances/bog_bile.tres",
	"res://items/instances/frost_filament.tres",
	"res://items/instances/peat_pitch.tres",
	"res://items/instances/ghost_lichen.tres",
	"res://items/instances/marsh_reed_bundle.tres",
	"res://items/instances/gravewax.tres",
	"res://items/instances/runeslate_tablet.tres",
	"res://items/instances/bone_tablet.tres",
	"res://items/instances/cold_iron_filing.tres",
	"res://items/instances/brine_crystal.tres",
	"res://items/instances/living_fire.tres",
	"res://items/instances/wraithseed.tres",
	# Consumables
	"res://items/instances/soul_phial.tres",
	"res://items/instances/cinder_salt.tres",
	"res://items/instances/fen_poultice.tres",
	"res://items/instances/brine_tonic.tres",
]

const MISC_ACT2: Array = [
	"res://items/instances/sky_iron.tres",
	"res://items/instances/mountain_marrow.tres",
	"res://items/instances/hoarfrost_tear.tres",
	"res://items/instances/heartcoal.tres",
	"res://items/instances/ember_honey.tres",
	"res://items/instances/living_wood_tablet.tres",
	"res://items/instances/deep_gold_tablet.tres",
	"res://items/instances/husk_of_sand.tres",
	"res://items/instances/venom_sac.tres",
	"res://items/instances/slag_glass_shard.tres",
	"res://items/instances/skyfathers_tooth.tres",
	"res://items/instances/wormgold.tres",
	# Consumables
	"res://items/instances/frostbloom_draught.tres",
	"res://items/instances/pyre_salve.tres",
	"res://items/instances/soul_phial.tres",
	"res://items/instances/cinder_salt.tres",
	# Some Act 1 reagents still appear (useful for crafting)
	"res://items/instances/pale_ash.tres",
	"res://items/instances/frost_filament.tres",
	"res://items/instances/cold_iron_filing.tres",
	"res://items/instances/peat_pitch.tres",
]


func _ready() -> void:
	# Subscribe to scene changes. When a new scene loads, check if it's
	# a clearing and spawn loot.
	get_tree().node_added.connect(_on_node_added)


## Fires for every node entering the tree. We watch for RegionRoot nodes
## (the root of every world scene) and check if the scene is a clearing.
## This is more reliable than tree_changed because it fires AFTER the
## scene tree is fully built, so marker nodes are findable.
func _on_node_added(node: Node) -> void:
	if not (node is Node2D) or not node.has_method("get") \
			or not ("region_id" in node):
		return
	# Defer so all children (markers, exits, etc.) are in the tree.
	call_deferred("_try_populate", node)


func _try_populate(region_root: Node) -> void:
	if not is_instance_valid(region_root):
		return
	var scene_path: String = region_root.scene_file_path
	if scene_path == "":
		# Fallback: use the tree's current scene path.
		var current: Node = get_tree().current_scene
		if current:
			scene_path = current.scene_file_path
	if not _is_clearing(scene_path):
		return
	var act: int = _get_act(scene_path)
	_spawn_loot(region_root, scene_path, act)


func _is_clearing(scene_path: String) -> bool:
	# Filename must contain "clearing" — matches the authoring convention.
	var fname: String = scene_path.get_file().to_lower()
	return "clearing" in fname


func _get_act(scene_path: String) -> int:
	# Extract the region folder from the path. Scene paths look like:
	# res://world/regions/east_path/east_forest_clearing_1.tscn
	# The region is the folder name after "regions/".
	var parts: PackedStringArray = scene_path.split("/")
	for i in range(parts.size()):
		if parts[i] == "regions" and i + 1 < parts.size():
			var region: String = parts[i + 1]
			# If the file is directly in regions/ (e.g. corpse_clearing),
			# region would be the filename. Default to act 1.
			if region.ends_with(".tscn"):
				return 1
			return REGION_ACT.get(region, 1)
	return 1


func _spawn_loot(root: Node, scene_path: String, act: int) -> void:
	# Deterministic RNG for this clearing, seeded from world seed + scene.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(RunState.world_seed) + scene_path)

	# Find marker nodes.
	var rune_marker: Node2D = root.get_node_or_null("RuneMarker")
	var equip_marker: Node2D = root.get_node_or_null("EquipMarker")
	var misc_marker: Node2D = root.get_node_or_null("MiscMarker")

	# Always spawn a rune.
	if rune_marker:
		var pool: Array = RUNES_ACT1 if act == 1 else RUNES_ACT2
		_spawn_pickup_at(root, rune_marker.position, pool, rng, scene_path, "rune")

	# Maybe spawn an equippable.
	if equip_marker and rng.randf() < EQUIP_CHANCE:
		var pool: Array = EQUIP_ACT1 if act == 1 else EQUIP_ACT2
		_spawn_pickup_at(root, equip_marker.position, pool, rng, scene_path, "equip")

	# Maybe spawn a misc item.
	if misc_marker and rng.randf() < MISC_CHANCE:
		var pool: Array = MISC_ACT1 if act == 1 else MISC_ACT2
		_spawn_pickup_at(root, misc_marker.position, pool, rng, scene_path, "misc")


func _spawn_pickup_at(root: Node, pos: Vector2, pool: Array,
		rng: RandomNumberGenerator, scene_path: String, slot: String) -> void:
	if pool.is_empty():
		return

	# Pick a random resource from the pool.
	var idx: int = rng.randi_range(0, pool.size() - 1)
	var res_path: String = pool[idx]
	var res: Resource = load(res_path)
	if res == null:
		push_warning("ClearingLootSpawner: failed to load %s" % res_path)
		return

	# Build a stable identity for consumption tracking so collected items
	# don't reappear on scene re-entry. Uses the scene path + slot name
	# (not the item, since the item is random per-run but the slot is fixed).
	var identity: String = scene_path + "::loot_" + slot
	if RunState.consumed_node_paths.has(identity):
		return

	var pickup: Node = PICKUP_SCENE.instantiate()
	pickup.position = pos
	pickup.persistent_per_run = true

	# Route to the correct pickup field based on resource type.
	if res is Weapon:
		pickup.weapon = res
	elif res is Item:
		pickup.item = res

	# Override the consumption identity so the spawner's stable identity
	# is used instead of the pickup's auto-generated one. We set a meta
	# that pickup.gd checks (if present) as an override.
	pickup.set_meta("loot_identity", identity)

	root.add_child(pickup)
