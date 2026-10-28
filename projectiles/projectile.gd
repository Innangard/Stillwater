class_name Projectile
extends Area2D
## Generic projectile. Used for ranged weapons, magic spells, and (later)
## enemy bullets. Driven entirely by the values set on it before adding
## to the tree — RangedWeapon/MagicSpell configure these.
##
## Why an Area2D and not a CharacterBody2D?
## Bullets don't slide along walls, they don't push other bodies, they
## don't need physics responses — they just want to know when they hit
## something. Area2D is much cheaper.

@export var speed: float = 500.0
@export var lifetime: float = 1.5
## How many enemies it can pass through. 0 = despawn on first hit.
@export var pierce: int = 0
@export var damage: float = 10.0
@export var damage_info: Dictionary = {}
@export var owning_team: String = "neutral"
## Direction of travel. Set by the weapon at spawn time.
var direction: Vector2 = Vector2.RIGHT

## Visual shape of this projectile. Set by the weapon at spawn time.
## Default ARROW works for most ranged weapons.
##   ARROW   — long thin arrowhead, wood shaft, element-colored tip
##   BOLT    — shorter, thicker crossbow bolt, same color scheme
##   BONE    — classic femur-shaped bone shard
##   BOMB    — round bomb (ExplodingProjectile overrides _draw, but
##             this provides a fallback for non-exploding bomb projectiles)
##   TEARDROP — tear/droplet shape for secondary/child projectiles
##   PELLET  — small circle (legacy fallback, broodmother spit etc.)
enum ProjectileVisual { ARROW, BOLT, BONE, BOMB, TEARDROP, PELLET }
var projectile_visual: int = ProjectileVisual.ARROW

@onready var hitbox: HitboxComponent = $HitboxComponent

var _hits: int = 0
## Actual collision radius, read from the scene's CollisionShape2D at
## _ready. Every drawn shape inscribes within this radius so the visual
## matches the hitbox exactly — no phantom reach, no undersized drawing.
var _hitbox_radius: float = 4.0


func _ready() -> void:
	# Orient the visual along travel direction.
	rotation = direction.angle()

	# Read the actual collision radius so drawings match the hitbox.
	var my_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if my_shape and my_shape.shape is CircleShape2D:
		_hitbox_radius = (my_shape.shape as CircleShape2D).radius

	# Difficulty: enemy projectiles travel slower on Easy / faster on Hard,
	# so the player has more or less time to react to a telegraphed shot.
	# Player shots are NOT scaled — weapon feel should stay consistent
	# regardless of difficulty (the variable side is enemy behavior, same
	# rationale as in Weapon.compute_outgoing_damage).
	if owning_team == "enemy":
		speed *= DifficultySettings.get_projectile_speed_multiplier()

	# Push our parameters down into the HitboxComponent so it's a valid hit.
	hitbox.damage = damage
	hitbox.damage_info = damage_info
	hitbox.owning_team = owning_team

	# Set the hitbox's collision_layer based on team so the right hurtboxes detect it.
	#   layer 5 (bit 16) = player-source hitbox  (enemy hurtboxes mask this)
	#   layer 7 (bit 64) = enemy-source hitbox   (player hurtboxes mask this)
	match owning_team:
		"player": hitbox.collision_layer = 16
		"enemy":  hitbox.collision_layer = 64
		_:        hitbox.collision_layer = 16 | 64

	# Detect walls (StaticBody2D on layer 1) and hurtboxes (we listen separately).
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(_body: Node) -> void:
	# Hit a wall.
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# We monitor the world-hurtbox layer, so anything we hit here is one of those.
	# We don't deal damage from this side — the hurtbox detects our HitboxComponent
	# and emits hit_received. Our job is to track hits for piercing.
	if area is HurtboxComponent:
		var hb: HurtboxComponent = area
		# Don't count friendly-side overlap as a hit.
		if hb.team == owning_team and owning_team != "neutral":
			return
		_hits += 1
		if _hits > pierce:
			# Disable our HitboxComponent's collision layer immediately
			# so any further overlaps in the SAME physics frame can't
			# deal extra damage before queue_free actually runs at end
			# of frame. Without this, firing a projectile through a
			# stack of overlapping enemies (or a boss + minion cluster)
			# would damage every enemy it touched on the same frame,
			# regardless of the pierce setting.
			hitbox.collision_layer = 0
			queue_free()


# --- Projectile visuals: shaped and colored by type + element. ---
# All drawn in local space; rotation=direction.angle() means +X is forward.
const SHAFT_BROWN := Color(0.50, 0.35, 0.18)    # wood shaft
const SHAFT_BROWN_LIGHT := Color(0.60, 0.45, 0.25) # lighter wood
const BONE_WHITE := Color(0.90, 0.85, 0.75)      # bone
const BONE_JOINT := Color(0.78, 0.72, 0.62)      # bone joint/knob

func _draw() -> void:
	var elem: int = damage_info.get("element", 0)
	var tip_col: Color = Weapon.element_color(elem)

	match projectile_visual:
		ProjectileVisual.ARROW:
			_draw_arrow(tip_col, false)
		ProjectileVisual.BOLT:
			_draw_arrow(tip_col, true)
		ProjectileVisual.BONE:
			_draw_bone(tip_col)
		ProjectileVisual.BOMB:
			_draw_bomb(tip_col)
		ProjectileVisual.TEARDROP:
			_draw_teardrop(tip_col)
		_:
			_draw_pellet(tip_col)


## Arrow: element-colored triangular tip → wood-brown shaft → small fletching.
## Bolt: same structure but shorter and thicker. All dimensions derive from
## _hitbox_radius so the drawn shape fills the collision circle.
func _draw_arrow(tip_col: Color, is_bolt: bool) -> void:
	var r: float = _hitbox_radius
	var shaft_len: float = r * 3.5 if not is_bolt else r * 2.2
	var shaft_w: float = r * 0.35 if not is_bolt else r * 0.6
	var tip_len: float = r * 1.5 if not is_bolt else r * 1.2
	var tip_w: float = r * 0.75 if not is_bolt else r * 1.0
	var fletch_len: float = r * 1.0 if not is_bolt else r * 0.7
	var fletch_w: float = r * 0.6 if not is_bolt else r * 0.5

	# Shaft (wood brown)
	draw_line(Vector2(-shaft_len, 0), Vector2.ZERO, SHAFT_BROWN, shaft_w)
	# Tip (element colored triangle)
	draw_colored_polygon(PackedVector2Array([
		Vector2(tip_len, 0),
		Vector2(0, -tip_w),
		Vector2(0, tip_w),
	]), tip_col)
	# Fletching (two small angled lines at the tail)
	var tail: Vector2 = Vector2(-shaft_len, 0)
	draw_line(tail, tail + Vector2(-fletch_len, -fletch_w), SHAFT_BROWN_LIGHT, 1.0)
	draw_line(tail, tail + Vector2(-fletch_len, fletch_w), SHAFT_BROWN_LIGHT, 1.0)


## Bone shard: classic femur shape — two rounded knobs connected by a
## thinner shaft. Tip knob colored by element. Scales to _hitbox_radius.
func _draw_bone(tip_col: Color) -> void:
	var r: float = _hitbox_radius
	var shaft_len: float = r * 2.5
	var shaft_w: float = r * 0.5
	var knob_r: float = r * 0.8
	var knob_spread: float = r * 0.4
	# Shaft
	draw_line(Vector2(-shaft_len * 0.5, 0), Vector2(shaft_len * 0.5, 0), BONE_WHITE, shaft_w)
	# Rear knob (bone colored)
	var rear: Vector2 = Vector2(-shaft_len * 0.5 - r * 0.2, 0)
	draw_circle(rear + Vector2(0, -knob_spread), knob_r * 0.75, BONE_JOINT)
	draw_circle(rear + Vector2(0, knob_spread), knob_r * 0.75, BONE_JOINT)
	# Front knob (element colored)
	var front: Vector2 = Vector2(shaft_len * 0.5 + r * 0.2, 0)
	draw_circle(front + Vector2(0, -knob_spread), knob_r * 0.75, tip_col)
	draw_circle(front + Vector2(0, knob_spread), knob_r * 0.75, tip_col)
	# Trail
	draw_line(Vector2(-shaft_len, 0), Vector2(-shaft_len - r * 1.5, 0),
		Color(BONE_WHITE.r, BONE_WHITE.g, BONE_WHITE.b, 0.3), shaft_w * 0.7)


## Bomb: round body with a fuse trailing behind. Fills _hitbox_radius.
func _draw_bomb(tip_col: Color) -> void:
	var r: float = _hitbox_radius
	# Body
	draw_circle(Vector2.ZERO, r, Color(0.25, 0.22, 0.20))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 12, Color(0.35, 0.30, 0.25), 1.0)
	# Element highlight band
	draw_arc(Vector2.ZERO, r * 0.6, -0.5, 0.5, 6, tip_col, r * 0.35)
	# Fuse (trailing spark line)
	draw_line(Vector2(-r, -r * 0.3), Vector2(-r * 2.0, -r * 0.6), Color(0.6, 0.5, 0.3), 1.0)
	var spark: Color = Color(1.0, 0.9, 0.4, 0.7 + 0.3 * sin(Time.get_ticks_msec() / 60.0))
	draw_circle(Vector2(-r * 2.0, -r * 0.6), r * 0.25, spark)


## Teardrop: secondary/child projectile. Inscribes within _hitbox_radius.
func _draw_teardrop(tip_col: Color) -> void:
	var r: float = _hitbox_radius
	var pts := PackedVector2Array([
		Vector2(r * 1.5, 0),
		Vector2(r * 0.25, -r * 0.75),
		Vector2(-r, -r * 0.6),
		Vector2(-r * 1.25, 0),
		Vector2(-r, r * 0.6),
		Vector2(r * 0.25, r * 0.75),
	])
	draw_colored_polygon(pts, tip_col)
	draw_line(Vector2(-r * 1.25, 0), Vector2(-r * 2.8, 0),
		Color(tip_col.r, tip_col.g, tip_col.b, 0.35), r * 0.35)


## Pellet: small colored circle matching _hitbox_radius (legacy/fallback).
func _draw_pellet(tip_col: Color) -> void:
	var r: float = _hitbox_radius
	draw_circle(Vector2.ZERO, r, tip_col)
	draw_line(Vector2.ZERO, Vector2(-r * 3, 0),
		Color(tip_col.r, tip_col.g, tip_col.b, 0.45), r * 0.5)
