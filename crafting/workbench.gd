class_name Workbench
extends Node2D
## A crafting station placed in the world. Press [E] when nearby to open
## its crafting UI. Each Workbench has its own recipes array, so a forge
## in one town can have different recipes than an altar in another.
##
## The UI itself is the autoloaded CraftingUI — workbenches just tell it
## "open with these recipes."

@export var station_name: String = "Workbench"
## Recipes available at this station. Authored as .tres files in
## crafting/instances/ and dragged in via the inspector.
@export var recipes: Array[Recipe] = []
## Color used for the placeholder visual.
@export var tint: Color = Color(0.85, 0.7, 0.45)
@export var icon: Texture2D = null

@onready var area: Area2D = $Area2D

var _player_in_range: Player = null


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	queue_redraw()
	if _player_in_range and Input.is_action_just_pressed("interact"):
		CraftingUI.open(self)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_range = body
		EventBus.notify_interactable_entered()


func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		EventBus.notify_interactable_exited()


# --- Placeholder visual: tinted square with name + [E] prompt ---
func _draw() -> void:
	
	# --- Draw Graphic ---
	if icon:
		# Set your desired scale here (0.5 means 50% of the original size)
		var scale_factor: float = 1
		
		# Get the size and apply the scale
		var scaled_size = icon.get_size() * scale_factor
		
		# Center it using the scaled size, then add the bob offset
		var draw_pos = -scaled_size
		
		# Draw it using a Rect2 (position + size)
		draw_texture_rect(icon, Rect2(draw_pos, scaled_size), false)
	else: # Body
		draw_rect(Rect2(-20, -20, 40, 40), tint)
		draw_rect(Rect2(-20, -20, 40, 40), Color.BLACK, false, 2.0)

	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(-80, -28), station_name,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(1, 1, 1, 0.9))
		if _player_in_range:
			draw_string(font, Vector2(-15, 38), "[E]",
				HORIZONTAL_ALIGNMENT_CENTER, 30, 14, Color(1.0, 0.95, 0.4))
