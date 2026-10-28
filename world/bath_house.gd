class_name BathHouse
extends Node2D
## Press E to bathe. Spends `cost` souls, applies a smell-block effect
## (smell can't rise above `block_threshold` for `block_duration` seconds)
## and immediately reduces current smell to that ceiling if it was higher.
##
## The bath house is fiction-flavor on top of RunState.grant_smell_block —
## any future "hide your scent" item or location can call the same API.

@export var display_name: String = "Bath House"
@export var cost: int = 8
## Fraction of max_smell. 0.15 = held below 15%.
@export_range(0.0, 1.0) var block_threshold: float = 0.15
## Seconds the block lasts.
@export var block_duration: float = 300.0
@export var tint: Color = Color(0.45, 0.65, 0.78)

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
		_try_bathe()


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_range = body
		EventBus.notify_interactable_entered()

func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		EventBus.notify_interactable_exited()


func _try_bathe() -> void:
	if GameState.soul_currency < cost:
		Toast.show_message("Not enough souls (%d / %d)" % [GameState.soul_currency, cost],
			Color(0.9, 0.4, 0.4))
		return
	if not GameState.spend_currency(cost):
		return
	RunState.grant_smell_block(block_threshold, block_duration)
	Toast.show_message("Bathed. The dead won't smell you for %ds." % int(block_duration),
		Color(0.55, 0.8, 0.95))


func _draw() -> void:
	# Building footprint
	draw_rect(Rect2(-46, -52, 92, 64), Color(0.32, 0.28, 0.24))
	draw_rect(Rect2(-46, -52, 92, 64), Color.BLACK, false, 2.0)
	# Roof — simple darker triangle on top
	var roof := PackedVector2Array([
		Vector2(-52, -52), Vector2(0, -78), Vector2(52, -52),
	])
	draw_colored_polygon(roof, Color(0.22, 0.18, 0.16))
	# Steam plume — bobbing translucent puffs above the roof
	for i in 3:
		var bob: float = sin((_bob_t + i * 0.7) * 1.5) * 3.0
		var center := Vector2(-12 + i * 12, -94 + bob)
		draw_circle(center, 7.0, Color(0.85, 0.92, 0.95, 0.55))
	# Door
	draw_rect(Rect2(-8, -16, 16, 28), Color(0.18, 0.14, 0.12))
	# Sign
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(-80, -100), display_name,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color(1, 1, 1, 0.9))
		var price_str := "%d souls" % cost
		draw_string(font, Vector2(-80, 28), price_str,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(0.85, 0.85, 0.85))
		if _player_in_range:
			draw_string(font, Vector2(-50, 46), "[E] bathe",
				HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color(1.0, 0.95, 0.4))
