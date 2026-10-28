class_name NPC
extends Node2D
## A non-player character. Press E nearby to start dialogue.
##
## Place in any scene, set:
##   - npc_name: shown in interaction prompt and dialogue speaker
##   - dialogue: a Dialogue Resource (.tres)
##   - tint: placeholder visual color
##
## NPCs can optionally house a crafting station. Set station_name and
## populate the recipes array to make a "Craft" button appear in the
## dialogue box from the very first line (Terraria-style). The player
## can browse the shop / craft at any time without sitting through all
## the dialogue.

@export var npc_name: String = "Stranger"
@export var dialogue: Dialogue
@export var tint: Color = Color(0.7, 0.7, 0.85)
## Sprite sheet name (without extension). If set, loads a PNG from
## res://sprites/Enemies/NPCs/<sprite_name>.png as a Sprite2D.
## Sheet layout: 4 columns (south/west/north/east), 64×64 per frame.
@export var sprite_name: String = ""

@export_group("Crafting Station")
## If non-empty, the dialogue box shows a craft button labeled with this.
@export var station_name: String = ""
## Recipes available when the player clicks the craft button.
@export var recipes: Array[Recipe] = []

@onready var area: Area2D = $Area2D

var _player_in_range: Player = null
var _sheet_sprite: Sprite2D = null
var _idle_drift_timer: float = 3.0

const _NPC_SHEET_COLS: int = 4
enum _FacingDir { SOUTH = 0, WEST = 1, NORTH = 2, EAST = 3 }


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	# Load sprite sheet if sprite_name is set
	if sprite_name != "":
		var sheet_path: String = _find_npc_sprite(sprite_name)
		if sheet_path != "":
			var tex: Texture2D = load(sheet_path)
			if tex:
				_sheet_sprite = Sprite2D.new()
				_sheet_sprite.texture = tex
				var tex_h: int = tex.get_height()
				_sheet_sprite.hframes = _NPC_SHEET_COLS
				_sheet_sprite.vframes = int(tex_h / 64.0) if tex_h >= 64 else 1
				_sheet_sprite.frame = 0  # south-facing default
				add_child(_sheet_sprite)


static func _find_npc_sprite(sname: String) -> String:
	var search_dirs: Array[String] = [
		"res://sprites/Enemies/NPCs/",
		"res://sprites/Enemies/",
		"res://sprites/",
	]
	for dir_path in search_dirs:
		var full: String = dir_path + sname + ".png"
		if ResourceLoader.exists(full):
			return full
	push_warning("NPC SpriteSheet: '%s' not found" % sname)
	return ""


func _process(_delta: float) -> void:
	queue_redraw()
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_open_dialogue()
	# Face toward player when they're nearby
	if _sheet_sprite and _player_in_range:
		var dir: Vector2 = _player_in_range.global_position - global_position
		var facing: int
		if absf(dir.x) >= absf(dir.y):
			facing = _FacingDir.EAST if dir.x > 0.0 else _FacingDir.WEST
		else:
			facing = _FacingDir.SOUTH if dir.y > 0.0 else _FacingDir.NORTH
		_sheet_sprite.frame = facing
	elif _sheet_sprite and not _player_in_range:
		# Slow idle facing drift — occasionally glance a different
		# direction so towns feel inhabited, not frozen.
		_idle_drift_timer -= _delta
		if _idle_drift_timer <= 0.0:
			_idle_drift_timer = 2.5 + randf() * 4.0  # 2.5–6.5s between shifts
			var new_facing: int = randi() % 4
			_sheet_sprite.frame = new_facing


func _open_dialogue() -> void:
	# Always open dialogue UI. If we have no dialogue lines AND no station,
	# there's nothing to show — skip.
	var has_dialogue: bool = dialogue != null and not dialogue.lines.is_empty()
	var has_station: bool = station_name != "" and not recipes.is_empty()
	if not has_dialogue and not has_station:
		return
	DialogueUI.show_dialogue(dialogue, station_name if has_station else "", recipes)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_range = body
		EventBus.notify_interactable_entered()


func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		EventBus.notify_interactable_exited()


# --- Visual: sprite sheet or placeholder square, name overhead, [E] prompt ---
func _draw() -> void:
	# Placeholder body only if no sprite sheet
	if _sheet_sprite == null:
		draw_rect(Rect2(-12, -16, 24, 32), tint)
		draw_rect(Rect2(-12, -16, 24, 32), Color.BLACK, false, 1.5)

	var font := ThemeDB.fallback_font
	if font:
		var name_y: float = -26.0 if _sheet_sprite == null else -38.0
		draw_string(font, Vector2(-80, name_y), npc_name,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(1, 1, 1, 0.9))
		if _player_in_range:
			var prompt_y: float = 32.0 if _sheet_sprite == null else 40.0
			draw_string(font, Vector2(-15, prompt_y), "[E]",
				HORIZONTAL_ALIGNMENT_CENTER, 30, 14, Color(1.0, 0.95, 0.4))
