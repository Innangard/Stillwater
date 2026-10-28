class_name ExplodingProjectile
extends Projectile
## A projectile that explodes into smaller child projectiles when its
## lifetime ends — but NOT when it hits something. The design tradeoff:
##   - Walk-into-it: take the primary damage, prevent the explosion.
##   - Dodge-and-stay-clear: avoid primary damage but the shrapnel still
##     hits anyone near the impact point.
## This rewards the player for tracking where the pod will *land*, not
## just where the pod *is*. A telegraphed AOE attack with a real choice.
##
## Extends Projectile so the base movement / piercing / wall-stop /
## team-filtering logic is inherited unchanged. We only customize the
## "lifetime hit zero" branch to fire the explosion.

@export_group("Explosion")
## The scene spawned for each shrapnel piece. Usually the standard
## projectile.tscn — anything that responds to direction/speed/lifetime/
## damage/owning_team will work.
@export var child_projectile_scene: PackedScene
## How many shrapnel pieces spawn. Evenly distributed around the
## explosion center using `spread_degrees`.
@export_range(1, 24) var child_count: int = 4
## Travel speed of each shrapnel. Lower = wider danger zone over time;
## higher = quick punish that's easier to outrun.
@export var child_speed: float = 280.0
## Lifetime of each shrapnel. child_speed × child_lifetime = max
## travel distance — keep this small (160-200px) for a contained
## explosion, larger for a sweeping area-denial pulse.
@export var child_lifetime: float = 0.6
## Per-shard damage multiplier vs the parent pod's damage. <1.0 means
## shrapnel hits softer than the primary; >1.0 makes the explosion
## the real threat. 0.7 feels right at low difficulty.
@export var child_damage_multiplier: float = 0.7
## How the shrapnel is distributed. 360° = full ring (cardinal-equivalent
## for child_count=4). 180° = forward fan. Use 360° unless designing
## an explicitly directional burst.
@export_range(1.0, 360.0) var child_spread_degrees: float = 360.0
## Knockback on each child hit. Lower than the parent's by default
## since each shard is a smaller projectile.
@export var child_knockback: float = 80.0
## Visual shape for child projectiles (default TEARDROP = 4).
var child_projectile_visual: int = 4


func _physics_process(delta: float) -> void:
	# Reimplement the parent's movement/lifetime instead of calling
	# super(): the only thing we change is the lifetime-end branch
	# (explode + free, rather than just free), and intercepting the
	# base behavior wholesale is clearer than calling super and then
	# trying to know "did super queue_free us this frame?"
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		_explode()
		queue_free()


## Spawn `child_count` projectiles evenly distributed around our
## current position. Each child inherits team and damage_info (so
## status applications like burn propagate to the shrapnel), with a
## damage multiplier applied.
func _explode() -> void:
	if child_projectile_scene == null:
		return
	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return

	var child_dmg: float = damage * child_damage_multiplier
	var spread_rad: float = deg_to_rad(child_spread_degrees)
	# For a full 360° spread, distribute evenly across TAU and don't
	# duplicate the endpoint at 0/360. For partial spreads, lerp from
	# -spread/2 to +spread/2 across child_count points.
	var is_full_ring: bool = child_spread_degrees >= 359.5
	# The shrapnel inherits the *parent's* travel direction as the
	# spread's center. So a pod thrown left explodes its forward shards
	# leftward, side shards perpendicular — feels like the pod's
	# momentum is preserved in the explosion's bias.
	var base_angle: float = direction.angle()

	for i in child_count:
		var angle: float
		if is_full_ring:
			angle = base_angle + (TAU * float(i) / float(child_count))
		else:
			# Single-point case: lerp dividend would be zero.
			var t: float = 0.5 if child_count == 1 else float(i) / float(child_count - 1)
			angle = base_angle + lerp(-spread_rad * 0.5, spread_rad * 0.5, t)

		var dir: Vector2 = Vector2.RIGHT.rotated(angle)

		var child: Projectile = child_projectile_scene.instantiate()
		# Match the parent's run-time fields so the shrapnel feels like
		# the same family of attack — preserves element for tint,
		# preserves burn application etc.
		child.direction = dir
		child.speed = child_speed
		child.lifetime = child_lifetime
		child.pierce = 0
		child.damage = child_dmg
		child.owning_team = owning_team

		# Carry over status applications & element from our damage_info.
		# Build a fresh info dict so each child can carry its own
		# knockback dir later without aliasing.
		var info: Dictionary = damage_info.duplicate()
		info["amount"] = child_dmg
		info["knockback"] = child_knockback
		info["knockback_dir"] = dir
		child.damage_info = info
		child.projectile_visual = child_projectile_visual

		parent.add_child(child)
		# Offset slightly forward along the spawn direction so children
		# don't immediately collide with each other at the spawn point
		# and pierce-cancel each other's hitboxes.
		const SHARD_OFFSET: float = 4.0
		child.global_position = global_position + dir * SHARD_OFFSET


# --- Visual override: a larger, glowing pod so the player can track
# it through busy fire-themed scenes. We don't call super._draw — we
# replace it. The pod reads as a slow-moving, dangerous projectile;
# the standard tiny circle would get lost in the visual chaos of
# Brann.
func _draw() -> void:
	# Use the bomb visual from Projectile's drawing system — the pulsing
	# glow and fuse spark. We set projectile_visual = BOMB in the class
	# so even if the weapon doesn't explicitly set it, the pod draws as
	# a bomb rather than the default arrow.
	projectile_visual = Projectile.ProjectileVisual.BOMB
	var elem: int = damage_info.get("element", int(Weapon.Element.FIRE))
	var tip_col: Color = Weapon.element_color(elem)
	_draw_bomb(tip_col)
