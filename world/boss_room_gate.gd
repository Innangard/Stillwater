class_name BossRoomGate
extends Node2D
## Placed at the center of a boss room. Spawns a Passage (transport
## arch) that takes the player to the dungeon entrance scene when the
## boss dies. On subsequent runs where the boss is already dead, the
## Passage appears immediately on scene load.
##
## The Passage is the same prefab used in the Ginnungagap tutorial —
## two stone pillars with a glowing opening, press [E] to step through.
## Its visual color can be overridden per-instance so each dungeon's
## portal reads with the right thematic tint.

## The boss_id that GameState.is_boss_dead checks. Must match the
## boss_id export on the boss entity in this room.
@export var boss_id: String = ""

## Scene the Passage teleports to (the dungeon entrance scene).
@export_file("*.tscn") var target_scene: String = ""

## Spawn marker in the target scene. Defaults to "default".
@export var target_spawn_marker: String = "default"

## Visual tint of the passage glow. Defaults to the same ethereal
## teal as the tutorial passage; override per-instance for themed
## dungeons (ember-orange for Brann, sickly green for Myrkfen, etc).
@export var passage_color: Color = Color(0.78, 0.92, 0.95, 1.0)

## Prompt shown when the player stands in the passage.
@export var prompt_text: String = "Press [E] to leave"

const PASSAGE_SCENE: PackedScene = preload("res://world/passage.tscn")

var _passage_spawned: bool = false


func _ready() -> void:
	# If the boss is already dead (killed in a prior run), spawn the
	# passage immediately so the room is navigable from the start.
	if boss_id != "" and GameState.is_boss_dead(boss_id):
		_spawn_passage()
		return

	# Otherwise listen for the boss to die during this visit.
	EventBus.boss_defeated.connect(_on_boss_defeated)


func _on_boss_defeated(_boss_name: String) -> void:
	# There is exactly one boss per boss room, so any boss_defeated
	# signal while this node is alive means OUR boss just died.
	_spawn_passage()


func _spawn_passage() -> void:
	if _passage_spawned:
		return
	_passage_spawned = true

	var passage: Passage = PASSAGE_SCENE.instantiate()
	passage.target_scene = target_scene
	passage.target_spawn_marker = target_spawn_marker
	passage.passage_color = passage_color
	passage.prompt_text = prompt_text
	passage.position = Vector2.ZERO  # gate node is already at center
	add_child(passage)
