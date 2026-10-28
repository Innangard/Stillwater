class_name Passage
extends Node2D
## A one-way scene transition interactable. Visually similar to an
## Arch — two pillars with a glowing opening — but mechanically just
## a portal: press E to step through, which calls SceneTransition.go_to
## the configured target scene. No respawn-anchor behavior, no story
## flags, no story_flag_set side effects (unless `completion_flag` is
## set, in which case stepping through marks that flag once).
##
## Used by the tutorial (Ginnungagap → south_cliff) and reserved for
## any future one-time gates that aren't proper Arches. If a passage
## *should* be a respawn anchor too, use the Arch class instead — this
## is the lighter-weight cousin.
##
## Drawing matches the Arch's silhouette so the player reads the
## affordance the same way ("two pillars with a glowing gap = walk
## through to leave"). The glow color is `passage_color` rather than
## the Arch's gold-or-grey — by default an ethereal teal, suitable
## for the void-between-worlds setting; per-instance overrides let
## a future Muspell-tunnel passage glow ember-orange.

@export_file("*.tscn") var target_scene: String = ""

## Spawn marker name in the target scene where the player will appear.
## Defaults to "default" — RegionRoot's canonical entry point.
@export var target_spawn_marker: String = "default"

## Optional story flag set when the player walks through. The tutorial
## passage uses this to mark `tutorial_completed`, so subsequent New
## Game flows or save-loads can detect that the player has already
## seen the introductory scene. Leave empty to skip flag-setting
## entirely — the passage just transitions without recording anything.
@export var completion_flag: String = ""

## Visual tint of the glowing gap between the pillars. Defaults to a
## pale ethereal teal that reads as "the void." Override per-instance
## for differently-themed passages.
@export var passage_color: Color = Color(0.78, 0.92, 0.95, 1.0)

## Label that appears above the passage when the player is in range,
## prompting interaction. Defaults to a generic "step through" — the
## tutorial overrides this with explicit hint text.
@export var prompt_text: String = "Press [E] to step through"

## Optional closing-lore narration that plays in the middle of the
## transition. If non-empty, the Passage uses SceneTransition's
## go_to_with_lore (fade to black → lore in → hold → lore out → swap
## scene → fade in new scene). If empty, the Passage uses the normal
## go_to (just a fade-out / fade-in around the scene swap, no lore).
##
## Use for passages that have a narrative bookend — the Ginnungagap
## exit reads its closing lore here. Leave empty for normal one-way
## doors with no story beat.
@export_multiline var closing_lore_text: String = ""


# ============================================================================

@onready var area: Area2D = $Area2D

var _player_in_range: Player = null
var _bob_t: float = 0.0


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_bob_t = randf() * TAU


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
	# Record the completion flag if configured. We set BEFORE the
	# scene transition because change_scene_to_file destroys this
	# node, and any deferred call would arrive after the new scene's
	# nodes are alive — too late for the flag to influence the
	# new scene's _ready() logic if it ever needs to.
	if completion_flag != "":
		GameState.set_flag(completion_flag)
	# Notify listeners that the player just left this interactable so
	# any HUD prompt disappears cleanly (otherwise the prompt might
	# persist on the loading screen).
	EventBus.notify_interactable_exited()
	# Choose transition style: with-lore plays a narrated beat in the
	# middle of the fade, plain go_to is a quick swap. Per-instance
	# selection so the same Passage scene can be used for both
	# narrated and silent transitions.
	if closing_lore_text != "":
		SceneTransition.go_to_with_lore(target_scene, target_spawn_marker, closing_lore_text)
	else:
		SceneTransition.go_to(target_scene, target_spawn_marker)


# ============================================================================
# DRAW
# ============================================================================

func _draw() -> void:
	# Same general silhouette as Arch but the glow is per-instance.
	# Pillar dimensions match Arch so the player's eye recognizes the
	# affordance regardless of context.
	var pillar_w: float = 14.0
	var pillar_h: float = 110.0
	var opening_half: float = 26.0
	var top_y: float = -pillar_h
	var span_h: float = 18.0

	var stone: Color = Color(0.18, 0.20, 0.26)
	var stone_outline: Color = Color(0.06, 0.08, 0.12)

	# Left pillar
	var left_x: float = -opening_half - pillar_w
	draw_rect(Rect2(left_x, top_y, pillar_w, pillar_h), stone)
	draw_rect(Rect2(left_x, top_y, pillar_w, pillar_h), stone_outline, false, 1.5)

	# Right pillar
	var right_x: float = opening_half
	draw_rect(Rect2(right_x, top_y, pillar_w, pillar_h), stone)
	draw_rect(Rect2(right_x, top_y, pillar_w, pillar_h), stone_outline, false, 1.5)

	# Top span
	var span_x: float = -opening_half - pillar_w
	var span_w: float = (opening_half + pillar_w) * 2.0
	draw_rect(Rect2(span_x, top_y - span_h, span_w, span_h), stone)
	draw_rect(Rect2(span_x, top_y - span_h, span_w, span_h), stone_outline, false, 1.5)

	# The glowing opening — a soft pulsing fill in passage_color.
	var pulse: float = 0.55 + 0.25 * sin(_bob_t * 2.0)
	var glow_col: Color = passage_color
	glow_col.a = pulse
	# Inner core (brighter)
	draw_rect(Rect2(-opening_half, top_y + 4, opening_half * 2.0, pillar_h - 8), glow_col)
	# Wisp particles inside the opening — three small circles bobbing
	# vertically out of phase to suggest motion
	for i in range(3):
		var t: float = _bob_t * 0.8 + i * (TAU / 3.0)
		var wy: float = top_y + 20.0 + fmod(t * 12.0, pillar_h - 40)
		var wx: float = sin(t * 0.6) * (opening_half * 0.6)
		var wc: Color = passage_color
		wc.a = 0.75
		draw_circle(Vector2(wx, -wy + top_y), 3.0, wc)

	# Prompt label appears above the passage when the player is in
	# range — draws here rather than as a Label child so it follows
	# the passage's coordinate system and we don't need to wire
	# visibility manually.
	if _player_in_range:
		var prompt_y: float = top_y - span_h - 22.0
		var font := ThemeDB.fallback_font
		var font_size: int = 14
		var size: Vector2 = font.get_string_size(prompt_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, Vector2(-size.x * 0.5, prompt_y), prompt_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
			Color(0.95, 0.96, 0.98, 0.95))
