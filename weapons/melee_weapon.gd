class_name MeleeWeapon
extends Weapon
## A melee weapon. On attack, spawns a brief hitbox arc in front of the user.

@export_group("Melee")
## How far in front of the user the hitbox spawns (its center).
## Renamed from `range` because that name shadows Godot's built-in
## `range()` function. Authored values in .tres files use swing_range.
@export var swing_range: float = 36.0
## Radius of the hitbox circle. Bigger = wider swing coverage.
## For RECTANGLE shape, this is the half-width perpendicular to the
## swing direction (so a "thrust" wants a small arc_radius like 3-6).
@export var arc_radius: float = 32.0
## How long the swing hitbox stays alive. Also rough animation length.
@export var swing_duration: float = 0.16
## How hard the hit pushes the target away.
@export var knockback: float = 250.0
## If > 0, the user surges forward by this many pixels at attack-time
## (consumed by callers — Player ignores it, Enemy applies it). Used for
## wolf-style "lunge" attacks. Set to 0 for normal swings.
@export var user_lunge_distance: float = 0.0
## Hitbox geometry. CIRCLE = a round area centered at swing_range ahead
## (good for sword sweeps where the player can hit in a wide arc).
## RECTANGLE = a long thin strip extending from the user toward
## swing_range (good for spear thrusts — only enemies *directly in front*
## get hit). Width of the rectangle is arc_radius × 2.
enum HitboxShape { CIRCLE, RECTANGLE }
@export var hitbox_shape: HitboxShape = HitboxShape.CIRCLE
## Visual shape drawn during the swing animation. Communicates what
## weapon the entity is swinging so the player reads threat type from
## the swing silhouette, not just the wind-up telegraph.
##   SWORD      — rectangle blade + flush triangle point
##   DAGGER     — shorter, thinner blade
##   SPEAR      — thin shaft + wider triangle head
##   AXE        — thin shaft + wedge/crescent head
##   MACE       — thin shaft + circle head (ball mace)
##   HAMMER     — thin shaft + square head
##   MAUL       — thin shaft + rectangle head (broad flat)
##   CRUSHER    — thin shaft + star head (morningstar/crusher)
##   CLAW       — curved slash marks (natural weapons, no silhouette)
enum SwingVisual { SWORD, DAGGER, SPEAR, AXE, MACE, HAMMER, MAUL, CRUSHER, CLAW }
@export var swing_visual: SwingVisual = SwingVisual.SWORD

const SWING_SCENE: PackedScene = preload("res://weapons/melee_swing.tscn")


func _init() -> void:
	super()
	if category == "weapon":
		category = "melee"


## Effective max distance at which this weapon can hit something —
## used by Enemy AI to decide when it's in attack range. The arc
## radius extends the hitbox past swing_range, so the real reach is
## swing_range + arc_radius (a sword swung forward 36 with a 32-radius
## arc strikes things up to 68 away, plus the lunge if any). For a
## RECTANGLE, the strip stretches from the user out to swing_range, so
## arc_radius is sideways extent only — effective range is just
## swing_range + lunge.
func effective_range() -> float:
	if hitbox_shape == HitboxShape.RECTANGLE:
		return swing_range + user_lunge_distance
	return swing_range + arc_radius + user_lunge_distance


func attack(user: Node2D, aim: Vector2) -> void:
	var swing: MeleeSwing = SWING_SCENE.instantiate()
	var aim_n := aim.normalized()

	# Rune bonus: melee weapon size scales both arc_radius and swing_range.
	var size_mult: float = RunState.get_rune_multiplier(
		RunestoneItem.RuneStat.MELEE_SIZE) if user is Player else 1.0
	var scaled_radius: float = arc_radius * size_mult
	var scaled_range: float = swing_range * size_mult

	# Set properties BEFORE add_child — _ready will run on add_child and uses these.
	swing.lifetime_max = swing_duration
	swing.swing_direction = aim_n
	swing.shape_kind = MeleeSwing.ShapeKind.CIRCLE if hitbox_shape == HitboxShape.CIRCLE \
		else MeleeSwing.ShapeKind.RECTANGLE
	swing.radius = scaled_radius
	swing.length = scaled_range
	swing.swing_visual = swing_visual
	swing.swing_element = element

	if hitbox_shape == HitboxShape.CIRCLE:
		swing.position = aim_n * scaled_range
	else:
		swing.position = aim_n * (scaled_range * 0.5)

	# Now enter the tree (this triggers _ready, resolves the @onready hitbox ref).
	user.add_child(swing)

	# Hitbox reference is valid after add_child; configure damage now.
	# compute_outgoing_damage layers in status-effect buffs (Berserker
	# etc.) and, for the player, kenning multipliers (weapon-type and
	# element gated). Mirror the result in info["amount"] so listeners
	# that inspect the damage_info dict see the same number that hits.
	var effective: float = compute_outgoing_damage(user)
	var info := build_damage_info()
	info["amount"] = effective
	info["knockback"] = knockback
	info["knockback_dir"] = aim_n

	swing.hitbox.damage = effective
	swing.hitbox.damage_info = info
	var team: String = user.team if "team" in user else "neutral"
	swing.hitbox.owning_team = team
	# The MeleeSwing scene defaults to player-team layer (16). When an
	# enemy is the user we need to flip the hitbox to the enemy-team layer
	# (64) so the PLAYER's hurtbox (mask 64) detects it. Same convention
	# Projectile.gd uses — kept identical so future weapon types can
	# follow the same pattern.
	match team:
		"player": swing.hitbox.collision_layer = 16
		"enemy":  swing.hitbox.collision_layer = 64
		_:        swing.hitbox.collision_layer = 16 | 64
