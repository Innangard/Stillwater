class_name ShieldZone
extends Area2D
## The runtime defensive zone spawned in front of the player while a
## ShieldWeapon is raised. Detects enemy hitboxes via area_entered
## (collision_mask = 64, the enemy-source damage layer). Two distinct
## behaviors:
##
##   - On entry, if the entering hitbox belongs to a Projectile: the
##     entire projectile is queue_free'd, removing it from play.
##
##   - The player's _on_hit_received calls is_blocking_hitbox(source)
##     when a hit lands on the player's hurtbox. The shield reports
##     whether that hitbox is currently overlapping the shield zone,
##     and the player applies its damage-reduction multiplier.
##
## Why use get_overlapping_areas() rather than tracking entries in a
## set? Godot doesn't guarantee signal-emission order between sibling
## Area2Ds detecting the same entering area in the same physics frame.
## If a wide melee hitbox appears at instantiation overlapping both
## shield AND player hurtbox simultaneously, the hurtbox's hit_received
## could fire BEFORE the shield's area_entered — at which point a set
## populated from area_entered would be empty when queried.
##
## get_overlapping_areas() doesn't have this problem: the overlap list
## is computed atomically by the physics engine before any signals
## fire. Whichever area's signal fires first, the shield's overlap
## list already reflects the current physics state. The query is
## order-independent.
##
## The zone itself is positioned and rotated each frame to point in
## the player's aim direction at `block_distance` away. Custom _draw
## renders an outlined rectangle so the player sees what they're
## blocking with.

## Reference to the ShieldWeapon resource this zone was spawned for.
## The zone reads block_arc_size and block_distance from the weapon
## (not duplicated as zone-level exports) so a single zone scene
## works for every shield variant the game might ship.
var shield_weapon: ShieldWeapon = null

## The player (or other actor) holding this shield. Used to read
## aim_direction each frame for positioning. Set by the spawner
## immediately after instantiation, before add_child, so _ready
## already has it.
var owner_actor: Node2D = null

# ============================================================================

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if shield_weapon == null:
		push_error("ShieldZone spawned without shield_weapon set. " +
			"Set shield_weapon before add_child.")
		return
	# Size the collision shape to the weapon's block_arc_size. Local-
	# origin centered so the rotation pivot is the rectangle's center.
	var shape := RectangleShape2D.new()
	shape.size = shield_weapon.block_arc_size
	_collision.shape = shape

	# Catch enemy hitboxes only. The shield doesn't get caught itself
	# (collision_layer = 0, monitorable = false) — it's a one-way
	# detector. Layer 64 is the enemy-source damage layer that every
	# enemy hitbox (melee, projectile, telegraphed AOE) uses.
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 64

	area_entered.connect(_on_area_entered)


func _process(_delta: float) -> void:
	if owner_actor == null or not is_instance_valid(owner_actor):
		return
	# Position the collision shape at the block_distance offset along
	# the aim direction. We update each frame so the shield turns
	# with the player's aim — the player can rotate to face new
	# threats without lowering the shield.
	#
	# The shield_zone itself stays at the player's origin (it's a
	# child of the player); only the CollisionShape2D moves. This
	# keeps signal scoping simple — area_entered fires on the
	# ShieldZone Area2D regardless of where its shape sits.
	var aim: Vector2 = owner_actor.aim_direction if "aim_direction" in owner_actor else Vector2.RIGHT
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	rotation = aim.angle()
	_collision.position = Vector2(shield_weapon.block_distance, 0)
	# CollisionShape2D rotation = 0 (in zone local space); the zone
	# itself is rotated, so the shape inherits the rotation. The
	# shape's local x-axis is now aligned with the aim direction,
	# meaning block_arc_size.x is "thickness" and .y is "breadth".
	queue_redraw()


# ============================================================================
# DETECTION
# ============================================================================

## Projectile destruction handler. Fires when an enemy hitbox enters
## the shield zone. If the hitbox is the child of a Projectile node,
## the projectile is queue_freed (removing both it AND its child
## hitbox from play). Other hitbox sources (melee swing hitboxes,
## persistent AOE hitboxes) are NOT handled here — the player's
## _on_hit_received queries is_blocking_hitbox to apply the damage
## reduction at consume-time.
func _on_area_entered(area: Area2D) -> void:
	if not (area is HitboxComponent):
		return
	var hitbox: HitboxComponent = area
	# Player-team hitboxes don't get blocked by the player's own
	# shield (defensive guard — collision_mask = 64 already excludes
	# them, but the team check is cheaper than debugging if a future
	# hitbox is misconfigured).
	if hitbox.owning_team != "enemy":
		return
	var parent: Node = hitbox.get_parent()
	if parent is Projectile:
		parent.queue_free()


## Returns true if the given hitbox is currently overlapping this
## shield zone. The player calls this from _on_hit_received with
## the `source` parameter (the hitbox that just hit them) to decide
## whether to apply the shield's damage-reduction multiplier.
##
## Uses get_overlapping_areas() rather than a tracked set so the query
## is reliable regardless of signal-emission order — the physics
## engine populates the overlap list atomically before any area
## signals fire, so the list reflects the current overlap state at
## the moment of any handler running.
func is_blocking_hitbox(hitbox: HitboxComponent) -> bool:
	if not is_instance_valid(hitbox):
		return false
	return get_overlapping_areas().has(hitbox)


# ============================================================================
# DRAW
# ============================================================================

func _draw() -> void:
	if shield_weapon == null:
		return
	# Rectangle outline + translucent fill, drawn in the shield's
	# local space. The rectangle's center sits at (block_distance, 0),
	# matching where the CollisionShape2D is positioned. Since the
	# zone's `rotation` is set to face the aim direction, the
	# rectangle ends up oriented in world space too.
	var size: Vector2 = shield_weapon.block_arc_size
	var center: Vector2 = Vector2(shield_weapon.block_distance, 0)
	var top_left: Vector2 = center - size * 0.5
	var rect: Rect2 = Rect2(top_left, size)

	var fill: Color = Color(0.78, 0.82, 0.90, 0.30)
	var outline: Color = Color(0.92, 0.95, 0.98, 0.85)
	draw_rect(rect, fill, true)
	draw_rect(rect, outline, false, 2.0)
