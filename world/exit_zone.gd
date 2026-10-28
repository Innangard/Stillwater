class_name ExitZone
extends Area2D
## Place these in scenes where the player can leave to another scene.
## When the player overlaps, fades + transitions to `target_scene`,
## spawning at the named `target_spawn_point` in that scene.
##
## Author with the export fields in the inspector — no code needed.

## The scene to load when triggered.
@export_file("*.tscn") var target_scene: String = ""

## Name of a Marker2D in the destination scene (in group "spawn_points").
## Leave empty to use the destination's default spawn.
@export var target_spawn_point: String = ""

## Optional label drawn above the zone for debugging / map sense
## (e.g., "to Wickbarrow Village →").
@export var label: String = ""

## Tint of the placeholder visual.
@export var tint: Color = Color(0.6, 0.5, 0.8, 0.4)

## Per-instance zone size. Defaults are good for vertical (east/west) exits;
## override to e.g. Vector2(192, 48) for a horizontal (north/south) exit.
@export var zone_size: Vector2 = Vector2(48, 96)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # player body
	body_entered.connect(_on_body_entered)
	# Resize this instance's collision shape to match zone_size. We have to
	# clone the shape resource so changing it doesn't affect other ExitZones
	# that share the same .tscn.
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var shape := RectangleShape2D.new()
			shape.size = zone_size
			child.shape = shape
			break
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	if target_scene == "":
		push_warning("ExitZone has no target_scene set: %s" % name)
		return
	SceneTransition.go_to(target_scene, target_spawn_point)

# --- Placeholder visual: tinted box + arrow + label ---
func _draw() -> void:
	# Find our own collision shape to size the rect to.
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var rect: RectangleShape2D = child.shape
			var size: Vector2 = rect.size
			var pos: Vector2 = -size * 0.5
			draw_rect(Rect2(pos, size), tint, true)
			draw_rect(Rect2(pos, size), Color(tint.r, tint.g, tint.b, 0.9), false, 2.0)
			break
	if label != "":
		var font := ThemeDB.fallback_font
		if font:
			draw_string(font, Vector2(-100, -8), label,
				HORIZONTAL_ALIGNMENT_CENTER, 200, 12, Color(1, 1, 1, 0.85))
