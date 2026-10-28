class_name Townsperson
extends Node2D
## A non-interactable background figure. Used to populate town scenes
## without adding meaningful NPCs. Drifts in slow random arcs around
## an anchor point so the player sees movement at the edges of frame.
##
## When you want a real NPC with dialogue, use NPC instead.

@export var tint: Color = Color(0.6, 0.55, 0.5)
@export var wander_radius: float = 40.0
@export var wander_speed: float = 18.0
## Sprite sheet name (without extension). If set, loads a PNG from
## the sprites/Enemies/NPCs/ directory. Sheet layout: 4 columns
## (south/west/north/east), 64×64 per frame.
@export var sprite_name: String = ""

var _anchor: Vector2
var _phase: float = 0.0
var _phase_offset_x: float = 0.0
var _phase_offset_y: float = 0.0
var _sheet_sprite: Sprite2D = null
var _last_pos: Vector2 = Vector2.ZERO

const _SHEET_COLS: int = 4
enum _FacingDir { SOUTH = 0, WEST = 1, NORTH = 2, EAST = 3 }
var _facing_dir: int = _FacingDir.SOUTH


func _ready() -> void:
	_anchor = global_position
	_last_pos = global_position
	_phase_offset_x = randf() * TAU
	_phase_offset_y = randf() * TAU

	if sprite_name != "":
		var sheet_path: String = _find_sprite(sprite_name)
		if sheet_path != "":
			var tex: Texture2D = load(sheet_path)
			if tex:
				_sheet_sprite = Sprite2D.new()
				_sheet_sprite.texture = tex
				_sheet_sprite.hframes = _SHEET_COLS
				_sheet_sprite.vframes = int(tex.get_height() / 64.0) if tex.get_height() >= 64 else 1
				_sheet_sprite.frame = 0
				add_child(_sheet_sprite)


static func _find_sprite(sname: String) -> String:
	var search_dirs: Array[String] = [
		"res://sprites/Enemies/NPCs/",
		"res://sprites/Enemies/Enemies/",
		"res://sprites/Enemies/",
		"res://sprites/",
	]
	for dir_path in search_dirs:
		var full: String = dir_path + sname + ".png"
		if ResourceLoader.exists(full):
			return full
	push_warning("Townsperson: sprite '%s' not found" % sname)
	return ""


func _process(delta: float) -> void:
	_phase += delta
	var dx := sin(_phase * 0.4 + _phase_offset_x) * wander_radius
	var dy := sin(_phase * 0.55 + _phase_offset_y) * wander_radius * 0.7
	global_position = _anchor + Vector2(dx, dy)

	# Update facing direction from drift movement
	if _sheet_sprite:
		var vel: Vector2 = global_position - _last_pos
		if vel.length_squared() > 0.1:
			if absf(vel.x) >= absf(vel.y):
				_facing_dir = _FacingDir.EAST if vel.x > 0.0 else _FacingDir.WEST
			else:
				_facing_dir = _FacingDir.SOUTH if vel.y > 0.0 else _FacingDir.NORTH
			_sheet_sprite.frame = _facing_dir
	_last_pos = global_position

	if _sheet_sprite == null:
		queue_redraw()


func _draw() -> void:
	if _sheet_sprite:
		return
	draw_rect(Rect2(-9, -13, 18, 26), tint)
	draw_rect(Rect2(-9, -13, 18, 26), Color(0, 0, 0, 0.35), false, 1.0)
