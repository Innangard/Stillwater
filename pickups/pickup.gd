class_name Pickup
extends Node2D
## A pickup in the world. Set ONE of: item, weapon, or currency_amount.
##
## - Item set         → auto-collects on touch, goes to inventory
## - Weapon set       → press [E] to equip (avoids accidental swap)
## - currency_amount  → auto-collects on touch, adds to GameState
##
## The visual auto-themes from what it carries (item color, element color
## for weapons, gold for currency).

@export var item: Item = null
@export var weapon: Weapon = null
@export var currency_amount: int = 0
@export var currency_icon: Texture2D = null
## If true, this pickup despawns when re-entered if already collected
## this run. Used for AUTHORED pickups in scene files — set true on
## any reagent or special item placed at design time. Leave false for
## drops spawned at runtime (e.g., enemy loot) since those have no
## stable identity and shouldn't re-appear anyway.
@export var persistent_per_run: bool = false

@onready var area: Area2D = $Area2D

var _player_in_range: Player = null
var _bob_t: float = 0.0


func _ready() -> void:
	# Runtime-spawned pickups (from ClearingLootSpawner) carry a stable
	# identity in meta so consumption tracking works across scene re-entry.
	# Check that identity first; fall back to the node-path-based identity
	# for hand-placed pickups.
	if persistent_per_run:
		if has_meta("loot_identity"):
			if RunState.consumed_node_paths.has(get_meta("loot_identity")):
				queue_free()
				return
		elif RunState.is_node_consumed(self):
			queue_free()
			return

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_bob_t = randf() * TAU


func _process(delta: float) -> void:
	_bob_t += delta
	queue_redraw()
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_collect(_player_in_range)


func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	# Track the player so the [E] hint will render correctly for any
	# future pickup type that gates collection behind interaction.
	# Previously _player_in_range was declared but never assigned —
	# _process's interact check was dead code.
	_player_in_range = body as Player
	if _requires_interact():
		# Press-E pickups participate in the global interactable counter
		# so the player's E-key fallback (open inventory when nothing
		# is in range) works correctly. Auto-collect pickups skip this:
		# they free themselves the same frame, and notify_exited wouldn't
		# fire on a freed node, which would leak the counter.
		EventBus.notify_interactable_entered()
		return
	_collect(body)


func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if _requires_interact():
			EventBus.notify_interactable_exited()


# Kept for forward compatibility — if a future pickup needs to require
# interact (e.g., a chest, a story-flagged item), set this to true on
# the instance and add the gating logic in _on_body_entered.
func _requires_interact() -> bool:
	return false


func _collect(_player: Player) -> void:
	# `_player` is unused right now but kept in the signature so future
	# pickup behaviors (e.g., directly buffing the collector, or running
	# a quick "you found X!" effect from the player's position) have it
	# available without changing the signature later.
	if currency_amount > 0:
		GameState.add_currency(currency_amount)

	if item:
		# Items, armor, AND weapons all flow through inventory now.
		# The "weapon" export below is only for backward-compatibility
		# with scenes that haven't been re-saved.
		RunState.add_to_inventory(item)

	if weapon:
		# Weapons are now Items — they go to inventory like everything else.
		# Equip from the inventory UI (double-click or drag-and-drop).
		RunState.add_to_inventory(weapon)

	# Mark this pickup as consumed for the current run so it won't
	# reappear when the scene reloads. Runtime-spawned pickups use
	# the stable loot_identity; hand-placed use node path.
	if persistent_per_run:
		if has_meta("loot_identity"):
			RunState.consumed_node_paths[get_meta("loot_identity")] = true
		else:
			RunState.mark_node_consumed(self)

	queue_free()


# --- Placeholder visual ---
func _draw() -> void:
	var bob: float = sin(_bob_t * 3.0) * 4.0
	var bob_offset := Vector2(0, bob)

	var col: Color
	var _label: String = ""  # kept for future label drawing
	var icon: Texture2D = null

	if currency_amount > 0:
		col = Color(1.0, 0.85, 0.2)
		_label = "%d" % currency_amount
		if currency_icon != null:
			icon = currency_icon
	elif item:
		col = item.placeholder_color
		_label = item.item_name
		# Safely check if the item resource has an icon property
		if "icon" in item:
			icon = item.icon
	elif weapon:
		col = Weapon.element_color(weapon.element)
		_label = weapon.weapon_name
		# Safely check if the weapon resource has an icon property
		if "icon" in weapon:
			icon = weapon.icon
	else:
		col = Color.MAGENTA # missing content -> obvious magenta
		_label = "(empty)"

	# --- Draw Graphic ---
	if icon:
		# Set your desired scale here (0.5 means 50% of the original size)
		var scale_factor: float = 0.4 
		
		# Get the size and apply the scale
		var scaled_size = icon.get_size() * scale_factor
		
		# Center it using the scaled size, then add the bob offset
		var draw_pos = -scaled_size / 2.0 + bob_offset
		
		# Draw it using a Rect2 (position + size)
		draw_texture_rect(icon, Rect2(draw_pos, scaled_size), false)
	else:
		# Fallback: Diamond
		var pts := PackedVector2Array([
			Vector2(0, -10) + bob_offset,
			Vector2(8,  0 ) + bob_offset,
			Vector2(0, 10 ) + bob_offset,
			Vector2(-8, 0 ) + bob_offset,
		])
		draw_colored_polygon(pts, col)
		for i in 4:
			draw_line(pts[i], pts[(i + 1) % 4], Color.BLACK, 1.5)

	# --- Draw Text ---
	var font := ThemeDB.fallback_font
	if _player_in_range and font and _label != "":
		var font_size: int = 12
		var label_pos := Vector2(-70, -20) + bob_offset
		for ox in [-1, 0, 1]:
			for oy in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				draw_string(font, label_pos + Vector2(ox, oy), _label,
					HORIZONTAL_ALIGNMENT_CENTER,
					140, font_size, Color(0.0, 0.0, 0.0, 0.8))
		draw_string(font, label_pos, _label,
			HORIZONTAL_ALIGNMENT_CENTER,
			140, font_size, Color(1, 1, 1, 0.95))
	
	# [E] interact prompt
	if _player_in_range and font:
		draw_string(font, Vector2(-15, 28) + bob_offset, "[E]",
			HORIZONTAL_ALIGNMENT_CENTER, 30, 14, Color(1.0, 0.95, 0.4))
