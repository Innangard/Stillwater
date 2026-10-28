class_name ExplodingRangedWeapon
extends RangedWeapon
## RangedWeapon that fires ExplodingProjectile and also configures its
## explosion parameters per-weapon. Lets one .tres define both the
## delivery shot AND its shrapnel behavior, so a "mook pod" and a
## "boss pod" can share the projectile scene but tune count/damage/
## spread independently.
##
## The base RangedWeapon.attack() handles all the standard projectile
## setup (direction, speed, lifetime, team, damage_info). We override
## attack() to do the same — verbatim — and then push the explosion
## parameters into the spawned projectile. Duplicating the loop is
## clearer than refactoring RangedWeapon's spawn into a hook, given
## this is the only subclass that needs the customization.

@export_group("Explosion")
## Shrapnel scene. Usually res://projectiles/projectile.tscn so the
## children look like ordinary bullets.
@export var child_projectile_scene: PackedScene
## How many shrapnel pieces. 4 is "cardinal cross"; 6 is "snowflake"
## (60° apart); 8+ starts to feel like a wall to walk through.
@export_range(1, 24) var child_count: int = 4
## Travel speed of each shrapnel.
@export var child_speed: float = 280.0
## Lifetime of each shrapnel. Total shrapnel reach = child_speed *
## child_lifetime — keep around 150-200px so the player has a real
## chance to clear the burst radius after a dodge.
@export var child_lifetime: float = 0.6
## Per-shard damage multiplier vs the pod's base damage.
@export var child_damage_multiplier: float = 0.7
## How widely shrapnel is distributed. 360° = full ring.
@export_range(1.0, 360.0) var child_spread_degrees: float = 360.0
## Per-shard knockback.
@export var child_knockback: float = 80.0
## Visual shape for child/shrapnel projectiles (default TEARDROP).
## 0=ARROW, 1=BOLT, 2=BONE, 3=BOMB, 4=TEARDROP, 5=PELLET
@export_range(0, 5) var child_projectile_visual: int = 4


func attack(user: Node2D, aim: Vector2) -> void:
	if projectile_scene == null:
		push_error("ExplodingRangedWeapon '%s' has no projectile_scene." % weapon_name)
		return

	var base_angle: float = aim.angle()
	var spread_rad: float = deg_to_rad(spread_degrees)

	for i in projectile_count:
		var angle: float = base_angle
		if projectile_count > 1:
			var t: float = float(i) / float(projectile_count - 1)
			angle = base_angle + lerp(-spread_rad * 0.5, spread_rad * 0.5, t)
		_spawn_exploding_projectile(user, Vector2.RIGHT.rotated(angle))


## Replicates RangedWeapon._spawn_projectile (private base method) and
## adds the explosion parameter injection. We call this from our own
## attack() loop rather than super() because the base spawn is not a
## virtual hook — it's a private helper. The set of fields we replicate
## is small, the duplication is honest about coupling to the projectile
## scene's interface, and a future change to base spawn semantics
## should be mirrored here intentionally.
func _spawn_exploding_projectile(user: Node2D, direction: Vector2) -> void:
	var proj: Projectile = projectile_scene.instantiate()

	var effective: float = compute_outgoing_damage(user)
	var info: Dictionary = build_damage_info()
	info["amount"] = effective
	info["knockback"] = knockback
	info["knockback_dir"] = direction

	proj.direction = direction
	proj.speed = projectile_speed
	proj.lifetime = projectile_lifetime
	proj.pierce = pierce
	proj.damage = effective
	proj.owning_team = user.team if "team" in user else "neutral"
	proj.damage_info = info
	proj.projectile_visual = projectile_visual

	# Configure explosion params if this projectile happens to be an
	# ExplodingProjectile. We don't strictly require it (you could
	# subclass for a single-hit "primer" pod that's just a heavy ball),
	# but the typical case sets child_projectile_scene so this branch
	# fires.
	if proj is ExplodingProjectile:
		var ep: ExplodingProjectile = proj
		ep.child_projectile_scene = child_projectile_scene
		ep.child_count = child_count
		ep.child_speed = child_speed
		ep.child_lifetime = child_lifetime
		ep.child_damage_multiplier = child_damage_multiplier
		ep.child_spread_degrees = child_spread_degrees
		ep.child_knockback = child_knockback
		ep.child_projectile_visual = child_projectile_visual

	user.get_parent().add_child(proj)
	# Same SPAWN_OFFSET rationale as RangedWeapon — push the spawn
	# outside the user's body so it doesn't self-collide. Use a
	# slightly larger offset because exploding pods have a fatter
	# hitbox (radius 7 vs base radius 4).
	const SPAWN_OFFSET: float = 28.0
	proj.global_position = user.global_position + direction * SPAWN_OFFSET
