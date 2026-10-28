extends Node
## Autoloaded path manager. Generates every randomized chain in the game
## from one data table (CHAIN_DEFS) and builds the scene_graph the world
## map renders from.
##
## ── Architecture (post-refactor) ────────────────────────────────────────
## The old file was 14 hand-copied chain blocks (constants, pools, arrays,
## generation calls, graph calls, override calls — six edit sites per
## chain). That structure produced real bugs: a duplicated seed offset,
## and three chains anchoring on their parent's INTENDED endpoint instead
## of its RESOLVED endpoint. Everything is now driven by:
##
##   POOL_DEFS    — scene pool directories, keyed by pool id.
##   CHAIN_DEFS   — one entry per chain, in GENERATION order. Downstream
##                  chains reference upstream chains by id ("anchor_base")
##                  and always anchor on the upstream chain's RESOLVED
##                  endpoint cell, so natural-end shortfalls propagate
##                  correctly by construction.
##   GRAPH_ORDER  — the order chains are emitted into scene_graph
##                  (matters for _ensure_connection back-wiring).
##   OVERRIDE_ORDER — the order runtime exit overrides apply (later
##                  chains win on shared scenes; see apply_overrides).
##
## Adding a chain = one CHAIN_DEFS entry + one id in GRAPH_ORDER and
## OVERRIDE_ORDER (+ a POOL_DEFS entry if it has its own scene pool).
##
## ── Behavioral fixes folded into the refactor ───────────────────────────
##   - coast_to_west seed offset was 11000, colliding with hindarfjall.
##     Now 14000 (next free after thursdal's 13000).
##   - hollowmere / sundust downstream chains (the three act-2 mountain
##     chains, deep_desert) now anchor on resolved endpoints, fixing the
##     orphaned-corridor bug when the parent chain natural-ends short.
##   - The Nasus City / Sundust Gate cells are reserved at the RESOLVED
##     endpoint (not the intended target), so the reservation always
##     matches where the paired scene is actually placed.
##   - The coast pool is shared by the coast and coast_to_west chains;
##     buffer/clearing usage is now tracked PER POOL across chains, so a
##     scene file can no longer appear in two chains at once (which
##     miswired its exits to whichever chain applied overrides last).
##   - Pool scanning strips the ".remap" suffix Godot appends to
##     resources in exported PCKs — without this, every DirAccess scan
##     finds zero scenes in an export and the world fails to generate.
##   - Pool scanning sorts filenames before use, so a given world_seed
##     produces the same layout regardless of filesystem enumeration
##     order (cross-platform seed stability).
##   - Buffer/clearing exit detection reads PackedScene.get_state()
##     (SceneState) instead of instantiating every pool scene at startup.
##
## NOTE: No class_name (autoload "PathManager").

const OPPOSITE := {
	"north": "south", "south": "north",
	"east": "west", "west": "east",
}
const DIR_VECTORS := {
	"north": Vector2i(0, -1), "south": Vector2i(0, 1),
	"east": Vector2i(1, 0), "west": Vector2i(-1, 0),
}

## Sentinel meaning "no target cell" — chains with this random-walk freely
## (the two dungeon interiors).
const SENTINEL := Vector2i(-9999, -9999)

const TYPE_NORMAL := "normal"
const TYPE_TOWN := "town"
const TYPE_CLEARING := "clearing"
const TYPE_BUFFER := "buffer"
const TYPE_ARCH := "arch"
const TYPE_DUNGEON_ENTRANCE := "dungeon_entrance"
const TYPE_BOSS := "boss"
const TYPE_ALTAR := "altar"

const SECTION_START := "start"
const SECTION_STORSPRUNGA := "storsprunga"
const SECTION_NASUS := "nasus"
const SECTION_NORTH_CHAIN := "north_chain"
const SECTION_EAST := "east"
const SECTION_EAST_CHAIN := "east_chain"
const SECTION_SPREKKEN := "sprekken"
const SECTION_BRANN := "brann"
const SECTION_COAST := "coast"
const SECTION_WESTMOOR := "westmoor"
const SECTION_EASTREACH := "eastreach"
const SECTION_SPREKKEN_APPROACH := "sprekken_approach"
const SECTION_MYRKFEN_APPROACH := "myrkfen_approach"
const SECTION_BRANN_APPROACH := "brann_approach"
const SECTION_MYRKFEN := "myrkfen"
const SECTION_GARNVIK := "garnvik"
const SECTION_SUNDUST := "sundust"
const SECTION_DEEP_DESERT := "deep_desert"
const SECTION_HOLLOWMERE := "hollowmere"
## Storsprunga Altar section covers the coast chain's altar terminus AND
## the coast→westmoor connector north of it — one logical region
## ("the wilderness north of Storsprunga"), one section flag.
const SECTION_STORSPRUNGA_ALTAR := "storsprunga_altar"
const SECTION_HINDARFJALL := "hindarfjall"
const SECTION_HRIMBJARG := "hrimbjarg"
const SECTION_THURSDAL := "thursdal"

## Act 2 overworld sections — paths, towns, altars, and approaches for
## the six Act 2 bosses beyond Hollowmere.
const SECTION_STRANDVIK := "strandvik"
const SECTION_DRIFTWORKS := "driftworks"
const SECTION_BARRHOLT := "barrholt"
const SECTION_KALDRHOLT := "kaldrholt"
const SECTION_VINDFELL := "vindfell"
const SECTION_FROSTGARD := "frostgard"
const SECTION_ISVARDA := "isvarda"
const SECTION_VATNBORG := "vatnborg"
const SECTION_VATNSTEINN := "vatnsteinn"
const SECTION_ASHFELD := "ashfeld"
const SECTION_KOLFJALL := "kolfjall"
const SECTION_SINDRI_APPROACH := "sindri_approach"
const SECTION_GYMIR_APPROACH := "gymir_approach"
const SECTION_SKADI_APPROACH := "skadi_approach"
const SECTION_HRIMFAXI_APPROACH := "hrimfaxi_approach"
const SECTION_ASHSPROUT_APPROACH := "ashsprout_approach"
const SECTION_EIR_APPROACH := "eir_approach"
## Act 3 — the bridge and tower leading to Heimdall
const SECTION_BRIDGE := "bridge"
const SECTION_KINGS_TOWER := "kings_tower"

## Grid ids. The overworld shares one occupancy grid; each dungeon has
## its own so interiors can never collide with the surface or each other.
const GRID_OVERWORLD := "overworld"
const GRID_SPREKKEN := "sprekken"
const GRID_BRANN := "brann"
const GRID_MYRKFEN := "myrkfen"
const GRID_GARNVIK := "garnvik"

## Act 2 dungeon grids — one per boss dungeon
const GRID_SINDRI := "sindri"
const GRID_GYMIR := "gymir"
const GRID_SKADI := "skadi"
const GRID_HRIMFAXI := "hrimfaxi"
const GRID_ASHSPROUT := "ashsprout"
const GRID_EIR := "eir"

const R := "res://world/regions/"

## Static threshold scene between the Eastreach Altar and the randomized
## desert — the constant room the player learns to recognize. Placed via
## the eastreach chain's paired-city mechanism (same machinery that pairs
## Nasus Overlook with Nasus City).
const SUNDUST_GATE_SCENE := R + "sundust_gate.tscn"

const STATIC_SCENES := {
	R + "south_cliff.tscn": {
		"pos": Vector2i(0, 5), "type": TYPE_ARCH, "section": SECTION_START,
		"name": "South Cliff", "connections": [R + "tutorial_1.tscn"],
	},
	R + "tutorial_1.tscn": {
		"pos": Vector2i(0, 4), "type": TYPE_NORMAL, "section": SECTION_START,
		"name": "Cliffside Path", "connections": [R + "south_cliff.tscn", R + "tutorial_2.tscn"],
	},
	R + "tutorial_2.tscn": {
		"pos": Vector2i(0, 3), "type": TYPE_NORMAL, "section": SECTION_START,
		"name": "Old Pilgrim Road", "connections": [R + "tutorial_1.tscn", R + "hollow_glade.tscn", R + "wickbarrow_outskirts.tscn"],
	},
	R + "hollow_glade.tscn": {
		"pos": Vector2i(1, 3), "type": TYPE_CLEARING, "section": SECTION_START,
		"name": "Hollow Glade", "connections": [R + "tutorial_2.tscn"],
	},
	R + "wickbarrow_outskirts.tscn": {
		"pos": Vector2i(0, 2), "type": TYPE_NORMAL, "section": SECTION_START,
		"name": "Wickbarrow Outskirts", "connections": [R + "hollow_glade.tscn", R + "forest_path.tscn"],
	},
	R + "forest_path.tscn": {
		"pos": Vector2i(0, 1), "type": TYPE_NORMAL, "section": SECTION_START,
		"name": "Forest Path", "connections": [R + "wickbarrow_outskirts.tscn", R + "wickbarrow_village.tscn"],
	},
	R + "wickbarrow_village.tscn": {
		"pos": Vector2i(0, 0), "type": TYPE_TOWN, "section": SECTION_START,
		"name": "Wickbarrow", "connections": [
			R + "forest_path.tscn", R + "wickbarrow_approach.tscn",
			R + "wickbarrow_west_gate.tscn", R + "wickbarrow_east_gate.tscn",
		],
	},
	R + "wickbarrow_west_gate.tscn": {
		"pos": Vector2i(-1, 0), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "West Gate", "connections": [R + "wickbarrow_village.tscn", R + "forest_edge.tscn"],
	},
	R + "forest_edge.tscn": {
		"pos": Vector2i(-2, 0), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "Forest Edge", "connections": [R + "wickbarrow_west_gate.tscn", R + "saltmarsh_path.tscn"],
	},
	R + "saltmarsh_path.tscn": {
		"pos": Vector2i(-3, 0), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "Saltmarsh Path", "connections": [R + "forest_edge.tscn", R + "beach_dunes.tscn"],
	},
	R + "beach_dunes.tscn": {
		"pos": Vector2i(-4, 0), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "Beach Dunes", "connections": [R + "saltmarsh_path.tscn", R + "tide_flats.tscn"],
	},
	R + "tide_flats.tscn": {
		"pos": Vector2i(-5, 0), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "Tide Flats", "connections": [R + "beach_dunes.tscn", R + "wreck_shoals.tscn"],
	},
	R + "wreck_shoals.tscn": {
		"pos": Vector2i(-6, 0), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "Wreck Shoals", "connections": [R + "tide_flats.tscn", R + "storsprunga_town.tscn"],
	},
	R + "storsprunga_town.tscn": {
		"pos": Vector2i(-7, 0), "type": TYPE_TOWN, "section": SECTION_STORSPRUNGA,
		"name": "Storsprunga", "connections": [
			R + "wreck_shoals.tscn", R + "skerry_strand.tscn",
		],
	},
	R + "skerry_strand.tscn": {
		"pos": Vector2i(-7, 1), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "Skerry Strand", "connections": [
			R + "storsprunga_town.tscn", R + "frostwrack_tangle.tscn",
		],
	},
	R + "frostwrack_tangle.tscn": {
		"pos": Vector2i(-7, 2), "type": TYPE_NORMAL, "section": SECTION_STORSPRUNGA,
		"name": "Frostwrack Tangle", "connections": [
			R + "skerry_strand.tscn", R + "dungeon_entrance_garnvik.tscn",
		],
	},
	R + "dungeon_entrance_garnvik.tscn": {
		"pos": Vector2i(-7, 3), "type": TYPE_DUNGEON_ENTRANCE, "section": SECTION_STORSPRUNGA,
		"name": "Garnvik Mouth", "connections": [R + "frostwrack_tangle.tscn"],
	},
	R + "wickbarrow_approach.tscn": {
		"pos": Vector2i(0, -1), "type": TYPE_NORMAL, "section": SECTION_NASUS,
		"name": "Wickbarrow Approach", "connections": [R + "wickbarrow_village.tscn"],
	},
	R + "wickbarrow_east_gate.tscn": {
		"pos": Vector2i(1, 0), "type": TYPE_NORMAL, "section": SECTION_EAST,
		"name": "East Gate", "connections": [R + "wickbarrow_village.tscn"],
	},
}

const SECTION_REVEAL_FLAGS := {
	SECTION_STORSPRUNGA: "map_revealed_wickbarrow",
	SECTION_NASUS: "map_revealed_wickbarrow",
	SECTION_NORTH_CHAIN: "map_revealed_wickbarrow",
	SECTION_EAST: "map_revealed_wickbarrow",
	SECTION_EAST_CHAIN: "map_revealed_wickbarrow",
	SECTION_SPREKKEN: "map_revealed_sprekken",
	SECTION_BRANN: "map_revealed_brann",
	SECTION_COAST: "map_revealed_storsprunga",
	SECTION_WESTMOOR: "map_revealed_nasus",
	SECTION_EASTREACH: "map_revealed_nasus",
	SECTION_SPREKKEN_APPROACH: "map_revealed_wickbarrow_altar",
	SECTION_MYRKFEN_APPROACH: "map_revealed_eastreach_altar",
	SECTION_BRANN_APPROACH: "map_revealed_hrimbjarg_altar",
	SECTION_MYRKFEN: "map_revealed_myrkfen",
	SECTION_GARNVIK: "map_revealed_garnvik",
	## Sundust shares the eastreach-altar reveal: both paths spawn from
	## the altar, so reaching it reveals both at once — the "two new
	## paths open up" moment.
	SECTION_SUNDUST: "map_revealed_eastreach_altar",
	## Deep Desert stays hidden until the Sundust Altar is reached —
	## it exists past the broodmother-gated spine and the map shouldn't
	## spoil it early.
	SECTION_DEEP_DESERT: "map_revealed_sundust_altar",
	## Hollowmere reveals on reaching the Westmoor Altar (its source).
	SECTION_HOLLOWMERE: "map_revealed_westmoor_altar",
	## Storsprunga altar + the coast→westmoor connector reveal on
	## reaching Storsprunga itself: the corridor is part of the same
	## revealed region — you should see "this goes somewhere" the moment
	## you arrive in town, not after a 10-room trek.
	SECTION_STORSPRUNGA_ALTAR: "map_revealed_storsprunga",
	## Act 2 mountain chains gate on reaching Hollowmere so the map
	## doesn't spoil that the village has three mountain spurs.
	SECTION_HINDARFJALL: "map_revealed_hollowmere",
	SECTION_HRIMBJARG: "map_revealed_hollowmere",
	SECTION_THURSDAL: "map_revealed_hollowmere",
	## Act 2 sections: each path/approach reveals when reaching its source
	SECTION_STRANDVIK: "map_revealed_storsprunga_altar",
	SECTION_SINDRI_APPROACH: "map_revealed_strandvik_altar",
	SECTION_DRIFTWORKS: "map_revealed_strandvik_altar",
	SECTION_BARRHOLT: "map_revealed_driftworks",
	SECTION_GYMIR_APPROACH: "map_revealed_barrholt_altar",
	SECTION_KALDRHOLT: "map_revealed_barrholt_altar",
	SECTION_VINDFELL: "map_revealed_kaldrholt",
	SECTION_SKADI_APPROACH: "map_revealed_vindfell_altar",
	SECTION_FROSTGARD: "map_revealed_hindarfjall_altar",
	SECTION_ISVARDA: "map_revealed_frostgard",
	SECTION_HRIMFAXI_APPROACH: "map_revealed_isvarda_altar",
	SECTION_VATNBORG: "map_revealed_thursdal_altar",
	SECTION_VATNSTEINN: "map_revealed_vatnborg",
	SECTION_ASHSPROUT_APPROACH: "map_revealed_vatnsteinn_altar",
	SECTION_ASHFELD: "map_revealed_hrimbjarg_altar",
	SECTION_KOLFJALL: "map_revealed_ashfeld",
	SECTION_EIR_APPROACH: "map_revealed_kolfjall_altar",
	SECTION_BRIDGE: "map_revealed_all_altars",
	SECTION_KINGS_TOWER: "map_revealed_all_altars",
}

const TOWN_REVEAL_TRIGGERS := {
	R + "wickbarrow_village.tscn": "map_revealed_wickbarrow",
	R + "dungeon_entrance_sprekken.tscn": "map_revealed_sprekken",
	R + "dungeon_entrance_brann.tscn": "map_revealed_brann",
	R + "dungeon_entrance_myrkfen.tscn": "map_revealed_myrkfen",
	R + "dungeon_entrance_garnvik.tscn": "map_revealed_garnvik",
	R + "storsprunga_town.tscn": "map_revealed_storsprunga",
	R + "nasus_city.tscn": "map_revealed_nasus",
	R + "eastreach_altar.tscn": "map_revealed_eastreach_altar",
	R + "sundust_altar.tscn": "map_revealed_sundust_altar",
	R + "westmoor_altar.tscn": "map_revealed_westmoor_altar",
	R + "hollowmere_village.tscn": "map_revealed_hollowmere",
	R + "wickbarrow_altar.tscn": "map_revealed_wickbarrow_altar",
	R + "hrimbjarg_altar.tscn": "map_revealed_hrimbjarg_altar",
	R + "hindarfjall_altar.tscn": "map_revealed_hindarfjall_altar",
	R + "thursdal_altar.tscn": "map_revealed_thursdal_altar",
	R + "storsprunga_altar.tscn": "map_revealed_storsprunga_altar",
	R + "strandvik_altar.tscn": "map_revealed_strandvik_altar",
	R + "driftworks_town.tscn": "map_revealed_driftworks",
	R + "barrholt_altar.tscn": "map_revealed_barrholt_altar",
	R + "kaldrholt_town.tscn": "map_revealed_kaldrholt",
	R + "vindfell_altar.tscn": "map_revealed_vindfell_altar",
	R + "frostgard_town.tscn": "map_revealed_frostgard",
	R + "isvarda_altar.tscn": "map_revealed_isvarda_altar",
	R + "vatnborg_town.tscn": "map_revealed_vatnborg",
	R + "vatnsteinn_altar.tscn": "map_revealed_vatnsteinn_altar",
	R + "ashfeld_town.tscn": "map_revealed_ashfeld",
	R + "kolfjall_altar.tscn": "map_revealed_kolfjall_altar",
}

# ============================================================================
# POOL DEFINITIONS
# One entry per scene-pool directory. `prefix` is the base name — the
# scanner derives "<prefix>_buffer_", "<prefix>_cross_", and
# "<prefix>_clearing_" from it. Pools may be shared by multiple chains
# (coast is used by both the coast chain and the coast_to_west connector);
# per-run usage tracking guarantees no scene file lands in two chains.
# ============================================================================

const POOL_DEFS := {
	"north": {"dir": "res://world/regions/north_path", "prefix": "north_forest"},
	"east": {"dir": "res://world/regions/east_path", "prefix": "east_forest"},
	"sprekken": {"dir": "res://world/regions/sprekken", "prefix": "sprekken"},
	"brann": {"dir": "res://world/regions/brann", "prefix": "brann"},
	"coast": {"dir": "res://world/regions/coast_path", "prefix": "coast"},
	"westmoor": {"dir": "res://world/regions/westmoor_path", "prefix": "west"},
	"eastreach": {"dir": "res://world/regions/eastreach_path", "prefix": "eastreach"},
	"sprekken_approach": {"dir": "res://world/regions/sprekken_approach", "prefix": "sprekken_approach"},
	"sundust": {"dir": "res://world/regions/sundust_path", "prefix": "sundust"},
	"deep_desert": {"dir": "res://world/regions/deep_desert_path", "prefix": "deep_desert"},
	"hollowmere": {"dir": "res://world/regions/hollowmere_path", "prefix": "hollowmere"},
	"hindarfjall": {"dir": "res://world/regions/hindarfjall_path", "prefix": "hindarfjall"},
	"hrimbjarg": {"dir": "res://world/regions/hrimbjarg_path", "prefix": "hrimbjarg"},
	"thursdal": {"dir": "res://world/regions/thursdal_path", "prefix": "thursdal"},
	"myrkfen": {"dir": "res://world/regions/myrkfen", "prefix": "myrkfen"},
	"garnvik": {"dir": "res://world/regions/garnvik", "prefix": "garnvik"},
	## Act 2 pools — overworld paths and dungeon interiors
	"strandvik": {"dir": "res://world/regions/strandvik_path", "prefix": "strandvik"},
	"driftworks": {"dir": "res://world/regions/driftworks_path", "prefix": "driftworks"},
	"barrholt": {"dir": "res://world/regions/barrholt_path", "prefix": "barrholt"},
	"kaldrholt": {"dir": "res://world/regions/kaldrholt_path", "prefix": "kaldrholt"},
	"vindfell": {"dir": "res://world/regions/vindfell_path", "prefix": "vindfell"},
	"frostgard": {"dir": "res://world/regions/frostgard_path", "prefix": "frostgard"},
	"isvarda": {"dir": "res://world/regions/isvarda_path", "prefix": "isvarda"},
	"vatnborg": {"dir": "res://world/regions/vatnborg_path", "prefix": "vatnborg"},
	"vatnsteinn": {"dir": "res://world/regions/vatnsteinn_path", "prefix": "vatnsteinn"},
	"ashfeld": {"dir": "res://world/regions/ashfeld_path", "prefix": "ashfeld"},
	"kolfjall": {"dir": "res://world/regions/kolfjall_path", "prefix": "kolfjall"},
	"sindri": {"dir": "res://world/regions/sindri", "prefix": "sindri"},
	"gymir": {"dir": "res://world/regions/gymir", "prefix": "gymir"},
	"skadi": {"dir": "res://world/regions/skadi", "prefix": "skadi"},
	"hrimfaxi": {"dir": "res://world/regions/hrimfaxi", "prefix": "hrimfaxi"},
	"ashsprout": {"dir": "res://world/regions/ashsprout", "prefix": "ashsprout"},
	"eir": {"dir": "res://world/regions/eir", "prefix": "eir"},
}

# ============================================================================
# CHAIN DEFINITIONS — the single source of truth for world layout.
#
# Entries are in GENERATION ORDER. A chain whose anchor_mode is "chain"
# anchors on the RESOLVED endpoint cell of the named upstream chain, so it
# must appear later in this array than its anchor_base. The generation
# loop enforces this with an assert.
#
# Field reference:
#   id                     unique chain id (used by anchor_base / orders)
#   pool                   POOL_DEFS key
#   grid                   GRID_OVERWORLD | GRID_SPREKKEN | GRID_BRANN
#   length                 max buffer slots on the spine
#   start_scene            scene the chain grows out of
#   start_exit_dir         which exit of start_scene feeds the chain
#   end_scene              endpoint scene placed past the last buffer
#   seed                   RNG offset for the chain walk (world_seed + seed)
#   target_seed            RNG offset for the target pick (defaults to seed;
#                          north/east keep their historical +100/+1100)
#   anchor_mode            "absolute" — anchor is a world cell
#                          "chain"    — anchor is offset from anchor_base's
#                                       resolved endpoint cell
#                          "none"     — free random walk (dungeons)
#   anchor_base            chain id (anchor_mode == "chain" only)
#   anchor / scatter       target box: anchor ± scatter
#   perp_axis              axis perpendicular to travel; deviations on it
#                          are penalized in the target pick (see
#                          _pick_target_cell)
#   pre_pick               pick + reserve the target BEFORE any generation
#                          so no other chain walks through it (north/east —
#                          the two absolute-anchor POI chains)
#   chain_axis             "" | "horizontal" | "vertical" spine lock
#   reserved_approach_dirs endpoint exits that must never be rewired by the
#                          end-of-chain override (see _evaluate_candidate)
#   final_forward_dir      forces the last step's direction so the endpoint
#                          lands on a specific face
#   end_at_chain           the endpoint is ANOTHER chain's already-placed
#                          endpoint (coast_to_west → westmoor altar); no
#                          new scene is placed, connections are wired in
#                          the graph pass
#   section                scene_graph section for the chain's rooms
#   end_label              exit label shown on the door into the endpoint
#   endpoint_mode          "poi"     — place endpoint via CHAIN fields below
#                          "connect" — wire to end_at_chain's endpoint
#                          "boss"    — dungeon: entrance node + boss room
#   ep_name/ep_type/ep_section        POI endpoint identity
#   city_path/city_name/city_section/city_type/city_offset
#                          optional paired scene one cell past the endpoint
#                          (Nasus City off the Overlook, Sundust Gate off
#                          the Eastreach Altar). Reserved at generation
#                          time on the RESOLVED endpoint so downstream
#                          chains can find it as a start scene.
#   boss_name/entrance_name           dungeon endpoint identity
#   grid_offset            map-coordinate offset for dungeon grids
# ============================================================================

const CHAIN_DEFS: Array = [
	# NORTH: Wickbarrow → Nasus Overlook (+ Nasus City paired one cell
	# further north). Axis-locked vertical so Nasus is always due north;
	# scatter is parallel-only (see the cardinal-accuracy note on
	# _pick_target_cell). Target pre-picked and reserved before anything
	# generates so no chain can occupy Nasus's cell.
	{
		"id": "north", "pool": "north", "grid": GRID_OVERWORLD,
		"length": 12,
		"start_scene": R + "wickbarrow_approach.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "nasus_overlook.tscn",
		"seed": 0, "target_seed": 100,
		"anchor_mode": "absolute", "anchor": Vector2i(0, -8),
		"scatter": Vector2i(0, 3), "perp_axis": "x",
		"pre_pick": true, "chain_axis": "vertical",
		"section": SECTION_NORTH_CHAIN,
		"end_label": "→  to Nasus Overlook",
		"endpoint_mode": "poi",
		"ep_name": "Nasus Overlook", "ep_type": TYPE_NORMAL, "ep_section": SECTION_NASUS,
		"city_path": R + "nasus_city.tscn", "city_name": "Nasus",
		"city_section": SECTION_NASUS, "city_type": TYPE_TOWN,
		"city_offset": Vector2i(0, -1),
	},
	# WEST: Nasus City → Westmoor Altar. final_forward_dir="west" so the
	# altar is entered on its EAST face, leaving the south face for the
	# coast_to_west connector (final "north") — the two inbound chains
	# rewire different exits and never conflict.
	{
		"id": "west", "pool": "westmoor", "grid": GRID_OVERWORLD,
		"length": 12,
		"start_scene": R + "nasus_city.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "westmoor_altar.tscn",
		"seed": 5000,
		"anchor_mode": "chain", "anchor_base": "north",
		"anchor": Vector2i(-10, -4),
		"scatter": Vector2i(0, 0), "perp_axis": "y",
		"final_forward_dir": "west",
		"section": SECTION_WESTMOOR,
		"end_label": "→  to the Westmoor Altar",
		"endpoint_mode": "poi",
		"ep_name": "Westmoor Altar", "ep_type": TYPE_ALTAR, "ep_section": SECTION_WESTMOOR,
	},
	# HOLLOWMERE: Westmoor Altar → Hollowmere village. NW diagonal (free
	# axis so N and W moves interleave). Anchored on the westmoor chain's
	# RESOLVED endpoint, so a short westmoor still yields a connected moor.
	{
		"id": "hollowmere", "pool": "hollowmere", "grid": GRID_OVERWORLD,
		"length": 18,
		"start_scene": R + "westmoor_altar.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "hollowmere_village.tscn",
		"seed": 10000,
		"anchor_mode": "chain", "anchor_base": "west",
		"anchor": Vector2i(-12, -8),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_HOLLOWMERE,
		"end_label": "→  to Hollowmere",
		# Approach the village heading WEST so the trail's last buffer
		# sits on the village's EAST face. The other three faces are
		# chain starts (N hindarfjall, W hrimbjarg, S thursdal) — an
		# unconstrained approach parks the last buffer south of the
		# village on most seeds, permanently blocking thursdal's first
		# cell AND contesting ExitSouth with thursdal's start override.
		"final_forward_dir": "west",
		"endpoint_mode": "poi",
		"ep_name": "Hollowmere", "ep_type": TYPE_TOWN, "ep_section": SECTION_HOLLOWMERE,
	},
	# Act 2 mountain chains — three corridors out of Hollowmere, each
	# ending at its own altar. All anchor on hollowmere's RESOLVED cell
	# (this is the fix for the orphaned-spur bug: the old code anchored
	# on the intended target, which the village doesn't always reach).
	{
		"id": "hindarfjall", "pool": "hindarfjall", "grid": GRID_OVERWORLD,
		"length": 10,
		"start_scene": R + "hollowmere_village.tscn",
		"start_exit_dir": "north",
		"start_exit_dir_priority": ["north", "east", "south", "west"],
		"end_scene": R + "hindarfjall_altar.tscn",
		"seed": 11000,
		"anchor_mode": "chain", "anchor_base": "hollowmere",
		"anchor": Vector2i(2, -11),
		"scatter": Vector2i(1, 1), "perp_axis": "y",
		"section": SECTION_HINDARFJALL,
		"end_label": "↑  to the Hindarfjall Altar",
		"endpoint_mode": "poi",
		"ep_name": "Hindarfjall Altar", "ep_type": TYPE_ALTAR, "ep_section": SECTION_HINDARFJALL,
	},
	{
		"id": "hrimbjarg", "pool": "hrimbjarg", "grid": GRID_OVERWORLD,
		"length": 10,
		"start_scene": R + "hollowmere_village.tscn",
		"start_exit_dir": "west",
		"start_exit_dir_priority": ["west", "south", "east", "north"],
		"end_scene": R + "hrimbjarg_altar.tscn",
		"seed": 12000,
		"anchor_mode": "chain", "anchor_base": "hollowmere",
		"anchor": Vector2i(-2, -10),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_HRIMBJARG,
		"end_label": "←  to the Hrimbjarg Altar",
		"endpoint_mode": "poi",
		"ep_name": "Hrimbjarg Altar", "ep_type": TYPE_ALTAR, "ep_section": SECTION_HRIMBJARG,
	},
	# Thursdal leaves the SOUTH face and wraps NW — longer (12) because
	# the south-then-northwest route is geometrically longer.
	{
		"id": "thursdal", "pool": "thursdal", "grid": GRID_OVERWORLD,
		"length": 12,
		"start_scene": R + "hollowmere_village.tscn",
		"start_exit_dir": "south",
		"start_exit_dir_priority": ["south", "east", "west", "north"],
		"end_scene": R + "thursdal_altar.tscn",
		"seed": 13000,
		"anchor_mode": "chain", "anchor_base": "hollowmere",
		"anchor": Vector2i(-9, -8),
		"scatter": Vector2i(2, 1), "perp_axis": "x",
		"section": SECTION_THURSDAL,
		"end_label": "↓  to the Thursdal Altar",
		"endpoint_mode": "poi",
		"ep_name": "Thursdal Altar", "ep_type": TYPE_ALTAR, "ep_section": SECTION_THURSDAL,
	},
	{
		"id": "brann_approach", "pool": "hrimbjarg", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "hrimbjarg_altar.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "dungeon_entrance_brann.tscn",
		"seed": 16000,
		"anchor_mode": "chain", "anchor_base": "hrimbjarg",
		"anchor": Vector2i(-3, 0),
		"scatter": Vector2i(0, 0), "perp_axis": "y",
		"chain_axis": "horizontal",
		"section": SECTION_BRANN_APPROACH,
		"end_label": "←  to the Brann Throat",
		"endpoint_mode": "poi",
		"ep_name": "Brann Throat", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_BRANN_APPROACH,
	},
	# EASTREACH: Nasus City → Eastreach Altar (+ Sundust Gate paired one
	# cell east). reserved_approach_dirs=["south","east"] forbids the
	# chain from ever ending with a step that would rewire the altar's
	# south exit (sprekken_approach's start) or east exit (the gate's
	# static wiring). final "south" → chain enters the altar's NORTH face.
	{
		"id": "eastreach", "pool": "eastreach", "grid": GRID_OVERWORLD,
		"length": 12,
		"start_scene": R + "nasus_city.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "eastreach_altar.tscn",
		"seed": 6000,
		"anchor_mode": "chain", "anchor_base": "north",
		"anchor": Vector2i(10, 3),
		"scatter": Vector2i(0, 0), "perp_axis": "y",
		"reserved_approach_dirs": ["south", "east"],
		"final_forward_dir": "south",
		"section": SECTION_EASTREACH,
		"end_label": "→  to the Eastreach Altar",
		"endpoint_mode": "poi",
		"ep_name": "Eastreach Altar", "ep_type": TYPE_ALTAR, "ep_section": SECTION_EASTREACH,
		"city_path": SUNDUST_GATE_SCENE, "city_name": "Sundust Gate",
		"city_section": SECTION_SUNDUST, "city_type": TYPE_NORMAL,
		"city_offset": Vector2i(1, 0),
	},
	{
		"id": "myrkfen_approach", "pool": "sprekken_approach", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "eastreach_altar.tscn",
		"start_exit_dir": "south",
		"end_scene": R + "dungeon_entrance_myrkfen.tscn",
		"seed": 15000,
		"anchor_mode": "chain", "anchor_base": "eastreach",
		"anchor": Vector2i(0, 3),
		"scatter": Vector2i(0, 0), "perp_axis": "x",
		"chain_axis": "vertical",
		"section": SECTION_MYRKFEN_APPROACH,
		"end_label": "→  to the Myrkfen Mouth",
		"endpoint_mode": "poi",
		"ep_name": "Myrkfen Mouth", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_MYRKFEN_APPROACH,
	},
	# SUNDUST: 25-buffer NE expedition, Sundust Gate → Sundust Altar.
	# Anchored on the eastreach ALTAR's resolved cell (not the gate) so
	# the target stays put regardless of where the gate lands. final
	# "east" leaves the altar's east face free for deep_desert to start.
	{
		"id": "sundust", "pool": "sundust", "grid": GRID_OVERWORLD,
		"length": 25,
		"start_scene": SUNDUST_GATE_SCENE,
		"start_exit_dir": "east",
		"end_scene": R + "sundust_altar.tscn",
		"seed": 8000,
		"anchor_mode": "chain", "anchor_base": "eastreach",
		"anchor": Vector2i(12, -12),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"final_forward_dir": "east",
		"section": SECTION_SUNDUST,
		"end_label": "→  to the Sundust Altar",
		"endpoint_mode": "poi",
		"ep_name": "Sundust Altar", "ep_type": TYPE_ALTAR, "ep_section": SECTION_SUNDUST,
	},
	# DEEP DESERT: 20-buffer NE corridor, Sundust Altar → the deep-desert
	# dungeon entrance. Anchored on sundust's RESOLVED endpoint (fix: the
	# old code anchored on sundust's intended target, which a short
	# sundust chain never reaches — same orphaning bug as the act-2 spurs).
	{
		"id": "deep_desert", "pool": "deep_desert", "grid": GRID_OVERWORLD,
		"length": 20,
		"start_scene": R + "sundust_altar.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "dungeon_entrance_deep_desert.tscn",
		"seed": 9000,
		"anchor_mode": "chain", "anchor_base": "sundust",
		"anchor": Vector2i(10, -10),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_DEEP_DESERT,
		"end_label": "→  to the Deep Desert Dungeon",
		"endpoint_mode": "poi",
		"ep_name": "Deep Desert Dungeon", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_DEEP_DESERT,
	},
	# EAST: Wickbarrow East Gate → Wickbarrow Altar. Axis-locked
	# horizontal; target pre-picked and reserved before any generation
	# (same protection as north). final "east" → altar entered on its
	# WEST face; the other three faces are scrubbed in the scene.
	{
		"id": "east", "pool": "east", "grid": GRID_OVERWORLD,
		"length": 12,
		"start_scene": R + "wickbarrow_east_gate.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "wickbarrow_altar.tscn",
		"seed": 1000, "target_seed": 1100,
		"anchor_mode": "absolute", "anchor": Vector2i(8, 0),
		"scatter": Vector2i(3, 0), "perp_axis": "y",
		"pre_pick": true, "chain_axis": "horizontal",
		"final_forward_dir": "east",
		"section": SECTION_EAST_CHAIN,
		"end_label": "→  to the Wickbarrow Altar",
		"endpoint_mode": "poi",
		"ep_name": "Wickbarrow Altar", "ep_type": TYPE_ALTAR, "ep_section": SECTION_EAST_CHAIN,
	},
	{
		"id": "sprekken_approach", "pool": "sprekken_approach", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "wickbarrow_altar.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "dungeon_entrance_sprekken.tscn",
		"seed": 7000,
		"anchor_mode": "chain", "anchor_base": "east",
		"anchor": Vector2i(3, 0),
		"scatter": Vector2i(0, 0), "perp_axis": "y",
		"chain_axis": "horizontal",
		"section": SECTION_SPREKKEN_APPROACH,
		"end_label": "→  to the Sprekken Entrance",
		"endpoint_mode": "poi",
		"ep_name": "Sprekken Entrance", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_SPREKKEN_APPROACH,
	},
	# SPREKKEN DEPTHS: dungeon interior on its own grid. Free random walk
	# (no target); the boss room lands one step past the last buffer.
	{
		"id": "sprekken_depths", "pool": "sprekken", "grid": GRID_SPREKKEN,
		"length": 12,
		"start_scene": R + "dungeon_entrance_sprekken.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "sprekken/sprekken_boss_room.tscn",
		"seed": 2000,
		"anchor_mode": "none",
		"section": SECTION_SPREKKEN,
		"end_label": "→  to the Throne Room",
		"endpoint_mode": "boss",
		"boss_name": "Sprekken Throne", "entrance_name": "Sprekken Entrance",
		"grid_offset": Vector2i(100, 100),
	},
	# BRANN DEPTHS: second dungeon, shorter (6) — reached after Sprekken
	# in the natural play order, so the build-up is shorter.
	{
		"id": "brann_depths", "pool": "brann", "grid": GRID_BRANN,
		"length": 6,
		"start_scene": R + "dungeon_entrance_brann.tscn",
		"start_exit_dir": "south",
		"end_scene": R + "brann/brann_boss_room.tscn",
		"seed": 4000,
		"anchor_mode": "none",
		"section": SECTION_BRANN,
		"end_label": "→  to the Pyre Hall",
		"endpoint_mode": "boss",
		"boss_name": "Pyre Hall", "entrance_name": "Brann Throat",
		"grid_offset": Vector2i(200, 200),
	},
	{
		"id": "myrkfen_depths", "pool": "myrkfen", "grid": GRID_MYRKFEN,
		"length": 8,
		"start_scene": R + "dungeon_entrance_myrkfen.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "myrkfen/myrkfen_boss_room.tscn",
		"seed": 17000,
		"anchor_mode": "none",
		"section": SECTION_MYRKFEN,
		"end_label": "→  to the Gallows Grove",
		"endpoint_mode": "boss",
		"boss_name": "Gallows Grove", "entrance_name": "Myrkfen Mouth",
		"grid_offset": Vector2i(300, 300),
	},
	{
		"id": "garnvik_depths", "pool": "garnvik", "grid": GRID_GARNVIK,
		"length": 9,
		"start_scene": R + "dungeon_entrance_garnvik.tscn",
		"start_exit_dir": "south",
		"end_scene": R + "garnvik/garnvik_boss_room.tscn",
		"seed": 18000,
		"anchor_mode": "none",
		"section": SECTION_GARNVIK,
		"end_label": "→  to the Beached Wreck",
		"endpoint_mode": "boss",
		"boss_name": "The Beached Wreck", "entrance_name": "Garnvik Mouth",
		"grid_offset": Vector2i(400, 400),
	},
	# COAST: Storsprunga → Storsprunga Altar. Storsprunga's static cell
	# is (-7, 0); anchor (-10, -7) = that cell + the historical (-3, -7)
	# offset. Generated late (after the whole east half) exactly like the
	# old ordering, so its target pick sees the same occupancy.
	{
		"id": "coast", "pool": "coast", "grid": GRID_OVERWORLD,
		"length": 10,
		"start_scene": R + "storsprunga_town.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "storsprunga_altar.tscn",
		"seed": 3000,
		"anchor_mode": "absolute", "anchor": Vector2i(-10, -7),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_COAST,
		"end_label": "→  to the Storsprunga Altar",
		"endpoint_mode": "poi",
		"ep_name": "Storsprunga Altar", "ep_type": TYPE_ALTAR,
		"ep_section": SECTION_STORSPRUNGA_ALTAR,
	},
	# COAST → WESTMOOR connector: Storsprunga Altar north to the EXISTING
	# Westmoor Altar. end_at_chain="west" targets the westmoor chain's
	# resolved endpoint; no new scene is placed — the graph pass wires
	# connections instead. Reuses the coast pool (same biome); per-pool
	# usage tracking keeps its rooms disjoint from the coast chain's.
	# final "north" → enters the altar's SOUTH face (west chain owns the
	# east face).
	#
	# Seed 14000 — was 11000, which collided with hindarfjall and made
	# the two chains draw from identical RNG streams. 14000 is the next
	# free offset after thursdal's 13000.
	{
		"id": "coast_to_west", "pool": "coast", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "storsprunga_altar.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "westmoor_altar.tscn",
		"seed": 14000,
		"anchor_mode": "chain", "anchor_base": "west",
		"anchor": Vector2i.ZERO,
		"scatter": Vector2i(0, 0), "perp_axis": "x",
		"end_at_chain": "west",
		"final_forward_dir": "north",
		"section": SECTION_STORSPRUNGA_ALTAR,
		"end_label": "→  to the Westmoor Altar",
		"endpoint_mode": "connect",
	},
	# ================================================================
	# ACT 2: STORSPRUNGA ALTAR → STRANDVIK → SINDRI / DRIFTWORKS
	# ================================================================
	# Strandvik path: Storsprunga Altar → Strandvik Altar
	{
		"id": "strandvik_path", "pool": "strandvik", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "storsprunga_altar.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "strandvik_altar.tscn",
		"seed": 20000,
		"anchor_mode": "chain", "anchor_base": "coast",
		"anchor": Vector2i(-6, -2),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"final_forward_dir": "west",
		"section": SECTION_STRANDVIK,
		"end_label": "->  to the Strandvik Altar",
		"endpoint_mode": "poi",
		"ep_name": "Strandvik Altar", "ep_type": TYPE_ALTAR,
		"ep_section": SECTION_STRANDVIK,
	},
	# Sindri approach: Strandvik Altar south → dungeon entrance
	{
		"id": "sindri_approach", "pool": "strandvik", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "strandvik_altar.tscn",
		"start_exit_dir": "south",
		"end_scene": R + "dungeon_entrance_sindri.tscn",
		"seed": 21000,
		"anchor_mode": "chain", "anchor_base": "strandvik_path",
		"anchor": Vector2i(0, 3),
		"scatter": Vector2i(0, 0), "perp_axis": "x",
		"chain_axis": "vertical",
		"section": SECTION_SINDRI_APPROACH,
		"end_label": "->  to Sindri's Forge",
		"endpoint_mode": "poi",
		"ep_name": "Sindri's Forge", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_SINDRI_APPROACH,
	},
	# Driftworks path: Strandvik Altar north → Driftworks Town
	{
		"id": "driftworks_path", "pool": "driftworks", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "strandvik_altar.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "driftworks_town.tscn",
		"seed": 22000,
		"anchor_mode": "chain", "anchor_base": "strandvik_path",
		"anchor": Vector2i(-4, -6),
		"scatter": Vector2i(1, 1), "perp_axis": "y",
		"section": SECTION_DRIFTWORKS,
		"end_label": "->  to Driftworks",
		"endpoint_mode": "poi",
		"ep_name": "Driftworks", "ep_type": TYPE_TOWN,
		"ep_section": SECTION_DRIFTWORKS,
	},
	# ================================================================
	# ACT 2: DRIFTWORKS → BARRHOLT → GYMIR / KALDRHOLT
	# ================================================================
	# Barrholt path: Driftworks Town → Barrholt Altar
	{
		"id": "barrholt_path", "pool": "barrholt", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "driftworks_town.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "barrholt_altar.tscn",
		"seed": 23000,
		"anchor_mode": "chain", "anchor_base": "driftworks_path",
		"anchor": Vector2i(2, -8),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_BARRHOLT,
		"end_label": "->  to the Barrholt Altar",
		"endpoint_mode": "poi",
		"ep_name": "Barrholt Altar", "ep_type": TYPE_ALTAR,
		"ep_section": SECTION_BARRHOLT,
	},
	# Gymir approach: Barrholt Altar east → dungeon entrance
	{
		"id": "gymir_approach", "pool": "barrholt", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "barrholt_altar.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "dungeon_entrance_gymir.tscn",
		"seed": 24000,
		"anchor_mode": "chain", "anchor_base": "barrholt_path",
		"anchor": Vector2i(3, 0),
		"scatter": Vector2i(0, 0), "perp_axis": "y",
		"chain_axis": "horizontal",
		"section": SECTION_GYMIR_APPROACH,
		"end_label": "->  to Gymir's Peak",
		"endpoint_mode": "poi",
		"ep_name": "Gymir's Peak", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_GYMIR_APPROACH,
	},
	# Kaldrholt path: Barrholt Altar west → Kaldrholt Town
	{
		"id": "kaldrholt_path", "pool": "kaldrholt", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "barrholt_altar.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "kaldrholt_town.tscn",
		"seed": 25000,
		"anchor_mode": "chain", "anchor_base": "barrholt_path",
		"anchor": Vector2i(-6, -4),
		"scatter": Vector2i(1, 1), "perp_axis": "y",
		"section": SECTION_KALDRHOLT,
		"end_label": "->  to Kaldrholt",
		"endpoint_mode": "poi",
		"ep_name": "Kaldrholt", "ep_type": TYPE_TOWN,
		"ep_section": SECTION_KALDRHOLT,
	},
	# ================================================================
	# ACT 2: KALDRHOLT → VINDFELL → SKADI
	# ================================================================
	# Vindfell path: Kaldrholt Town → Vindfell Altar
	{
		"id": "vindfell_path", "pool": "vindfell", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "kaldrholt_town.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "vindfell_altar.tscn",
		"seed": 26000,
		"anchor_mode": "chain", "anchor_base": "kaldrholt_path",
		"anchor": Vector2i(0, -8),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_VINDFELL,
		"end_label": "->  to the Vindfell Altar",
		"endpoint_mode": "poi",
		"ep_name": "Vindfell Altar", "ep_type": TYPE_ALTAR,
		"ep_section": SECTION_VINDFELL,
	},
	# Skadi approach: Vindfell Altar east → dungeon entrance
	{
		"id": "skadi_approach", "pool": "vindfell", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "vindfell_altar.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "dungeon_entrance_skadi.tscn",
		"seed": 27000,
		"anchor_mode": "chain", "anchor_base": "vindfell_path",
		"anchor": Vector2i(3, 0),
		"scatter": Vector2i(0, 0), "perp_axis": "y",
		"chain_axis": "horizontal",
		"section": SECTION_SKADI_APPROACH,
		"end_label": "->  to Skadi's Hunt",
		"endpoint_mode": "poi",
		"ep_name": "Skadi's Hunt", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_SKADI_APPROACH,
	},
	# ================================================================
	# ACT 2: HINDARFJALL ALTAR → FROSTGARD → ISVARDA → HRIMFAXI
	# ================================================================
	# Frostgard path: Hindarfjall Altar → Frostgard Town
	{
		"id": "frostgard_path", "pool": "frostgard", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "hindarfjall_altar.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "frostgard_town.tscn",
		"seed": 28000,
		"anchor_mode": "chain", "anchor_base": "hindarfjall",
		"anchor": Vector2i(0, -8),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_FROSTGARD,
		"end_label": "->  to Frostgard",
		"endpoint_mode": "poi",
		"ep_name": "Frostgard", "ep_type": TYPE_TOWN,
		"ep_section": SECTION_FROSTGARD,
	},
	# Isvarda path: Frostgard Town → Isvarda Altar
	{
		"id": "isvarda_path", "pool": "isvarda", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "frostgard_town.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "isvarda_altar.tscn",
		"seed": 29000,
		"anchor_mode": "chain", "anchor_base": "frostgard_path",
		"anchor": Vector2i(-8, 0),
		"scatter": Vector2i(1, 1), "perp_axis": "y",
		"final_forward_dir": "west",
		"section": SECTION_ISVARDA,
		"end_label": "->  to the Isvarda Altar",
		"endpoint_mode": "poi",
		"ep_name": "Isvarda Altar", "ep_type": TYPE_ALTAR,
		"ep_section": SECTION_ISVARDA,
	},
	# Hrimfaxi approach: Isvarda Altar south → dungeon entrance
	{
		"id": "hrimfaxi_approach", "pool": "isvarda", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "isvarda_altar.tscn",
		"start_exit_dir": "south",
		"end_scene": R + "dungeon_entrance_hrimfaxi.tscn",
		"seed": 30000,
		"anchor_mode": "chain", "anchor_base": "isvarda_path",
		"anchor": Vector2i(0, 3),
		"scatter": Vector2i(0, 0), "perp_axis": "x",
		"chain_axis": "vertical",
		"section": SECTION_HRIMFAXI_APPROACH,
		"end_label": "->  to the Frost Hollow",
		"endpoint_mode": "poi",
		"ep_name": "Frost Hollow", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_HRIMFAXI_APPROACH,
	},
	# ================================================================
	# ACT 2: THURSDAL ALTAR → VATNBORG → VATNSTEINN → ASHSPROUT
	# ================================================================
	# Vatnborg path: Thursdal Altar → Vatnborg Town
	{
		"id": "vatnborg_path", "pool": "vatnborg", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "thursdal_altar.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "vatnborg_town.tscn",
		"seed": 31000,
		"anchor_mode": "chain", "anchor_base": "thursdal",
		"anchor": Vector2i(-8, 0),
		"scatter": Vector2i(1, 1), "perp_axis": "y",
		"section": SECTION_VATNBORG,
		"end_label": "->  to Vatnborg",
		"endpoint_mode": "poi",
		"ep_name": "Vatnborg", "ep_type": TYPE_TOWN,
		"ep_section": SECTION_VATNBORG,
	},
	# Vatnsteinn path: Vatnborg Town → Vatnsteinn Altar
	{
		"id": "vatnsteinn_path", "pool": "vatnsteinn", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "vatnborg_town.tscn",
		"start_exit_dir": "south",
		"end_scene": R + "vatnsteinn_altar.tscn",
		"seed": 32000,
		"anchor_mode": "chain", "anchor_base": "vatnborg_path",
		"anchor": Vector2i(0, 8),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_VATNSTEINN,
		"end_label": "->  to the Vatnsteinn Altar",
		"endpoint_mode": "poi",
		"ep_name": "Vatnsteinn Altar", "ep_type": TYPE_ALTAR,
		"ep_section": SECTION_VATNSTEINN,
	},
	# Ashsprout approach: Vatnsteinn Altar east → dungeon entrance
	{
		"id": "ashsprout_approach", "pool": "vatnsteinn", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "vatnsteinn_altar.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "dungeon_entrance_ashsprout.tscn",
		"seed": 33000,
		"anchor_mode": "chain", "anchor_base": "vatnsteinn_path",
		"anchor": Vector2i(3, 0),
		"scatter": Vector2i(0, 0), "perp_axis": "y",
		"chain_axis": "horizontal",
		"section": SECTION_ASHSPROUT_APPROACH,
		"end_label": "->  to the Rotwood",
		"endpoint_mode": "poi",
		"ep_name": "The Rotwood", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_ASHSPROUT_APPROACH,
	},
	# ================================================================
	# ACT 2: HRIMBJARG ALTAR → ASHFELD → KOLFJALL → EIR
	# ================================================================
	# Ashfeld path: Hrimbjarg Altar → Ashfeld Town
	{
		"id": "ashfeld_path", "pool": "ashfeld", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "hrimbjarg_altar.tscn",
		"start_exit_dir": "north",
		"end_scene": R + "ashfeld_town.tscn",
		"seed": 34000,
		"anchor_mode": "chain", "anchor_base": "hrimbjarg",
		"anchor": Vector2i(0, -8),
		"scatter": Vector2i(1, 1), "perp_axis": "x",
		"section": SECTION_ASHFELD,
		"end_label": "->  to Ashfeld",
		"endpoint_mode": "poi",
		"ep_name": "Ashfeld", "ep_type": TYPE_TOWN,
		"ep_section": SECTION_ASHFELD,
	},
	# Kolfjall path: Ashfeld Town → Kolfjall Altar
	{
		"id": "kolfjall_path", "pool": "kolfjall", "grid": GRID_OVERWORLD,
		"length": 8,
		"start_scene": R + "ashfeld_town.tscn",
		"start_exit_dir": "west",
		"end_scene": R + "kolfjall_altar.tscn",
		"seed": 35000,
		"anchor_mode": "chain", "anchor_base": "ashfeld_path",
		"anchor": Vector2i(-8, 0),
		"scatter": Vector2i(1, 1), "perp_axis": "y",
		"final_forward_dir": "west",
		"section": SECTION_KOLFJALL,
		"end_label": "->  to the Kolfjall Altar",
		"endpoint_mode": "poi",
		"ep_name": "Kolfjall Altar", "ep_type": TYPE_ALTAR,
		"ep_section": SECTION_KOLFJALL,
	},
	# Eir approach: Kolfjall Altar south → dungeon entrance
	{
		"id": "eir_approach", "pool": "kolfjall", "grid": GRID_OVERWORLD,
		"length": 3,
		"start_scene": R + "kolfjall_altar.tscn",
		"start_exit_dir": "south",
		"end_scene": R + "dungeon_entrance_eir.tscn",
		"seed": 36000,
		"anchor_mode": "chain", "anchor_base": "kolfjall_path",
		"anchor": Vector2i(0, 3),
		"scatter": Vector2i(0, 0), "perp_axis": "x",
		"chain_axis": "vertical",
		"section": SECTION_EIR_APPROACH,
		"end_label": "->  to the Valkyrie's Perch",
		"endpoint_mode": "poi",
		"ep_name": "Valkyrie's Perch", "ep_type": TYPE_DUNGEON_ENTRANCE,
		"ep_section": SECTION_EIR_APPROACH,
	},
	# ================================================================
	# ACT 2 DUNGEON INTERIORS — one per boss
	# ================================================================
	{
		"id": "sindri_depths", "pool": "sindri", "grid": GRID_SINDRI,
		"length": 8,
		"start_scene": R + "dungeon_entrance_sindri.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "sindri/sindri_boss_room.tscn",
		"seed": 37000,
		"anchor_mode": "none",
		"section": SECTION_SINDRI_APPROACH,
		"end_label": "->  to the Apprentice's Forge",
		"endpoint_mode": "boss",
		"boss_name": "Apprentice's Forge", "entrance_name": "Sindri's Forge",
		"grid_offset": Vector2i(500, 500),
	},
	{
		"id": "gymir_depths", "pool": "gymir", "grid": GRID_GYMIR,
		"length": 8,
		"start_scene": R + "dungeon_entrance_gymir.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "gymir/gymir_boss_room.tscn",
		"seed": 38000,
		"anchor_mode": "none",
		"section": SECTION_GYMIR_APPROACH,
		"end_label": "->  to the Giant's Hall",
		"endpoint_mode": "boss",
		"boss_name": "Giant's Hall", "entrance_name": "Gymir's Peak",
		"grid_offset": Vector2i(600, 600),
	},
	{
		"id": "skadi_depths", "pool": "skadi", "grid": GRID_SKADI,
		"length": 8,
		"start_scene": R + "dungeon_entrance_skadi.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "skadi/skadi_boss_room.tscn",
		"seed": 39000,
		"anchor_mode": "none",
		"section": SECTION_SKADI_APPROACH,
		"end_label": "->  to the Huntress's Den",
		"endpoint_mode": "boss",
		"boss_name": "Huntress's Den", "entrance_name": "Skadi's Hunt",
		"grid_offset": Vector2i(700, 700),
	},
	{
		"id": "hrimfaxi_depths", "pool": "hrimfaxi", "grid": GRID_HRIMFAXI,
		"length": 8,
		"start_scene": R + "dungeon_entrance_hrimfaxi.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "hrimfaxi/hrimfaxi_boss_room.tscn",
		"seed": 40000,
		"anchor_mode": "none",
		"section": SECTION_HRIMFAXI_APPROACH,
		"end_label": "->  to the Frost Den",
		"endpoint_mode": "boss",
		"boss_name": "Frost Den", "entrance_name": "Frost Hollow",
		"grid_offset": Vector2i(800, 800),
	},
	{
		"id": "ashsprout_depths", "pool": "ashsprout", "grid": GRID_ASHSPROUT,
		"length": 8,
		"start_scene": R + "dungeon_entrance_ashsprout.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "ashsprout/ashsprout_boss_room.tscn",
		"seed": 41000,
		"anchor_mode": "none",
		"section": SECTION_ASHSPROUT_APPROACH,
		"end_label": "->  to the Blighted Heart",
		"endpoint_mode": "boss",
		"boss_name": "Blighted Heart", "entrance_name": "The Rotwood",
		"grid_offset": Vector2i(900, 900),
	},
	{
		"id": "eir_depths", "pool": "eir", "grid": GRID_EIR,
		"length": 8,
		"start_scene": R + "dungeon_entrance_eir.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "eir/eir_boss_room.tscn",
		"seed": 42000,
		"anchor_mode": "none",
		"section": SECTION_EIR_APPROACH,
		"end_label": "->  to the Fallen Sanctum",
		"endpoint_mode": "boss",
		"boss_name": "Fallen Sanctum", "entrance_name": "Valkyrie's Perch",
		"grid_offset": Vector2i(1000, 1000),
	},
	# ================================================================
	# ACT 3: BRIDGE + KING'S TOWER → HEIMDALL
	# ================================================================
	# Bridge path: converging from multiple altar completions
	# For now this is a short corridor ending at the Crowned Bridge.
	# The start scene is the Storsprunga Altar (the player's first
	# Act 1 hub, now serving as the Act 3 convergence point).
	{
		"id": "bridge_path", "pool": "strandvik", "grid": GRID_OVERWORLD,
		"length": 5,
		"start_scene": R + "storsprunga_altar.tscn",
		"start_exit_dir": "east",
		"end_scene": R + "crowned_bridge.tscn",
		"seed": 43000,
		"anchor_mode": "chain", "anchor_base": "coast",
		"anchor": Vector2i(5, 0),
		"scatter": Vector2i(1, 1), "perp_axis": "y",
		"section": SECTION_BRIDGE,
		"end_label": "->  to the Crowned Bridge",
		"endpoint_mode": "poi",
		"ep_name": "Crowned Bridge", "ep_type": TYPE_NORMAL,
		"ep_section": SECTION_BRIDGE,
	},
]

## Order chains are emitted into scene_graph. Endpoint-placing chains must
## come before chains that back-wire into their endpoints (_ensure_connection
## is a no-op on nodes that don't exist yet); dungeons come last so the
## sprekken entrance node placed by sprekken_approach wins its position.
const GRAPH_ORDER: Array = [
	"north", "west", "hollowmere",
	"hindarfjall", "hrimbjarg", "thursdal", "brann_approach",
	"eastreach", "myrkfen_approach", "sundust", "deep_desert",
	"east", "sprekken_approach", "coast", "coast_to_west",
	# Act 2 overworld chains
	"strandvik_path", "sindri_approach", "driftworks_path",
	"barrholt_path", "gymir_approach", "kaldrholt_path",
	"vindfell_path", "skadi_approach",
	"frostgard_path", "isvarda_path", "hrimfaxi_approach",
	"vatnborg_path", "vatnsteinn_path", "ashsprout_approach",
	"ashfeld_path", "kolfjall_path", "eir_approach",
	# Act 3
	"bridge_path",
	# Dungeon interiors (last so entrance nodes placed by approach chains win)
	"sprekken_depths", "brann_depths", "myrkfen_depths", "garnvik_depths",
	"sindri_depths", "gymir_depths", "skadi_depths",
	"hrimfaxi_depths", "ashsprout_depths", "eir_depths",
]

## Order runtime exit overrides apply per scene. LATER entries win when two
## chains touch the same scene, which encodes the old defense-in-depth
## ordering: e.g. coast_to_west's start override runs after coast's end
## override on the Storsprunga Altar; hollowmere and the mountain chains
## run after west; sprekken_approach and sundust run after eastreach.
const OVERRIDE_ORDER: Array = [
	"north", "sprekken_depths", "brann_depths", "myrkfen_depths",
	"garnvik_depths",
	"sindri_depths", "gymir_depths", "skadi_depths",
	"hrimfaxi_depths", "ashsprout_depths", "eir_depths",
	"coast", "coast_to_west",
	"west", "hollowmere",
	"hindarfjall", "hrimbjarg", "thursdal", "brann_approach",
	"eastreach", "myrkfen_approach", "sundust", "deep_desert",
	"east", "sprekken_approach",
	# Act 2 overworld chains (later entries win on shared scenes)
	"strandvik_path", "sindri_approach", "driftworks_path",
	"barrholt_path", "gymir_approach", "kaldrholt_path",
	"vindfell_path", "skadi_approach",
	"frostgard_path", "isvarda_path", "hrimfaxi_approach",
	"vatnborg_path", "vatnsteinn_path", "ashsprout_approach",
	"ashfeld_path", "kolfjall_path", "eir_approach",
	"bridge_path",
]

const ENTRANCE_PAIRS := [
	{"approach": "sprekken_approach", "depths": "sprekken_depths"},
	{"approach": "myrkfen_approach", "depths": "myrkfen_depths"},
	{"approach": "brann_approach", "depths": "brann_depths"},
	{"approach": "sindri_approach", "depths": "sindri_depths"},
	{"approach": "gymir_approach", "depths": "gymir_depths"},
	{"approach": "skadi_approach", "depths": "skadi_depths"},
	{"approach": "hrimfaxi_approach", "depths": "hrimfaxi_depths"},
	{"approach": "ashsprout_approach", "depths": "ashsprout_depths"},
	{"approach": "eir_approach", "depths": "eir_depths"},
]

# ---- runtime state ----

## pool_id → {"buffers": Array[String], "clearings": {dir: Array[String]}}
var _pools: Dictionary = {}
## Per-generation usage tracking, keyed by pool id. Shared across every
## chain drawing from that pool, so a scene file appears in at most one
## chain per run (the coast/coast_to_west fix).
var _used_buffers: Dictionary = {}
var _used_clearings: Dictionary = {}

## chain id → runtime dict:
##   { "def": Dictionary, "slots": Array[Dictionary],
##     "index": {scene_path: slot_i}, "roles": {scene_path: role},
##     "endpoint_cell": Vector2i, "city_cell": Vector2i }
var _chains: Dictionary = {}

## grid id → occupancy Dictionary (Vector2i cell → scene path)
var _grids: Dictionary = {}

var scene_graph: Dictionary = {}
var _exit_cache: Dictionary = {}

## Empty string when not in a dungeon; otherwise the dungeon id
## ("sprekken" or "brann") so the map UI can title itself and section
## visibility can tell "in any dungeon" from "in this specific dungeon."
var in_dungeon: String = ""


func _ready() -> void:
	_scan_pools()
	# Create the chain records BEFORE the deferred first generation.
	# _chains must be fully keyed the moment any scene can call into
	# apply_overrides / _build_graph — a region scene run directly
	# (F6) has its _ready fire before deferred calls, and with empty
	# records every override is a clean no-op (the old file's
	# per-chain member arrays gave this for free; the dictionary
	# needs it done explicitly).
	_reset_chain_records()
	EventBus.run_started.connect(_on_run_started)
	call_deferred("_generate_all_chains")
	call_deferred("_build_graph")


## Create (or wipe back to empty) the per-chain runtime records so
## every id in CHAIN_DEFS is always a valid _chains key. Slots start
## empty; generation fills them in.
func _reset_chain_records() -> void:
	_chains.clear()
	for def in CHAIN_DEFS:
		_chains[def["id"]] = {
			"def": def, "slots": [], "index": {}, "roles": {},
			"endpoint_cell": SENTINEL, "city_cell": SENTINEL,
			# Resolved at generation time (may differ from the def when
			# start_exit_dir_priority is set); default keeps pre-
			# generation callers consistent.
			"start_dir": def["start_exit_dir"],
		}


func _on_run_started(is_restore: bool) -> void:
	in_dungeon = ""
	# Clear map reveal flags so the map hides until the player reaches a
	# town again — but ONLY on a fresh run (death / new game). On a save
	# restore, the flags are part of the loaded story_flags and should
	# persist. This replaces the old SaveManager snapshot/restore hack
	# that copied reveals off-band before the emit and poured them back
	# in afterward.
	if not is_restore:
		for section in SECTION_REVEAL_FLAGS:
			var flag: String = SECTION_REVEAL_FLAGS[section]
			if flag != "":
				GameState.set_flag(flag, false)
	_generate_all_chains()
	_build_graph()


# ============================================================================
# POOL SCANNING
# ============================================================================

func _scan_pools() -> void:
	_pools.clear()
	for pool_id in POOL_DEFS:
		var pd: Dictionary = POOL_DEFS[pool_id]
		_pools[pool_id] = _scan_dir(String(pd["dir"]), String(pd["prefix"]))


## Scan a pool directory for buffer/cross/clearing scenes.
## Returns {"buffers": Array[String], "clearings": {exit_dir: Array[String]}}.
##
## Export-safety: in an exported PCK, Godot renames resources to
## "<name>.tscn.remap" — DirAccess enumerates the remapped names, so we
## strip the suffix before the extension check. load() on the original
## path still works; only the directory listing shows the remap.
##
## Determinism: filenames are sorted before classification so the pool
## order (which feeds every shuffle) is identical across filesystems and
## platforms for a given world_seed.
func _scan_dir(dir_path: String, base_prefix: String) -> Dictionary:
	var buffer_prefix: String = base_prefix + "_buffer_"
	var cross_prefix: String = base_prefix + "_cross_"
	var clearing_prefix: String = base_prefix + "_clearing_"
	var out: Dictionary = {"buffers": [], "clearings": {}}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("PathManager: can't open %s" % dir_path)
		return out
	var names: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean: String = fname.trim_suffix(".remap")
			if clean.ends_with(".tscn"):
				names.append(clean)
		fname = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var path: String = dir_path + "/" + n
		if n.begins_with(buffer_prefix) or n.begins_with(cross_prefix):
			out["buffers"].append(path)
		elif n.begins_with(clearing_prefix):
			var exits: Array = _get_buffer_exits(path)
			if exits.is_empty():
				continue
			var exit_dir: String = exits[0]
			if not out["clearings"].has(exit_dir):
				out["clearings"][exit_dir] = []
			out["clearings"][exit_dir].append(path)
	return out


## Read the Exit* child names of a scene WITHOUT instantiating it.
## SceneState enumerates the packed node tree in file order (matching
## get_children order), so exits[0] is the same "first Exit child" the
## old instantiate-based detector returned. Instanced sub-scenes'
## internal nodes don't appear in the state, which is exactly right —
## exits are authored as direct children by convention.
func _get_buffer_exits(scene_path: String) -> Array:
	if _exit_cache.has(scene_path):
		return _exit_cache[scene_path]
	var exits: Array = []
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_exit_cache[scene_path] = exits
		return exits
	var state: SceneState = packed.get_state()
	for i in state.get_node_count():
		var np: String = String(state.get_node_path(i))
		# Keep only direct children of the root. get_node_path returns
		# "." for the root and prefixes everything else with "./", so a
		# direct child is "./ExitEast" and a nested node is
		# "./Walls/WallTop" — strip the prefix, then any remaining "/"
		# means the node is nested deeper.
		if np == ".":
			continue
		if np.trim_prefix("./").find("/") != -1:
			continue
		var node_name: String = String(state.get_node_name(i))
		if node_name.begins_with("Exit"):
			exits.append(node_name.substr(4).to_lower())
	_exit_cache[scene_path] = exits
	return exits


func _scene_has_exit(scene_path: String, dir: String) -> bool:
	return dir in _get_buffer_exits(scene_path)


# ============================================================================
# GENERATION
# ============================================================================

func _generate_all_chains() -> void:
	# Fresh grids. Dungeon grids are seeded lazily (start scene at ZERO)
	# when their chain generates.
	_grids = {GRID_OVERWORLD: {}, GRID_SPREKKEN: {}, GRID_BRANN: {}, GRID_MYRKFEN: {}, GRID_GARNVIK: {}, GRID_SINDRI: {}, GRID_GYMIR: {}, GRID_SKADI: {}, GRID_HRIMFAXI: {}, GRID_ASHSPROUT: {}, GRID_EIR: {}}
	var overworld: Dictionary = _grids[GRID_OVERWORLD]
	for path in STATIC_SCENES:
		overworld[STATIC_SCENES[path]["pos"]] = path

	# Fresh per-pool usage tracking (shared across chains on the same pool).
	_used_buffers.clear()
	_used_clearings.clear()
	for pool_id in POOL_DEFS:
		_used_buffers[pool_id] = {}
		_used_clearings[pool_id] = {}

	# Fresh runtime records.
	_reset_chain_records()

	# ── Pre-pick pass ─────────────────────────────────────────────────
	# The absolute-anchor POI chains (north, east) pick their target
	# cells FIRST and reserve them, so no chain generated before them
	# can walk through where Nasus / the Wickbarrow Altar will land.
	# Draw order (north then east, statics-only occupancy for north)
	# matches the historical RNG sequence.
	var picked_targets: Dictionary = {}
	for def in CHAIN_DEFS:
		if not def.get("pre_pick", false):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = RunState.world_seed + int(def.get("target_seed", def["seed"]))
		var t: Vector2i = _pick_target_cell(def["anchor"], def["scatter"],
			String(def["perp_axis"]), overworld, rng)
		overworld[t] = def["end_scene"]
		picked_targets[def["id"]] = t

	# ── Generation pass — CHAIN_DEFS order is generation order ────────
	for def in CHAIN_DEFS:
		var id: String = def["id"]
		var rt: Dictionary = _chains[id]
		var occupied: Dictionary = _grids[def["grid"]]

		# Dungeon grids: seed the entrance at the origin so the chain
		# finds its start cell and can't walk back onto it.
		if def["grid"] != GRID_OVERWORLD and occupied.is_empty():
			occupied[Vector2i.ZERO] = def["start_scene"]

		# Resolve this chain's target cell.
		var target: Vector2i = SENTINEL
		var target_is_existing: bool = false
		var end_at: String = def.get("end_at_chain", "")
		if end_at != "":
			# Endpoint is another chain's already-placed endpoint (the
			# coast_to_west connector aiming at the Westmoor Altar).
			# The cell stays occupied — the terminal early-stop fires
			# when the cursor steps onto it, and the graph pass wires
			# the connection instead of placing a scene.
			assert(_chains[end_at]["endpoint_cell"] != SENTINEL,
				"PathManager: chain '%s' targets '%s' before it generated" % [id, end_at])
			target = _chains[end_at]["endpoint_cell"]
			target_is_existing = true
		elif picked_targets.has(id):
			target = picked_targets[id]
			# Free the reservation so the chain's terminal check can
			# land on the cell; it's re-reserved at resolution below.
			occupied.erase(target)
		elif def["anchor_mode"] == "chain":
			var base_id: String = def["anchor_base"]
			assert(_chains[base_id]["endpoint_cell"] != SENTINEL,
				"PathManager: chain '%s' anchors on '%s' before it generated" % [id, base_id])
			var base: Vector2i = _chains[base_id]["endpoint_cell"]
			var rng := RandomNumberGenerator.new()
			rng.seed = RunState.world_seed + int(def.get("target_seed", def["seed"]))
			target = _pick_target_cell(base + def["anchor"], def["scatter"],
				String(def["perp_axis"]), occupied, rng)
		elif def["anchor_mode"] == "absolute":
			var rng := RandomNumberGenerator.new()
			rng.seed = RunState.world_seed + int(def.get("target_seed", def["seed"]))
			target = _pick_target_cell(def["anchor"], def["scatter"],
				String(def["perp_axis"]), occupied, rng)
		# anchor_mode "none" keeps the sentinel: free random walk.

		_generate_chain(def, rt, occupied, target)
		# Slot-0 failure on a priority-start chain means the chosen
		# face was free but boxed in by surrounding trails. Retry the
		# remaining faces — a slot-0 failure places nothing, so
		# retrying has no side effects. Faces that failed are recorded
		# on rt so the selector skips them.
		if not def.get("start_exit_dir_priority", []).is_empty():
			var tries: int = 0
			var unboxed_dirs: Array = []
			while rt["slots"].is_empty() and tries < 8:
				tries += 1
				var cur_dir: String = String(rt["start_dir"])
				# A free face can still be a dead pocket (the cursor
				# boxed in by trails). If decorative clearings are
				# among the blockers, evict them and retry the SAME
				# face once before writing it off.
				var did_unbox := false
				if not (cur_dir in unboxed_dirs):
					unboxed_dirs.append(cur_dir)
					var sc: Vector2i = rt.get("start_cell", SENTINEL)
					if sc != SENTINEL:
						var cursor: Vector2i = sc + DIR_VECTORS[cur_dir]
						for d in DIR_VECTORS:
							var c: Vector2i = cursor + DIR_VECTORS[d]
							if String(occupied.get(c, "")).find("_clearing_") != -1 \
									and _evict_side_clearing(c, occupied):
								did_unbox = true
				if not did_unbox:
					var failed: Array = rt.get("_failed_start_dirs", [])
					if cur_dir in failed:
						break
					failed.append(cur_dir)
					rt["_failed_start_dirs"] = failed
				_generate_chain(def, rt, occupied, target)
			rt.erase("_failed_start_dirs")

		# ── Endpoint resolution ───────────────────────────────────────
		# THE core correctness rule of this file: every chain's endpoint
		# cell is resolved (target if reached, natural end otherwise)
		# and reserved IMMEDIATELY after generation, BEFORE any
		# downstream chain anchors on it or searches for it as a start
		# scene. The graph pass then places scenes at these resolved
		# cells — generation and graph can no longer disagree.
		if def["endpoint_mode"] == "boss":
			# Dungeon boss rooms live one step past the last buffer on
			# an isolated grid; nothing downstream anchors on them, so
			# the graph pass computes the cell directly.
			continue
		if target_is_existing:
			rt["endpoint_cell"] = target
			continue

		var ep: Vector2i = _resolve_endpoint_cell(rt, def, target, occupied)
		if ep != target and occupied.get(target) == def["end_scene"]:
			# Pre-picked reservation is moving to the natural end.
			occupied.erase(target)
		occupied[ep] = def["end_scene"]
		rt["endpoint_cell"] = ep

		# Paired city / gate: reserve its cell now, relative to the
		# RESOLVED endpoint, with the same neighbor fallback the graph
		# pass uses — so downstream chains that start FROM the paired
		# scene (west/eastreach from Nasus City, sundust from the gate)
		# find it at the cell it will actually occupy.
		if String(def.get("city_path", "")) != "":
			var cp: Vector2i = ep + def["city_offset"]
			if occupied.has(cp):
				for d in ["north", "east", "west", "south"]:
					var c: Vector2i = ep + DIR_VECTORS[d]
					if not occupied.has(c):
						cp = c
						break
			occupied[cp] = def["city_path"]
			rt["city_cell"] = cp

	# Role/index tables for O(1) runtime override lookup.
	for id in _chains:
		_index_chain_roles(_chains[id])


## Where does this chain's endpoint actually sit? Target if the chain
## reached it; the cell one step past the last buffer otherwise. Includes
## a defensive neighbor fallback if the natural end is somehow occupied
## (shouldn't happen — forward cells are empty at pick time and the
## endpoint is reserved before any later chain runs — but a graceful
## slide beats a stacked cell).
func _resolve_endpoint_cell(rt: Dictionary, def: Dictionary,
		target: Vector2i, occupied: Dictionary) -> Vector2i:
	var slots: Array = rt["slots"]
	if slots.is_empty():
		# No chain at all (pool missing). Cosmetic fallback: one step
		# out of the start scene, or the target if the start is unknown.
		if STATIC_SCENES.has(def["start_scene"]):
			return STATIC_SCENES[def["start_scene"]]["pos"] + DIR_VECTORS[def["start_exit_dir"]]
		if target != SENTINEL:
			return target
		return DIR_VECTORS[def["start_exit_dir"]]
	var last: Dictionary = slots[slots.size() - 1]
	var natural: Vector2i = last["pos"] + DIR_VECTORS[last["forward_exit_dir"]]
	if natural == target:
		return target
	if not occupied.has(natural):
		return natural
	# Defensive: slide along the chain axis first, perpendicular last.
	var sd: String = String(rt.get("start_dir", def["start_exit_dir"]))
	var axis_order: Array
	if sd == "east" or sd == "west":
		axis_order = [sd, OPPOSITE[sd], "north", "south"]
	else:
		axis_order = [sd, OPPOSITE[sd], "east", "west"]
	for d in axis_order:
		var c: Vector2i = last["pos"] + DIR_VECTORS[d]
		if not occupied.has(c):
			return c
	return natural


## Pick a deterministic unoccupied cell within [anchor - scatter,
## anchor + scatter]. Deviations on the perpendicular axis are penalized
## (PERP_AXIS_WEIGHT) so POIs prefer their cardinal line; an RNG
## tiebreaker keeps equal-score cells varying per seed. Falls back to the
## anchor if the whole box is taken (never in practice).
const PERP_AXIS_WEIGHT := 3
func _pick_target_cell(anchor: Vector2i, scatter: Vector2i, perp_axis: String,
		occupied: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var candidates: Array = []
	for dx in range(-scatter.x, scatter.x + 1):
		for dy in range(-scatter.y, scatter.y + 1):
			var cell := anchor + Vector2i(dx, dy)
			if not occupied.has(cell):
				candidates.append(cell)
	if candidates.is_empty():
		return anchor
	var with_score: Array = []
	for c in candidates:
		var dx_anc: int = abs(c.x - anchor.x)
		var dy_anc: int = abs(c.y - anchor.y)
		var score: int
		if perp_axis == "x":
			score = dx_anc * PERP_AXIS_WEIGHT + dy_anc
		else:
			score = dx_anc + dy_anc * PERP_AXIS_WEIGHT
		with_score.append({"cell": c, "score": score, "tie": rng.randi()})
	with_score.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] < b["score"]
		return a["tie"] < b["tie"])
	# Pick from the top tier so the result stays near the anchor most of
	# the time while allowing per-seed variety.
	var top_n: int = clampi(with_score.size() / 2, 1, 4)
	var pick_idx: int = rng.randi_range(0, top_n - 1)
	return with_score[pick_idx]["cell"]


## Generate one chain's spine + side branches into rt["slots"].
##
## The walking algorithm is ported intact from the pre-refactor version
## (target-bias scoring, force_converge, chain_axis lock, reserved
## approach dirs, final-slot face forcing, early stop on target). The
## only structural change: buffer and clearing usage is tracked in the
## PER-POOL shared sets (_used_buffers/_used_clearings) instead of
## per-chain locals, so chains sharing a pool can't duplicate scenes.
func _generate_chain(def: Dictionary, rt: Dictionary, occupied: Dictionary,
		target_cell: Vector2i) -> void:
	var chain_out: Array = rt["slots"]
	chain_out.clear()

	var pool: Dictionary = _pools.get(def["pool"], {"buffers": [], "clearings": {}})
	var used_buffers: Dictionary = _used_buffers[def["pool"]]
	var used_clearings: Dictionary = _used_clearings[def["pool"]]

	var chain_length: int = def["length"]
	var start_scene: String = def["start_scene"]
	var start_exit_dir: String = def["start_exit_dir"]
	var end_scene: String = def["end_scene"]
	var chain_axis: String = def.get("chain_axis", "")
	var reserved_approach_dirs: Array = def.get("reserved_approach_dirs", [])
	var final_forward_dir: String = def.get("final_forward_dir", "")

	var rng := RandomNumberGenerator.new()
	rng.seed = RunState.world_seed + int(def["seed"])

	var has_target: bool = target_cell != SENTINEL

	var shuffled_buffers: Array = pool["buffers"].duplicate()
	for i in range(shuffled_buffers.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled_buffers[i]
		shuffled_buffers[i] = shuffled_buffers[j]
		shuffled_buffers[j] = tmp

	var shuffled_clearings: Dictionary = {}
	for dir_key in pool["clearings"]:
		var arr: Array = pool["clearings"][dir_key].duplicate()
		for i in range(arr.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = arr[i]
			arr[i] = arr[j]
			arr[j] = tmp
		shuffled_clearings[dir_key] = arr

	# Cursor start: one step from start_scene in the start exit dir. The
	# start scene is found in the occupancy grid — statics are seeded
	# there, and dynamically-placed starts (Nasus City, the Sundust
	# Gate, resolved altars) are reserved by their owning chain's
	# endpoint-resolution step before this chain runs.
	var start_cell: Vector2i = SENTINEL
	for pos in occupied:
		if occupied[pos] == start_scene:
			start_cell = pos
			break
	if start_cell == SENTINEL and STATIC_SCENES.has(start_scene):
		start_cell = STATIC_SCENES[start_scene]["pos"]
	rt["start_cell"] = start_cell

	# ── Adaptive start face ───────────────────────────────────────────
	# When the def lists a start_exit_dir_priority, the chain departs
	# through the first face whose adjacent cell is still free. Needed
	# for the act-2 mountain chains: three chains share hollowmere
	# village with the hollowmere trail's own approach, and which face
	# the trail's last buffer lands on varies by seed — a fixed face
	# can be (and, for thursdal, always was) permanently blocked. The
	# resolved direction is stored on rt so overrides and endpoint
	# resolution wire the exit that was actually used.
	var start_dir_priority: Array = def.get("start_exit_dir_priority", [])
	var failed_dirs: Array = rt.get("_failed_start_dirs", [])
	if start_cell != SENTINEL and not start_dir_priority.is_empty():
		var chosen := ""
		for d in start_dir_priority:
			if d in failed_dirs:
				continue
			if not occupied.has(start_cell + DIR_VECTORS[d]):
				chosen = d
				break
		if chosen == "":
			# All faces taken. If one is only blocked by a sibling
			# chain's side-branch content (a decorative dead-end),
			# evict it — a chain start beats a clearing.
			for d in start_dir_priority:
				if d in failed_dirs:
					continue
				var c: Vector2i = start_cell + DIR_VECTORS[d]
				if String(occupied.get(c, "")).find("_clearing_") != -1 \
						and _evict_side_clearing(c, occupied):
					chosen = d
					break
		if chosen != "":
			start_exit_dir = chosen
	rt["start_dir"] = start_exit_dir

	var needed_entry: String = OPPOSITE[start_exit_dir]
	var cursor: Vector2i
	if start_cell != SENTINEL:
		cursor = start_cell + DIR_VECTORS[start_exit_dir]
	else:
		cursor = DIR_VECTORS[start_exit_dir]

	# ── Approach-face reservation ─────────────────────────────────────
	# final_forward_dir promises the endpoint is ENTERED heading that
	# way, i.e. the last buffer sits on the target's OPPOSITE face. The
	# final-slot check alone can't deliver that: the walk is free to
	# arrive adjacent from any other side first, and then it's too late.
	# So while this chain walks, block the target's three non-approach
	# neighbor cells with a sentinel — the only route onto the target is
	# through the requested face. The sentinels are removed right after
	# the walk (before endpoint resolution), so they never leak into the
	# grid other chains see. Needed for hollowmere: the village's other
	# three faces are the START cells of the act-2 mountain chains.
	const APPROACH_SENTINEL := "__approach_reserved__"
	var reserved_cells: Array = []
	if has_target and final_forward_dir != "":
		var approach_cell: Vector2i = target_cell - DIR_VECTORS[final_forward_dir]
		for d in DIR_VECTORS:
			var c: Vector2i = target_cell + DIR_VECTORS[d]
			if c == approach_cell or c == cursor or occupied.has(c):
				continue
			occupied[c] = APPROACH_SENTINEL
			reserved_cells.append(c)

	for slot_i in chain_length:
		# Clearing availability this slot: the per-chain shuffled order,
		# minus anything already consumed from this pool (by this chain
		# OR a sibling chain sharing the pool).
		var available_clearings: Dictionary = {}
		for dir_key in shuffled_clearings:
			var avail: Array = []
			for c in shuffled_clearings[dir_key]:
				if not used_clearings.has(c):
					avail.append(c)
			available_clearings[dir_key] = avail

		# Direction priority toward the target (empty without a target —
		# the evaluator falls back to shuffled order).
		var preferred_dirs: Array = []
		if has_target:
			preferred_dirs = _direction_priority_toward(cursor, target_cell, rng)

		var picked_path := ""
		var picked_plan: Dictionary = {}
		# Force final-stretch convergence when the remaining budget is
		# within 3 of the manhattan distance — meandering early,
		# decisive late.
		var force_converge: bool = has_target \
			and (chain_length - slot_i) <= _manhattan(cursor, target_cell) + 3

		# When final_forward_dir is set and one step in that direction
		# lands on the target, this is the last slot — restrict the
		# forward dir so the endpoint lands on the requested face.
		var is_final_slot: bool = has_target and final_forward_dir != "" \
			and (cursor + DIR_VECTORS.get(final_forward_dir, Vector2i.ZERO)) == target_cell

		if not has_target:
			# Free walk: first valid buffer in shuffle order.
			for candidate in shuffled_buffers:
				if used_buffers.has(candidate):
					continue
				var plan := _evaluate_candidate(candidate, cursor, needed_entry,
					available_clearings, rng, occupied,
					preferred_dirs, target_cell, has_target, force_converge,
					chain_axis, reserved_approach_dirs)
				if plan.is_empty():
					continue
				if is_final_slot and plan["forward_dir"] != final_forward_dir:
					continue
				picked_path = candidate
				picked_plan = plan
				break
		else:
			# Targeted: score every valid candidate by forward-direction
			# alignment with the target delta, pick the best.
			var best_score: int = -999999
			var best_tie: int = 0
			for candidate in shuffled_buffers:
				if used_buffers.has(candidate):
					continue
				var plan := _evaluate_candidate(candidate, cursor, needed_entry,
					available_clearings, rng, occupied,
					preferred_dirs, target_cell, has_target, force_converge,
					chain_axis, reserved_approach_dirs)
				if plan.is_empty():
					continue
				if is_final_slot and plan["forward_dir"] != final_forward_dir:
					continue
				var fd: String = plan["forward_dir"]
				var dv: Vector2i = DIR_VECTORS[fd]
				var delta: Vector2i = target_cell - cursor
				var score: int = dv.x * delta.x + dv.y * delta.y
				var tie: int = rng.randi()
				if score > best_score or (score == best_score and tie < best_tie):
					best_score = score
					best_tie = tie
					picked_path = candidate
					picked_plan = plan
		# Final-slot fallback: no buffer satisfied the face constraint —
		# take any valid buffer. Wrong face beats failed generation.
		if picked_path == "" and is_final_slot:
			push_warning("PathManager: chain '%s' slot %d couldn't satisfy final_forward_dir=%s; falling back" % [def["id"], slot_i, final_forward_dir])
			for candidate in shuffled_buffers:
				if used_buffers.has(candidate):
					continue
				var plan := _evaluate_candidate(candidate, cursor, needed_entry,
					available_clearings, rng, occupied,
					preferred_dirs, target_cell, has_target, force_converge,
					chain_axis, reserved_approach_dirs)
				if plan.is_empty():
					continue
				picked_path = candidate
				picked_plan = plan
				break
		if picked_path == "":
			push_warning("PathManager: chain '%s' ended early at slot %d" % [def["id"], slot_i])
			break

		used_buffers[picked_path] = true
		occupied[cursor] = picked_path

		var side_exit_dirs: Array = []
		var side_clearings: Array = []
		for ps in picked_plan["planned_sides"]:
			var sd: String = ps["dir"]
			var clr_path: String = ps["clearing"]
			occupied[cursor + DIR_VECTORS[sd]] = clr_path
			side_exit_dirs.append(sd)
			side_clearings.append(clr_path)
			used_clearings[clr_path] = true

		var backward_target := ""
		if slot_i == 0:
			backward_target = start_scene
		else:
			backward_target = chain_out[chain_out.size() - 1]["scene_path"]

		chain_out.append({
			"scene_path": picked_path,
			"pos": cursor,
			"entry_dir": needed_entry,
			"backward_exit_dir": needed_entry,
			"forward_exit_dir": picked_plan["forward_dir"],
			"side_exit_dirs": side_exit_dirs,
			"side_clearings": side_clearings,
			# Uniform side-branch structure parallel to side_exit_dirs /
			# side_clearings. Starts length-1 (clearing adjacent to the
			# spine); the extension pass may promote to length 2-3 with
			# transit buffers. `rooms` runs spine-outward; `positions`
			# matches 1:1; the last entry is always the clearing.
			"side_branches": _initial_side_branches(cursor, side_exit_dirs, side_clearings),
			"wired_sides": picked_plan["wired_sides"],
			"backward_target": backward_target,
			"forward_target": "",
		})

		var next_cursor: Vector2i = cursor + DIR_VECTORS[picked_plan["forward_dir"]]
		# Early stop: the forward exit lands ON the target — the chain
		# is done and the endpoint attaches here.
		if has_target and next_cursor == target_cell:
			cursor = next_cursor
			break

		cursor = next_cursor
		needed_entry = OPPOSITE[picked_plan["forward_dir"]]

	# Release the approach-face sentinels. Done BEFORE side-branch
	# extension and endpoint resolution so nothing downstream ever sees
	# them — sentinels were only placed on cells that were empty, and
	# nothing writes those cells while the sentinel occupies them.
	for c in reserved_cells:
		if occupied.get(c) == APPROACH_SENTINEL:
			occupied.erase(c)

	# Extend some side branches into 2- or 3-room corridors (post-pass so
	# branch logic can't couple with the delicate spine walk).
	_extend_side_branches(chain_out, pool["buffers"], used_buffers,
		occupied, rng, shuffled_clearings, used_clearings)

	for i in chain_out.size():
		if i < chain_out.size() - 1:
			chain_out[i]["forward_target"] = chain_out[i + 1]["scene_path"]
		else:
			chain_out[i]["forward_target"] = end_scene


## Remove whatever side-branch content occupies `cell` from whichever
## chain owns it, freeing the cell(s) and returning the scenes to their
## pools. Handles three shapes: a transit-side clearing hanging off a
## transit room, a single-room branch, and a whole extended branch when
## the blocking cell is any of its rooms (removing just the tail would
## orphan the transits, so the entire dead-end appendix goes). Runs
## during generation (before role indexing and the graph pass); any
## wired_sides references into evicted scenes are dropped so the
## dangling-exit sweep re-wires those exits safely.
func _evict_side_clearing(cell: Vector2i, occupied: Dictionary) -> bool:
	for id in _chains:
		var rt: Dictionary = _chains[id]
		var pool_id: String = String(rt["def"]["pool"])
		var slots: Array = rt["slots"]
		for slot in slots:
			var branches: Array = slot["side_branches"]
			for bi in range(branches.size() - 1, -1, -1):
				var br: Dictionary = branches[bi]
				var positions: Array = br["positions"]
				var tsc: Array = br.get("transit_side_clearings", [])

				# (a) Transit-side clearing at the cell: drop just it.
				for ri in tsc.size():
					var arr: Array = tsc[ri]
					for k in range(arr.size() - 1, -1, -1):
						var sc: Dictionary = arr[k]
						if positions[ri] + DIR_VECTORS[sc["dir"]] != cell:
							continue
						arr.remove_at(k)
						occupied.erase(cell)
						if _used_clearings.has(pool_id):
							_used_clearings[pool_id].erase(sc["scene"])
						_drop_wired_refs([sc["scene"]])
						return true

				# (b) A branch room at the cell: evict the whole branch.
				var hit := false
				for p in positions:
					if p == cell:
						hit = true
						break
				if not hit:
					continue
				var evicted: Array = []
				for ri in positions.size():
					occupied.erase(positions[ri])
				for ri in tsc.size():
					for sc in tsc[ri]:
						occupied.erase(positions[ri] + DIR_VECTORS[sc["dir"]])
						if _used_clearings.has(pool_id):
							_used_clearings[pool_id].erase(sc["scene"])
						evicted.append(sc["scene"])
				var rooms: Array = br["rooms"]
				for ri in rooms.size():
					var room: String = rooms[ri]
					evicted.append(room)
					if ri == rooms.size() - 1:
						if _used_clearings.has(pool_id):
							_used_clearings[pool_id].erase(room)
					else:
						if _used_buffers.has(pool_id):
							_used_buffers[pool_id].erase(room)
				branches.remove_at(bi)
				# The spine slot's parallel side arrays still name the
				# branch — purge them so _override_exits can't wire the
				# spine's side exit at an evicted scene (the sweep
				# re-points that exit instead).
				var sda: Array = slot.get("side_exit_dirs", [])
				var sca: Array = slot.get("side_clearings", [])
				var kk: int = sda.find(br["dir"])
				if kk != -1:
					sda.remove_at(kk)
					if kk < sca.size():
						sca.remove_at(kk)
				_drop_wired_refs(evicted)
				return true
	return false


## Remove wired_sides entries pointing at evicted scenes across every
## generated slot — the affected exits fall back to the dangling-exit
## sweep instead of teleporting to a scene that no longer exists.
func _drop_wired_refs(evicted: Array) -> void:
	for id in _chains:
		for slot in _chains[id]["slots"]:
			var wsa: Array = slot.get("wired_sides", [])
			for k in range(wsa.size() - 1, -1, -1):
				if wsa[k]["target"] in evicted:
					wsa.remove_at(k)


## Build the initial (length-1) side_branches array. Uniform shape
## regardless of length so downstream code iterates without special-casing.
func _initial_side_branches(spine_pos: Vector2i, dirs: Array,
		clearings: Array) -> Array:
	var out: Array = []
	for k in dirs.size():
		var sd: String = dirs[k]
		out.append({
			"dir": sd,
			"rooms": [clearings[k]],
			"positions": [spine_pos + DIR_VECTORS[sd]],
		})
	return out


## Extension pass: lengthen some side branches from 1 room to 2 or 3 by
## inserting transit buffers between the spine fork and the clearing.
## Weighted 60/30/10 toward staying short — the buffer pool is shared
## with the spine (and with sibling chains on the same pool).
const BRANCH_LENGTH_WEIGHTS := [60, 30, 10]  # indices 0,1,2 → length 1,2,3
func _extend_side_branches(chain_arr: Array,
		buffer_pool: Array, used_buffers: Dictionary,
		occupied: Dictionary, rng: RandomNumberGenerator,
		shuffled_clearings: Dictionary, used_clearings: Dictionary) -> void:
	for slot in chain_arr:
		var branches: Array = slot["side_branches"]
		for branch in branches:
			var roll: int = rng.randi_range(0, 99)
			var target_len: int = 1
			var cum: int = 0
			for i in BRANCH_LENGTH_WEIGHTS.size():
				cum += BRANCH_LENGTH_WEIGHTS[i]
				if roll < cum:
					target_len = i + 1
					break
			if target_len == 1:
				continue
			_try_extend_branch(slot, branch, target_len, buffer_pool,
				used_buffers, occupied, rng,
				shuffled_clearings, used_clearings)


## Try to extend `branch` (currently length 1) to `target_len` rooms.
## Atomic: the full plan is validated before anything commits; failure
## leaves the branch untouched.
func _try_extend_branch(slot: Dictionary, branch: Dictionary,
		target_len: int, buffer_pool: Array,
		used_buffers: Dictionary, occupied: Dictionary,
		rng: RandomNumberGenerator,
		shuffled_clearings: Dictionary, used_clearings: Dictionary) -> void:
	var dir: String = branch["dir"]
	# Entry to each transit buffer faces back toward the spine; forward
	# continues outward along the branch.
	var entry: String = OPPOSITE[dir]
	var forward: String = dir
	var spine_pos: Vector2i = slot["pos"]
	var num_transit: int = target_len - 1

	var dv: Vector2i = DIR_VECTORS[dir]
	var transit_positions: Array = []
	for k in num_transit:
		transit_positions.append(spine_pos + dv * (k + 1))
	var clearing_new_pos: Vector2i = spine_pos + dv * target_len

	# Cell collisions. The clearing's CURRENT cell is being re-occupied
	# by a transit buffer, so exempt it.
	var clearing_current_pos: Vector2i = branch["positions"][0]
	for pos in transit_positions:
		if pos == clearing_current_pos:
			continue
		if occupied.has(pos):
			return
	if clearing_new_pos != clearing_current_pos and occupied.has(clearing_new_pos):
		return

	# Compatible transit buffers: entry AND forward among their exits,
	# not yet used anywhere in this pool. Preference: higher exit count
	# first (X over T over straight) — more interesting transits — with
	# the shuffle providing variety within each tier.
	var pool_shuffled: Array = buffer_pool.duplicate()
	for i in range(pool_shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool_shuffled[i]
		pool_shuffled[i] = pool_shuffled[j]
		pool_shuffled[j] = tmp
	var exit_count: Dictionary = {}
	for b in pool_shuffled:
		exit_count[b] = _get_buffer_exits(b).size()
	pool_shuffled.sort_custom(func(a, b):
		return exit_count[a] > exit_count[b])

	var chosen_transits: Array = []
	for candidate in pool_shuffled:
		if chosen_transits.size() >= num_transit:
			break
		if used_buffers.has(candidate):
			continue
		var exits: Array = _get_buffer_exits(candidate)
		if not (entry in exits) or not (forward in exits):
			continue
		chosen_transits.append(candidate)

	if chosen_transits.size() < num_transit:
		return

	# Commit the branch spine. Side clearings off T/X transits are
	# best-effort below and never block the branch itself.
	occupied.erase(clearing_current_pos)
	var clearing_path: String = branch["rooms"][0]
	for k in num_transit:
		occupied[transit_positions[k]] = chosen_transits[k]
		used_buffers[chosen_transits[k]] = true
	occupied[clearing_new_pos] = clearing_path

	# Per-transit side clearings: for each extra exit (beyond entry and
	# forward) on a T/X transit, spawn a clearing if a cell and a pool
	# entry are available. transit_side_clearings is parallel to `rooms`;
	# the terminal clearing's entry is always [].
	var transit_side_clearings: Array = []
	for k in num_transit:
		var transit_path: String = chosen_transits[k]
		var transit_pos: Vector2i = transit_positions[k]
		var transit_exits: Array = _get_buffer_exits(transit_path)
		var sides: Array = []
		for ed in transit_exits:
			if ed == entry or ed == forward:
				continue
			var side_pos: Vector2i = transit_pos + DIR_VECTORS[ed]
			if occupied.has(side_pos):
				continue
			# The clearing pool is keyed by the clearing's own exit
			# direction — for a clearing placed in direction `ed`, its
			# exit faces OPPOSITE[ed].
			var needed: String = OPPOSITE[ed]
			var pool_arr: Array = shuffled_clearings.get(needed, [])
			var clr_path: String = ""
			for cand in pool_arr:
				if not used_clearings.has(cand):
					clr_path = cand
					break
			if clr_path == "":
				continue   # pool exhausted
			used_clearings[clr_path] = true
			occupied[side_pos] = clr_path
			sides.append({"dir": ed, "scene": clr_path, "pos": side_pos})
		transit_side_clearings.append(sides)
	transit_side_clearings.append([])

	# Rewrite the branch to its new shape.
	var new_rooms: Array = []
	var new_positions: Array = []
	for k in num_transit:
		new_rooms.append(chosen_transits[k])
		new_positions.append(transit_positions[k])
	new_rooms.append(clearing_path)
	new_positions.append(clearing_new_pos)
	branch["rooms"] = new_rooms
	branch["positions"] = new_positions
	branch["transit_side_clearings"] = transit_side_clearings

	# Legacy side_clearings sync: the spine's immediate neighbor on this
	# side is now the first transit buffer, not the clearing.
	var sda: Array = slot["side_exit_dirs"]
	var sca: Array = slot["side_clearings"]
	for k in sda.size():
		if sda[k] == dir:
			sca[k] = chosen_transits[0]
			break


func _evaluate_candidate(candidate: String, cursor: Vector2i,
		entry_dir: String, available_clearings: Dictionary,
		rng: RandomNumberGenerator, occupied: Dictionary,
		preferred_dirs: Array = [], target_cell: Vector2i = SENTINEL,
		has_target: bool = false, force_converge: bool = false,
		chain_axis: String = "",
		reserved_approach_dirs: Array = []) -> Dictionary:
	if occupied.has(cursor):
		return {}
	var exits: Array = _get_buffer_exits(candidate)
	if not (entry_dir in exits) or exits.size() < 2:
		return {}

	var empty_dirs: Array = []
	var wired_sides: Array = []
	for ed in exits:
		if ed == entry_dir:
			continue
		if not DIR_VECTORS.has(ed):
			return {}
		var adj: Vector2i = cursor + DIR_VECTORS[ed]
		if not occupied.has(adj):
			empty_dirs.append(ed)
		else:
			# Non-resource occupants (the approach-face sentinel) hard-
			# block: no exit can wire into them, and load() must never
			# see them.
			var neighbor: String = String(occupied[adj])
			if not neighbor.begins_with("res://"):
				return {}
			if _scene_has_exit(neighbor, OPPOSITE[ed]):
				wired_sides.append({"dir": ed, "target": neighbor})
			else:
				return {}
	if empty_dirs.is_empty():
		return {}

	# Forward-direction try order. Without a target: shuffled. With one:
	# preferred (target-aligned) first, convergent-only when forced.
	var forward_order: Array = empty_dirs.duplicate()

	if has_target and not preferred_dirs.is_empty():
		var ordered: Array = []
		for pd in preferred_dirs:
			if pd in empty_dirs and not (pd in ordered):
				ordered.append(pd)
		for ed in empty_dirs:
			if not (ed in ordered):
				ordered.append(ed)
		forward_order = ordered

		if force_converge:
			# Only directions that strictly reduce manhattan distance —
			# keeps the chain on-rail in the final stretch.
			var converging: Array = []
			var d_now: int = _manhattan(cursor, target_cell)
			for fd in forward_order:
				if _manhattan(cursor + DIR_VECTORS[fd], target_cell) < d_now:
					converging.append(fd)
			if not converging.is_empty():
				forward_order = converging
	else:
		for i in range(forward_order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = forward_order[i]
			forward_order[i] = forward_order[j]
			forward_order[j] = tmp

	# Hard cardinal-axis filter. Applied AFTER the preferred/converge
	# rebuilds so nothing downstream can reintroduce off-axis directions
	# (this ordering was a fixed bug in an earlier iteration). Side
	# branches are unaffected — perpendicular exits still spawn
	# clearings; they just can't be the chain's forward direction.
	if chain_axis == "horizontal":
		var allowed: Array = []
		for fd in forward_order:
			if fd == "east" or fd == "west":
				allowed.append(fd)
		if allowed.is_empty():
			return {}
		forward_order = allowed
	elif chain_axis == "vertical":
		var allowed: Array = []
		for fd in forward_order:
			if fd == "north" or fd == "south":
				allowed.append(fd)
		if allowed.is_empty():
			return {}
		forward_order = allowed

	# Reserved-approach filter: for each `d` in the list, forbid
	# forward_dir = OPPOSITE[d] on EVERY slot, so the end-of-chain
	# override (which rewires OPPOSITE[last.forward_dir] on the endpoint)
	# can never touch the endpoint's `d` exit. Applied last for the same
	# no-rebuild-after reason as chain_axis.
	if not reserved_approach_dirs.is_empty():
		var forbidden_set: Dictionary = {}
		for d in reserved_approach_dirs:
			var opp: String = OPPOSITE.get(d, "")
			if opp != "":
				forbidden_set[opp] = true
		if not forbidden_set.is_empty():
			var allowed_r: Array = []
			for fd in forward_order:
				if not forbidden_set.has(fd):
					allowed_r.append(fd)
			if allowed_r.is_empty():
				return {}
			forward_order = allowed_r

	for forward_dir in forward_order:
		var side_empties: Array = []
		for ed in empty_dirs:
			if ed != forward_dir:
				side_empties.append(ed)

		# Never let a side clearing land on the target cell (the target
		# isn't in `occupied` while its own chain is in flight, so the
		# clearing placement below would happily stack onto it).
		if has_target:
			var side_collision: bool = false
			for sd in side_empties:
				if cursor + DIR_VECTORS[sd] == target_cell:
					side_collision = true
					break
			if side_collision:
				continue
		var clearings_taken: Dictionary = {}
		var planned_sides: Array = []
		var ok := true
		for sd in side_empties:
			var needed: String = OPPOSITE[sd]
			var pool: Array = available_clearings.get(needed, [])
			var taken: int = clearings_taken.get(needed, 0)
			if taken >= pool.size():
				ok = false
				break
			planned_sides.append({"dir": sd, "clearing": pool[taken]})
			clearings_taken[needed] = taken + 1
		if not ok:
			continue
		return {"forward_dir": forward_dir, "planned_sides": planned_sides, "wired_sides": wired_sides}
	return {}


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


## Cardinal directions sorted by alignment with (target - cursor); RNG
## tiebreaker keeps equal scores varying per seed. Shuffled when already
## at the target (degenerate case — no preferred way to go).
func _direction_priority_toward(cursor: Vector2i, target: Vector2i,
		rng: RandomNumberGenerator) -> Array:
	var delta: Vector2i = target - cursor
	var all_dirs: Array = ["north", "south", "east", "west"]
	if delta == Vector2i.ZERO:
		for i in range(all_dirs.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = all_dirs[i]
			all_dirs[i] = all_dirs[j]
			all_dirs[j] = tmp
		return all_dirs

	var scored: Array = []
	for d in all_dirs:
		var dv: Vector2i = DIR_VECTORS[d]
		var score: int = dv.x * delta.x + dv.y * delta.y
		scored.append({"dir": d, "score": score, "tie": rng.randi()})
	scored.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["tie"] < b["tie"])
	var out: Array = []
	for entry in scored:
		out.append(entry["dir"])
	return out


## Build the O(1) runtime lookup tables for a generated chain:
##   rt["index"] — spine scene_path → slot index (used by _override_exits
##                 to resolve spawn markers on backward transitions)
##   rt["roles"] — every scene this chain owns → its role, consumed by
##                 apply_overrides instead of the old nested scans.
## Role kinds: "slot", "branch_first" (first room of a side branch — the
## clearing for length-1 branches, the first transit buffer otherwise),
## "branch_room" (rooms deeper in an extended branch), "transit_side"
## (clearings hanging off T/X transit buffers).
func _index_chain_roles(rt: Dictionary) -> void:
	var roles: Dictionary = {}
	var index: Dictionary = {}
	var slots: Array = rt["slots"]
	for i in slots.size():
		var slot: Dictionary = slots[i]
		index[slot["scene_path"]] = i
		roles[slot["scene_path"]] = {"kind": "slot", "i": i}
		var branches: Array = slot.get("side_branches", [])
		for k in branches.size():
			var branch: Dictionary = branches[k]
			var rooms: Array = branch["rooms"]
			if rooms.size() > 0:
				roles[rooms[0]] = {"kind": "branch_first", "slot": i, "branch": k}
			for ri in range(1, rooms.size()):
				roles[rooms[ri]] = {"kind": "branch_room", "slot": i, "branch": k, "ri": ri}
			var tsc: Array = branch.get("transit_side_clearings", [])
			for ti in tsc.size():
				for sc_data in tsc[ti]:
					roles[sc_data["scene"]] = {
						"kind": "transit_side", "slot": i, "branch": k,
						"ti": ti, "dir": sc_data["dir"],
					}
	rt["roles"] = roles
	rt["index"] = index


# ============================================================================
# GRAPH
# ============================================================================

func _build_graph() -> void:
	scene_graph.clear()
	for path in STATIC_SCENES:
		var data: Dictionary = STATIC_SCENES[path]
		scene_graph[path] = {
			"pos": data["pos"], "type": data["type"], "name": data["name"],
			"section": data["section"],
			"connections": data["connections"].duplicate(), "visited": false,
		}

	for id in GRAPH_ORDER:
		var rt: Dictionary = _chains[id]
		var def: Dictionary = rt["def"]
		var offset: Vector2i = def.get("grid_offset", Vector2i.ZERO)
		match String(def["endpoint_mode"]):
			"poi":
				_add_chain_to_graph(rt, def["section"], offset)
				_place_poi_endpoint(rt, def)
			"connect":
				_add_chain_to_graph(rt, def["section"], offset)
				var slots: Array = rt["slots"]
				if not slots.is_empty():
					var last_c: Dictionary = slots[slots.size() - 1]
					_ensure_connection(last_c["scene_path"], def["end_scene"])
					_ensure_connection(def["end_scene"], last_c["scene_path"])
			"boss":
				# The dungeon entrance may already be in the graph (the
				# sprekken entrance is placed at its overworld cell by
				# the sprekken_approach endpoint; the brann entrance is
				# static). Only create it if missing.
				if not scene_graph.has(def["start_scene"]):
					scene_graph[def["start_scene"]] = {
						"pos": offset, "type": TYPE_DUNGEON_ENTRANCE,
						"name": def["entrance_name"], "section": def["section"],
						"connections": [], "visited": false,
					}
				_add_chain_to_graph(rt, def["section"], offset)
				var slots_b: Array = rt["slots"]
				if not slots_b.is_empty():
					var last_b: Dictionary = slots_b[slots_b.size() - 1]
					var boss_pos: Vector2i = last_b["pos"] \
						+ DIR_VECTORS[last_b["forward_exit_dir"]] + offset
					scene_graph[def["end_scene"]] = {
						"pos": boss_pos, "type": TYPE_BOSS, "name": def["boss_name"],
						"section": def["section"],
						"connections": [last_b["scene_path"]], "visited": false,
					}
					_ensure_connection(last_b["scene_path"], def["end_scene"])

	# South cliff is always visited — it's where the player spawns.
	var south_cliff_path := R + "south_cliff.tscn"
	if scene_graph.has(south_cliff_path):
		scene_graph[south_cliff_path]["visited"] = true

	EventBus.map_graph_rebuilt.emit()


## Emit every room of a chain (spine, branches, transit side clearings)
## into scene_graph. `offset` shifts map coordinates for dungeon grids so
## interiors never overlap the overworld view.
func _add_chain_to_graph(rt: Dictionary, section: String, offset: Vector2i) -> void:
	for slot in rt["slots"]:
		var bp: String = slot["scene_path"]
		var conns: Array = [slot["backward_target"]]
		if slot["forward_target"] != "":
			conns.append(slot["forward_target"])
		# The spine connects to the FIRST room of each branch (the
		# clearing for length-1 branches, the first transit buffer for
		# extended ones) — side_branches is the source of truth.
		for branch in slot.get("side_branches", []):
			if branch["rooms"].size() > 0:
				conns.append(branch["rooms"][0])
		for ws in slot["wired_sides"]:
			conns.append(ws["target"])
		scene_graph[bp] = {
			"pos": slot["pos"] + offset, "type": TYPE_BUFFER, "name": _pretty_name(bp),
			"section": section, "connections": conns, "visited": false,
		}
		_ensure_connection(slot["backward_target"], bp)
		if slot["forward_target"] != "":
			_ensure_connection(slot["forward_target"], bp)
		for ws in slot["wired_sides"]:
			_ensure_connection(ws["target"], bp)
		# Branch rooms: each links to its predecessor and successor along
		# the branch; T/X transit buffers also link their spawned side
		# clearings.
		for branch in slot.get("side_branches", []):
			var rooms: Array = branch["rooms"]
			var positions: Array = branch["positions"]
			var tsc: Array = branch.get("transit_side_clearings", [])
			for ri in rooms.size():
				var room: String = rooms[ri]
				var room_pos: Vector2i = positions[ri] + offset
				var prev_room: String = bp if ri == 0 else rooms[ri - 1]
				var room_conns: Array = [prev_room]
				if ri < rooms.size() - 1:
					room_conns.append(rooms[ri + 1])
				var my_sides: Array = tsc[ri] if ri < tsc.size() else []
				for sc_data in my_sides:
					room_conns.append(sc_data["scene"])
				var room_type: String = TYPE_CLEARING if ri == rooms.size() - 1 else TYPE_BUFFER
				scene_graph[room] = {
					"pos": room_pos, "type": room_type,
					"name": _pretty_name(room), "section": section,
					"connections": room_conns, "visited": false,
				}
				for sc_data in my_sides:
					scene_graph[sc_data["scene"]] = {
						"pos": sc_data["pos"] + offset, "type": TYPE_CLEARING,
						"name": _pretty_name(sc_data["scene"]),
						"section": section,
						"connections": [room], "visited": false,
					}


## Place a POI endpoint (and its optional paired city/gate scene) at the
## cells resolved during generation. Because resolution + reservation
## happen at generation time, this function no longer re-derives anything
## — it places exactly where the reservations say, so the map, the
## occupancy grid, and downstream chain anchors always agree.
func _place_poi_endpoint(rt: Dictionary, def: Dictionary) -> void:
	var occupied: Dictionary = _grids[def["grid"]]
	var slots: Array = rt["slots"]
	var ep: Vector2i = rt["endpoint_cell"]

	var oc: Array = []
	if not slots.is_empty():
		oc.append(slots[slots.size() - 1]["scene_path"])
	var city_path: String = String(def.get("city_path", ""))
	if city_path != "":
		oc.append(city_path)
	scene_graph[def["end_scene"]] = {
		"pos": ep, "type": def["ep_type"], "name": def["ep_name"],
		"section": def["ep_section"], "connections": oc, "visited": false,
	}
	occupied[ep] = def["end_scene"]

	if city_path == "":
		return
	var cp: Vector2i = rt["city_cell"]
	if cp == SENTINEL:
		cp = ep + def["city_offset"]
	scene_graph[city_path] = {
		"pos": cp, "type": def["city_type"], "name": def["city_name"],
		"section": def["city_section"], "connections": [def["end_scene"]],
		"visited": false,
	}
	occupied[cp] = city_path


func _ensure_connection(scene_path: String, target_path: String) -> void:
	if not scene_graph.has(scene_path):
		return
	var conns: Array = scene_graph[scene_path]["connections"]
	if target_path not in conns:
		conns.append(target_path)


func _pretty_name(scene_path: String) -> String:
	return scene_path.get_file().get_basename().replace("_", " ").capitalize()


# ============================================================================
# MAP HELPERS
# ============================================================================

func mark_visited(scene_path: String) -> void:
	if scene_graph.has(scene_path):
		scene_graph[scene_path]["visited"] = true


## Force-mark every scene visited. Debug / authoring use (All-Seer).
## NOTE: KenningManager's All-Seer handler writes visited flags directly
## instead of calling this, to avoid recursing through the emit — other
## callers should use this function.
func mark_all_visited() -> void:
	for k in scene_graph.keys():
		scene_graph[k]["visited"] = true
	EventBus.map_graph_rebuilt.emit()


func is_section_visible(section: String) -> bool:
	if section == SECTION_START:
		return true
	# Dungeon layouts only show while the player is inside that dungeon —
	# atmosphere ("the map of the depths only exists while you're in
	# them") and overworld de-cluttering in one.
	if section == SECTION_SPREKKEN:
		if in_dungeon != "sprekken":
			return false
	if section == SECTION_BRANN:
		if in_dungeon != "brann":
			return false
	if section == SECTION_MYRKFEN:
		if in_dungeon != "myrkfen":
			return false
	if section == SECTION_GARNVIK:
		if in_dungeon != "garnvik":
			return false
	var flag: String = SECTION_REVEAL_FLAGS.get(section, "")
	if flag == "":
		return false
	return GameState.has_flag(flag)


func on_scene_entered(scene_path: String) -> void:
	mark_visited(scene_path)
	var was: String = in_dungeon
	# Dungeon membership by path prefix: dungeon rooms live in folders
	# named for their dungeon. Entrance hubs are transitional and don't
	# count as inside.
	var now: String = ""
	if scene_path.find("/sprekken/") != -1:
		now = "sprekken"
	elif scene_path.find("/brann/") != -1:
		now = "brann"
	elif scene_path.find("/myrkfen/") != -1:
		now = "myrkfen"
	elif scene_path.find("/garnvik/") != -1:
		now = "garnvik"
	in_dungeon = now
	if now != was:
		if was != "":
			EventBus.exited_dungeon.emit(was, false)
		if now != "":
			EventBus.entered_dungeon.emit(now)
	if TOWN_REVEAL_TRIGGERS.has(scene_path):
		var flag: String = TOWN_REVEAL_TRIGGERS[scene_path]
		if not GameState.has_flag(flag):
			GameState.set_flag(flag)
			EventBus.map_section_revealed.emit(flag)
	QuestManager.on_scene_entered(scene_path)


# ============================================================================
# RUNTIME EXIT OVERRIDES
# ============================================================================

## Rewire a region's Exit* nodes to match the generated world. Applies
## EVERY chain in OVERRIDE_ORDER (no early return) so boundary scenes —
## an altar that ends one chain and starts two others — get all their
## overrides, with later chains winning contested exits exactly as the
## order encodes.
func apply_overrides(region_root: Node) -> void:
	var csp: String = region_root.scene_file_path
	if csp == "":
		var tr := region_root.get_tree().current_scene
		if tr:
			csp = tr.scene_file_path

	for id in OVERRIDE_ORDER:
		_apply_chain_overrides(region_root, csp, _chains[id])

	# ── Shared dungeon entrances: each entrance scene here is BOTH an
	# approach chain's endpoint AND a dungeon chain's start. The dungeon-
	# entry exit is reserved; the other three faces route back to the
	# approach chain's last buffer.
	for pair in ENTRANCE_PAIRS:
		var ap: Dictionary = _chains[pair["approach"]]
		var ap_slots: Array = ap["slots"]
		if csp != ap["def"]["end_scene"] or ap_slots.is_empty():
			continue
		var lb: Dictionary = ap_slots[ap_slots.size() - 1]
		var back_scene: String = lb["scene_path"]
		var back_marker: String = "from_" + lb["forward_exit_dir"]
		var enter_dir: String = String(_chains[pair["depths"]].get("start_dir", _chains[pair["depths"]]["def"]["start_exit_dir"]))
		for d in ["north", "south", "east", "west"]:
			if d == enter_dir:
				continue
			var ex_child: Node = region_root.get_node_or_null(NodePath("Exit" + d.capitalize()))
			if ex_child != null and "target_scene" in ex_child:
				ex_child.set_meta("pm_wired", true)
				ex_child.target_scene = back_scene
				ex_child.target_spawn_point = back_marker
				ex_child.label = "←  back to the approach"

	# ── Safety net: re-wire each shared entrance's dungeon-entry exit.
	for pair in ENTRANCE_PAIRS:
		var dg: Dictionary = _chains[pair["depths"]]
		var dg_slots: Array = dg["slots"]
		if csp == dg["def"]["start_scene"] and not dg_slots.is_empty():
			var first_d: Dictionary = dg_slots[0]
			_override_exit_by_dir(region_root, String(dg.get("start_dir", dg["def"]["start_exit_dir"])),
				first_d["scene_path"], "from_" + first_d["entry_dir"])

	# ── Dangling-exit safety net ──────────────────────────────────────
	# After every chain has wired what it knows about, any Exit* child
	# of a GENERATED scene still carrying its authored target (which is
	# an arbitrary placeholder — usually hollowmere village) would
	# teleport the player out of the generated world. Redirect all of
	# them back the way the player came. Sources this catches: the
	# second exit of the legacy two-exit clearings, junction extras
	# that got no side clearing, and ri=0 transit extras.
	_wire_dangling_exits(region_root, csp)


## Point every unwired Exit* child of a generated scene at that scene's
## own "back" target, derived from its role in the owning chain (the
## LAST chain in OVERRIDE_ORDER claiming the scene, matching the
## later-chains-win override rule). Static scenes (towns, altars,
## entrances) have no role and are left untouched — their authored
## exits are intentional.
func _wire_dangling_exits(region_root: Node, csp: String) -> void:
	var back_scene := ""
	var back_marker := "default"
	for i in range(OVERRIDE_ORDER.size() - 1, -1, -1):
		var rt: Dictionary = _chains[OVERRIDE_ORDER[i]]
		var role: Dictionary = rt["roles"].get(csp, {})
		if role.is_empty():
			continue
		var slots: Array = rt["slots"]
		match String(role["kind"]):
			"slot":
				back_scene = slots[role["i"]]["backward_target"]
			"branch_first":
				back_scene = slots[role["slot"]]["scene_path"]
			"branch_room":
				var rooms: Array = slots[role["slot"]]["side_branches"][role["branch"]]["rooms"]
				back_scene = rooms[role["ri"] - 1] if role["ri"] > 0 \
					else slots[role["slot"]]["scene_path"]
			"transit_side":
				back_scene = slots[role["slot"]]["side_branches"][role["branch"]]["rooms"][role["ti"]]
		if back_scene != "":
			break
	if back_scene == "":
		return
	for child in region_root.get_children():
		if not ("target_scene" in child):
			continue
		if not String(child.name).begins_with("Exit"):
			continue
		if child.has_meta("pm_wired"):
			continue
		child.target_scene = back_scene
		child.target_spawn_point = back_marker
		child.label = "←  back"
		child.set_meta("pm_wired", true)


## Apply one chain's overrides to a scene, dispatching on the role table
## built at generation time (O(1) lookup — replaces the old per-chain
## nested scans over slots × branches × rooms).
func _apply_chain_overrides(region_root: Node, csp: String, rt: Dictionary) -> void:
	var def: Dictionary = rt["def"]
	var slots: Array = rt["slots"]
	var role: Dictionary = rt["roles"].get(csp, {})

	if not role.is_empty():
		match String(role["kind"]):
			"slot":
				_override_exits(region_root, slots[role["i"]], slots,
					rt["index"], def["end_scene"], def["end_label"])
			"branch_first":
				# First room of a side branch: back exit toward the
				# spine; for extended branches, forward exit to room 1
				# and extra exits to per-transit side clearings.
				var slot_bf: Dictionary = slots[role["slot"]]
				var branch_bf: Dictionary = slot_bf["side_branches"][role["branch"]]
				var sd: String = branch_bf["dir"]
				_override_exit_by_dir(region_root, OPPOSITE[sd],
					slot_bf["scene_path"], "from_" + sd)
				if branch_bf["rooms"].size() >= 2:
					_override_exit_by_dir(region_root, sd,
						branch_bf["rooms"][1], "from_" + OPPOSITE[sd])
					_override_transit_extras_branch(region_root, csp, branch_bf, 0)
			"branch_room":
				# Deeper branch room: back to the previous room, forward
				# to the next (terminal clearings have no forward), plus
				# T/X extras.
				var branch_br: Dictionary = slots[role["slot"]]["side_branches"][role["branch"]]
				var rooms: Array = branch_br["rooms"]
				var ri: int = role["ri"]
				var back_dir: String = OPPOSITE[branch_br["dir"]]
				_override_exit_by_dir(region_root, back_dir,
					rooms[ri - 1], "from_" + branch_br["dir"])
				if ri < rooms.size() - 1:
					_override_exit_by_dir(region_root, branch_br["dir"],
						rooms[ri + 1], "from_" + back_dir)
				_override_transit_extras_branch(region_root, csp, branch_br, ri)
			"transit_side":
				# Clearing hanging off a T/X transit buffer: single exit
				# back to its owning transit.
				var branch_ts: Dictionary = slots[role["slot"]]["side_branches"][role["branch"]]
				var owner_room: String = branch_ts["rooms"][role["ti"]]
				_override_exit_by_dir(region_root, OPPOSITE[role["dir"]],
					owner_room, "from_" + role["dir"])
		return

	if csp == def["start_scene"] and not slots.is_empty():
		var fb: Dictionary = slots[0]
		_override_exit_by_dir(region_root, String(rt.get("start_dir", def["start_exit_dir"])),
			fb["scene_path"], "from_" + fb["entry_dir"])
		return
	if csp == def["end_scene"] and not slots.is_empty():
		# The endpoint sits one step past the chain's natural end; its
		# backward direction is the opposite of the last buffer's
		# forward direction.
		var lb: Dictionary = slots[slots.size() - 1]
		var wired: bool = _override_exit_by_dir(region_root,
			OPPOSITE[lb["forward_exit_dir"]],
			lb["scene_path"], "from_" + lb["forward_exit_dir"])
		if not wired:
			# The mountain altars use a single non-directional
			# "ExitBack" instead of Exit<Dir>. Wire it (or, failing
			# that, the first unwired Exit* child) onto the last
			# buffer — without this, the authored target sends the
			# player straight back to hollowmere village.
			var eb: Node = region_root.get_node_or_null(^"ExitBack")
			if eb == null:
				for child in region_root.get_children():
					if String(child.name).begins_with("Exit") \
							and "target_scene" in child \
							and not child.has_meta("pm_wired"):
						eb = child
						break
			if eb != null and "target_scene" in eb:
				eb.target_scene = lb["scene_path"]
				eb.target_spawn_point = "from_" + lb["forward_exit_dir"]
				eb.set_meta("pm_wired", true)


## Override the EXTRA exits on a transit buffer (beyond entry + forward).
## Each extra points at its spawned side clearing, or falls back to the
## previous room ("visually redundant but safe") when no clearing was
## spawned. `ri` is csp's index in the branch; terminal clearings no-op.
func _override_transit_extras_branch(region_root: Node, csp: String,
		branch: Dictionary, ri: int) -> void:
	var rooms: Array = branch["rooms"]
	if ri >= rooms.size() - 1:
		return   # terminal clearing has no extras
	var entry_dir: String = OPPOSITE[branch["dir"]]
	var forward_dir: String = branch["dir"]
	var tsc: Array = branch.get("transit_side_clearings", [])
	var my_sides: Array = tsc[ri] if ri < tsc.size() else []
	var dir_to_side: Dictionary = {}
	for sc_data in my_sides:
		dir_to_side[sc_data["dir"]] = sc_data["scene"]

	# For ri=0 the previous room is the spine buffer, which we can't
	# reach from here — the spine's own side exit already wires the
	# backward path, so the fallback is skipped in that case.
	var prev_room: String = "" if ri == 0 else rooms[ri - 1]

	var transit_exits: Array = _get_buffer_exits(csp)
	for ed in transit_exits:
		if ed == entry_dir or ed == forward_dir:
			continue
		if dir_to_side.has(ed):
			_override_exit_by_dir(region_root, ed, dir_to_side[ed], "default")
		elif prev_room != "":
			_override_exit_by_dir(region_root, ed, prev_room,
				"from_" + branch["dir"])


## Spine-slot override: backward, forward, side, and wired exits.
func _override_exits(region_root: Node, slot: Dictionary,
		slots: Array, index: Dictionary,
		end_scene: String, end_label: String) -> void:
	for child in region_root.get_children():
		if not ("target_scene" in child):
			continue
		var en: String = child.name
		if not en.begins_with("Exit"):
			continue
		var ed: String = en.substr(4).to_lower()
		if ed == slot["backward_exit_dir"]:
			child.set_meta("pm_wired", true)
			child.target_scene = slot["backward_target"]
			var idx: int = index[slot["scene_path"]]
			if idx > 0:
				child.target_spawn_point = "from_" + slots[idx - 1]["forward_exit_dir"]
			else:
				child.target_spawn_point = "from_" + OPPOSITE[slot["backward_exit_dir"]]
			child.label = "←  back"
		elif ed == slot["forward_exit_dir"]:
			child.set_meta("pm_wired", true)
			child.target_scene = slot["forward_target"]
			child.target_spawn_point = "from_" + OPPOSITE[slot["forward_exit_dir"]]
			if slot["forward_target"] == end_scene:
				child.label = end_label
				child.target_spawn_point = "default"
			else:
				if scene_graph.has(slot["forward_target"]):
					var ft_type: String = scene_graph[slot["forward_target"]]["type"]
					if ft_type == TYPE_CLEARING:
						child.label = "→  a quiet clearing"
						child.target_spawn_point = "default"
					else:
						if index.has(slot["forward_target"]):
							var ft_slot: Dictionary = slots[index[slot["forward_target"]]]
							child.target_spawn_point = "from_" + ft_slot["backward_exit_dir"]
							child.label = "→  toward the way out"
						else:
							child.label = "→  deeper in"
				else:
					child.label = "→  deeper in"
		else:
			var sda: Array = slot.get("side_exit_dirs", [])
			var sca: Array = slot.get("side_clearings", [])
			var wsa: Array = slot.get("wired_sides", [])
			var sidx := sda.find(ed)
			if sidx != -1 and sidx < sca.size():
				child.set_meta("pm_wired", true)
				child.target_scene = sca[sidx]
				child.target_spawn_point = "default"
				# Label from what's on the other side: a clearing is a
				# 1-room dead-end, a buffer means the branch extends.
				if sca[sidx] == end_scene:
					child.label = end_label
				elif scene_graph.has(sca[sidx]) \
						and scene_graph[sca[sidx]]["type"] == TYPE_BUFFER:
					child.label = "→  a winding path"
				else:
					child.label = "→  clearing"
				continue
			for ws in wsa:
				if ws["dir"] == ed:
					child.set_meta("pm_wired", true)
					child.target_scene = ws["target"]
					child.target_spawn_point = "from_" + OPPOSITE[ed]
					child.label = "→  a familiar path"
					break


func _override_exit_by_dir(region_root: Node, exit_dir: String,
		target_scene: String, target_marker: String) -> bool:
	var en := "Exit" + exit_dir.capitalize()
	for child in region_root.get_children():
		if child.name == en:
			child.target_scene = target_scene
			child.target_spawn_point = target_marker
			child.set_meta("pm_wired", true)
			return true
	return false
