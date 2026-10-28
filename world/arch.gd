class_name Arch
extends Node2D
## One of the four cardinal arches of the island. Presses E to activate
## as the current respawn anchor — on death, the player will respawn at
## whichever arch was most recently activated.
##
## (Full death-respawn isn't wired yet; this slice just establishes the
## mechanic. Activating the arch updates GameState.last_arch_id and emits
## arch_activated, which future systems can listen to.)
##
## Each arch has an arch_id ("south_arch", "east_arch", etc.) used to
## identify which scene to teleport to and where within it.

@export var arch_id: String = "south_arch"
@export var display_name: String = "South Arch"
## Optional first-activation dialogue (lore on first touch). Plays only
## when the player has not yet activated this arch (story flag check).
@export var first_activation_dialogue: Dialogue
## Spawn marker name (a Marker2D in this scene) where the player will
## be placed when respawning at this arch. Defaults to "default" which
## RegionRoot uses as the canonical entry point.
@export var respawn_spawn_marker: String = "default"

@onready var area: Area2D = $Area2D

var _player_in_range: Player = null
var _bob_t: float = 0.0


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_bob_t = randf() * TAU
	# Self-register with the SceneTransition's runtime arch directory.
	# NOTE: scene_file_path on `self` is "res://world/arch.tscn" (this
	# node IS the root of the arch prefab) — that's not what we want.
	# We want the path of the scene the arch was *instanced into*, which
	# is the current scene's scene_file_path.
	var containing_scene: Node = get_tree().current_scene
	if containing_scene != null and containing_scene.scene_file_path != "":
		SceneTransition.register_arch(
			arch_id, containing_scene.scene_file_path, respawn_spawn_marker
		)


func _process(delta: float) -> void:
	_bob_t += delta
	queue_redraw()
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_activate()


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_range = body
		EventBus.notify_interactable_entered()


func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		EventBus.notify_interactable_exited()


func _activate() -> void:
	var was_first_time: bool = not GameState.has_flag("arch_activated_" + arch_id)
	GameState.last_arch_id = arch_id
	GameState.set_flag("arch_activated_" + arch_id)
	EventBus.arch_activated.emit(arch_id)
	Toast.show_message("Arch awakened: %s" % display_name, Color(1.0, 0.85, 0.3))

	# Arches are the canonical "you've made progress, anchor here"
	# beats — every other respawn behavior keys off last_arch_id. Auto-
	# saving on activation guarantees the player can't lose the arch as
	# their respawn point to a hard crash or accidental quit, and gives
	# them an obvious checkpoint affordance: "I awoke the arch, my
	# progress is safe."
	SaveManager.autosave_if_active()

	if was_first_time and first_activation_dialogue:
		DialogueUI.show_dialogue(first_activation_dialogue)


# --- Placeholder visual: a real archway. Two pillars with a stone span. ---
func _draw() -> void:
	var active: bool = GameState.last_arch_id == arch_id
	var glyph_col: Color = Color(1.0, 0.85, 0.3) if active else Color(0.55, 0.55, 0.65)
	var stone: Color = Color(0.32, 0.30, 0.34)
	var stone_outline: Color = Color(0.12, 0.10, 0.14)

	# Pillar dimensions chosen so the opening is wide enough for the player
	# (~24px diameter) to plausibly stand in. Y origin is the player's feet.
	var pillar_w: float = 14.0
	var pillar_h: float = 110.0
	var opening_half: float = 26.0 # half-width of the gap between pillars
	var top_y: float = -pillar_h
	var span_h: float = 18.0

	# Left pillar
	var left_x: float = -opening_half - pillar_w
	draw_rect(Rect2(left_x, top_y, pillar_w, pillar_h), stone)
	draw_rect(Rect2(left_x, top_y, pillar_w, pillar_h), stone_outline, false, 1.5)

	# Right pillar
	var right_x: float = opening_half
	draw_rect(Rect2(right_x, top_y, pillar_w, pillar_h), stone)
	draw_rect(Rect2(right_x, top_y, pillar_w, pillar_h), stone_outline, false, 1.5)

	# Span across the top — slightly wider than the pillars for a capstone feel.
	var span_x: float = left_x - 4.0
	var span_w: float = (right_x + pillar_w + 4.0) - span_x
	draw_rect(Rect2(span_x, top_y - span_h, span_w, span_h), stone)
	draw_rect(Rect2(span_x, top_y - span_h, span_w, span_h), stone_outline, false, 1.5)

	# Activation glyph: floating diamond in the center of the opening.
	var bob: float = sin(_bob_t * 1.5) * 3.0
	var center: Vector2 = Vector2(0, top_y + pillar_h * 0.45 + bob)
	var pts := PackedVector2Array([
		center + Vector2(0, -8),
		center + Vector2(7, 0),
		center + Vector2(0, 8),
		center + Vector2(-7, 0),
	])
	draw_colored_polygon(pts, glyph_col)
	for i in 4:
		draw_line(pts[i], pts[(i + 1) % 4], Color.BLACK, 1.5)

	# Faint glow when active — a couple of larger transparent diamonds.
	if active:
		for r in [16.0, 24.0]:
			var glow_pts := PackedVector2Array([
				center + Vector2(0, -r),
				center + Vector2(r * 0.7, 0),
				center + Vector2(0, r),
				center + Vector2(-r * 0.7, 0),
			])
			draw_colored_polygon(glow_pts, Color(glyph_col.r, glyph_col.g, glyph_col.b, 0.12))

	# Name label above the span
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(-80, top_y - span_h - 8), display_name,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(1, 1, 1, 0.9))
		if _player_in_range:
			var hint: String = "[E] activate" if not active else "[E] (active)"
			draw_string(font, Vector2(-50, 28), hint,
				HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color(1.0, 0.95, 0.4))
