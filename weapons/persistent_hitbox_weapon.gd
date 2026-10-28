class_name PersistentHitboxWeapon
extends Weapon
## A weapon that spawns a long-lived damage zone (cone or beam) when
## fired. Designed for telegraphed AOE attacks like flamethrowers and
## charged beams — anything where the hitbox needs to persist across
## multiple frames with periodic damage application, rather than the
## single-frame swing of MeleeWeapon or the moving point of a Projectile.
##
## The zone:
##   - Attaches to the user (so it follows the user's position; if the
##     user is killed the zone is freed with them — matches how
##     MeleeSwing works).
##   - Is rotated to face `aim` at spawn time and does NOT track the
##     target afterward. The shooter commits to a direction; the player
##     can sidestep the cone/beam by reading the windup.
##   - Ticks damage every `tick_interval` for `duration` seconds.

const PERSISTENT_SCENE: PackedScene = preload("res://weapons/persistent_hitbox.tscn")

@export_group("Persistent Hitbox")
@export var shape_kind: PersistentHitbox.ShapeKind = PersistentHitbox.ShapeKind.CONE
## CONE: tip-to-edge distance. RECTANGLE: forward length. CIRCLE: disc
## radius. Also drives effective_range() so the AI engages from a
## sensible distance — for CIRCLE this means the worm wants the player
## INSIDE the disc, so min_engage_range on the enemy should be set
## low (~0) and the AI naturally walks onto the player to fire.
@export var length: float = 120.0
## CONE only — full opening angle in degrees. 60° is a reasonable
## flamethrower; 90° feels wide; 30° feels like a focused jet.
@export_range(10.0, 180.0) var cone_angle_degrees: float = 60.0
## RECTANGLE only — total width perpendicular to forward. 40px is a
## "thick beam"; 20px is a "thin laser."
@export var rect_width: float = 40.0
## How long the zone exists, in seconds.
@export var duration: float = 2.0
## Seconds between damage ticks. Lower = smoother damage, faster TTK
## for a target stuck in it; higher = chunkier, more punishment-y feel.
@export var tick_interval: float = 0.25
## Per-tick knockback applied to anything hit. Per-tick (not single
## hit) means a target stuck inside gets continually nudged out the
## back — feels like the flame is *pushing* them out, which is the
## right read for a continuous force.
@export var knockback: float = 60.0


func _init() -> void:
	super()
	if category == "weapon":
		category = "persistent"


## Approximate max distance a target inside this zone can be hit at —
## the AI uses this to decide when it's in firing range. For CONE, the
## tip-to-edge length; for RECTANGLE, the forward length. The AI's
## min_engage_range should be tuned so the enemy stays out of melee
## range while keeping the player inside the zone's sweet spot.
func effective_range() -> float:
	return length


func attack(user: Node2D, aim: Vector2) -> void:
	var zone: PersistentHitbox = PERSISTENT_SCENE.instantiate()
	var aim_n: Vector2 = aim.normalized()
	if aim_n == Vector2.ZERO:
		aim_n = Vector2.RIGHT

	# base_damage on the Weapon becomes the per-tick damage. compute_
	# outgoing_damage composes status/kenning multipliers so a buffed
	# user's persistent zone hits harder per tick.
	var effective_tick_dmg: float = compute_outgoing_damage(user)

	# Configure BEFORE add_child so _ready (which builds the polygon and
	# stores damage_info) sees final values.
	zone.shape_kind = shape_kind
	zone.length = length
	zone.cone_angle_degrees = cone_angle_degrees
	zone.rect_width = rect_width
	zone.duration = duration
	zone.tick_interval = tick_interval
	zone.damage_per_tick = effective_tick_dmg
	zone.element = int(element)
	zone.on_hit_effects = on_hit_effects
	zone.knockback = knockback
	zone.weapon_name = weapon_name
	zone.weapon_category = category
	zone.owning_team = user.team if "team" in user else "neutral"

	# Parent under the user (like MeleeSwing). The zone follows the user
	# in position but its rotation is fixed at spawn — so a moving boss
	# carrying a flamethrower forward sweeps the cone with its body.
	user.add_child(zone)
	zone.rotation = aim_n.angle()
	# Local position zero — the cone's origin sits at the user's center
	# and extends forward. Tune via cone shape (origin offset baked into
	# the polygon) if a future design needs a different attachment point.
	zone.position = Vector2.ZERO
