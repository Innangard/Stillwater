class_name RangedWeapon
extends Weapon
## A ranged weapon. Spawns one or more projectiles in a spread pattern.
## Can be a bow, gun, crossbow, dart — different feel via tuning.

@export_group("Ranged")
## The Projectile scene to spawn. Usually res://projectiles/projectile.tscn,
## but you can swap in custom projectile scenes for special weapons.
@export var projectile_scene: PackedScene
## Visual shape of the projectile. Passed to each spawned Projectile's
## projectile_visual field so arrows look like arrows, bolts like bolts, etc.
##   0=ARROW (default), 1=BOLT, 2=BONE, 3=BOMB, 4=TEARDROP, 5=PELLET
@export_range(0, 5) var projectile_visual: int = 0
## How fast the projectile travels (pixels/sec).
@export var projectile_speed: float = 520.0
## How long the projectile lives before despawning (seconds).
## Default reduced as part of the ranged-weapon rebalance — see notes
## below. Weapons that need a different lifetime override this in
## their .tres (long-range bows raise it to ~1.4, scatter shots drop
## it lower).
##
## Ranged rebalance (constitution: melee = power, ranged = positioning):
##   Ranged weapons receive three concurrent reductions vs. their
##   pre-rebalance values: −18% base damage, +20% cooldown, and ~−22%
##   projectile lifetime. The damage and cooldown cuts are applied
##   per-weapon in the .tres files (they varied too much for a single
##   default). The lifetime cut is applied here at the default AND
##   per-file for overrides. Together the changes preserve the role of
##   ranged as a kiting / opener tool while ensuring melee — which has
##   no safety margin on positioning — wins the DPS race.
@export var projectile_lifetime: float = 1.1
## How many projectiles spawn per attack. >1 fans out across spread_degrees.
@export_range(1, 32) var projectile_count: int = 1
## Total angular spread, in degrees. Ignored if count is 1.
@export_range(0.0, 180.0) var spread_degrees: float = 0.0
## How many enemies one projectile can pass through before despawning.
@export_range(0, 20) var pierce: int = 0
## Knockback applied to anything the projectile hits.
@export var knockback: float = 100.0


func _init() -> void:
	super()
	if category == "weapon":
		category = "ranged"


## Approximate max distance the projectile can fly before despawning.
## Enemy AI uses this to decide when it's in firing range.
func effective_range() -> float:
	return projectile_speed * projectile_lifetime


func attack(user: Node2D, aim: Vector2) -> void:
	if projectile_scene == null:
		push_error("RangedWeapon '%s' has no projectile_scene assigned." % weapon_name)
		return

	var base_angle := aim.angle()
	var spread_rad := deg_to_rad(spread_degrees)

	for i in projectile_count:
		var angle: float = base_angle
		if projectile_count > 1:
			var t := float(i) / float(projectile_count - 1) # 0..1 across the fan
			angle = base_angle + lerp(-spread_rad * 0.5, spread_rad * 0.5, t)
		_spawn_projectile(user, Vector2.RIGHT.rotated(angle))


func _spawn_projectile(user: Node2D, direction: Vector2) -> void:
	var proj: Projectile = projectile_scene.instantiate()

	# compute_outgoing_damage layers status buffs + (for player) kenning
	# multipliers into the base. Mirror in info["amount"] so anything
	# reading from the dict sees the same number on the wire.
	var effective: float = compute_outgoing_damage(user)
	var info := build_damage_info()
	info["amount"] = effective
	info["knockback"] = knockback
	info["knockback_dir"] = direction

	# Set properties BEFORE add_child — _ready uses direction/damage/damage_info/team.
	proj.direction = direction
	# Rune bonus: projectile speed scales from rune collection.
	var speed_mult: float = RunState.get_rune_multiplier(
		RunestoneItem.RuneStat.PROJECTILE_SPEED) if user is Player else 1.0
	proj.speed = projectile_speed * speed_mult
	proj.lifetime = projectile_lifetime
	proj.pierce = pierce
	proj.damage = effective
	proj.owning_team = user.team if "team" in user else "neutral"
	proj.damage_info = info
	proj.projectile_visual = projectile_visual

	# Spawn into the user's parent (the world), not as a child of user,
	# so the projectile moves independently in world space.
	user.get_parent().add_child(proj)
	# Offset spawn position forward of the user so the projectile doesn't
	# start *inside* the user's hurtbox — that would self-collide via the
	# projectile body's hurtbox-overlap mask and cancel the shot. Player
	# happens to get away with no offset because the player's hurtbox is
	# offset upward from root; enemies have centered hurtboxes so they
	# always self-hit without this. SPAWN_OFFSET is sized to clear the
	# largest body radius among current enemies (Giant Crab at 18px) plus
	# a small margin.
	const SPAWN_OFFSET := 24.0
	proj.global_position = user.global_position + direction * SPAWN_OFFSET
