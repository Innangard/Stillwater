class_name PersistentHitbox
extends Node2D
## A damage zone that persists for `duration` seconds and applies damage
## every `tick_interval`. Unlike a MeleeSwing (single brief overlap) or a
## Projectile (single hit event), this is a *continuous* hazard — a
## flamethrower cone, a beam, an aura. The player can only avoid it by
## not being inside it.
##
## Shape is configured at spawn time: CONE (triangle-with-arc-end) for
## flamethrower-style attacks, RECTANGLE (long strip) for beam attacks,
## or CIRCLE (full disc centered on the user) for omnidirectional
## eruption-style attacks (sand worms, ground-pound shockwaves, etc).
## CONE and RECTANGLE extend forward along the +X axis of this node so
## the parent's rotation aims them; CIRCLE ignores rotation since a
## disc is rotation-invariant.
##
## Damage is applied by querying our HitboxComponent's overlapping areas
## every tick and emitting hit_received on each opposing HurtboxComponent.
## We don't rely on Godot's area_entered pipeline for tick damage because
## that signal fires only once per overlap entry — once the player is
## inside, area_entered never fires again until they leave and re-enter.
## So we leave collision_layer at 0 on our hitbox (so hurtboxes never
## auto-detect us via the normal pipeline) and route ALL damage through
## the tick loop. This gives us exact control over the damage rhythm and
## avoids the double-hit-on-entry that would otherwise occur.

enum ShapeKind { CONE, RECTANGLE, CIRCLE }

# ============================================================================
# CONFIG (set by the spawning weapon before add_child)
# ============================================================================

@export var shape_kind: ShapeKind = ShapeKind.CONE
## CONE: distance from tip to far edge. RECTANGLE: forward length.
## CIRCLE: radius of the disc (the disc extends `length` pixels in
## every direction from the user's center).
@export var length: float = 120.0
## CONE: full opening angle in degrees. Ignored for RECTANGLE.
@export var cone_angle_degrees: float = 60.0
## RECTANGLE: total width perpendicular to forward. Ignored for CONE.
@export var rect_width: float = 40.0
## How long the zone exists, in seconds.
@export var duration: float = 2.0
## Seconds between damage ticks. Damage applies on tick 0 too, so a
## player who walks into the zone takes damage immediately.
@export var tick_interval: float = 0.25
## Per-tick damage. Total damage if a target stands in the zone the
## entire duration is roughly: damage_per_tick * (duration / tick_interval).
@export var damage_per_tick: float = 4.0
@export var element: int = Weapon.Element.FIRE
@export var on_hit_effects: Array[StatusApplication] = []
@export var owning_team: String = "neutral"
## Pushback applied each tick. Small per-tick value so a target getting
## pushed out of the cone feels intentional, not catapulted.
@export var knockback: float = 60.0
## Aesthetic name shown in damage_info["weapon_name"] for HUD floating
## damage numbers. Inherits from the spawning weapon.
@export var weapon_name: String = "Persistent Hitbox"
## Category of the spawning weapon ("melee"/"ranged"/"spell"/"persistent").
## Propagates into damage_info["weapon_category"] so kill-tracking code
## downstream can categorize hits by source type. PersistentHitboxWeapon
## sets "persistent" by default (see its _init()); a future melee-styled
## persistent attack could override.
@export var weapon_category: String = "persistent"

@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var collision_polygon: CollisionPolygon2D = $HitboxComponent/CollisionPolygon2D

# ============================================================================
# RUNTIME STATE
# ============================================================================

var _lifetime: float
var _tick_timer: float
var _polygon_points: PackedVector2Array  # cached for _draw

# ============================================================================
# READY
# ============================================================================

func _ready() -> void:
	_lifetime = duration
	_tick_timer = 0.0  # fire on the first physics frame

	# Build the geometric shape from current params.
	_polygon_points = _build_polygon()
	collision_polygon.polygon = _polygon_points

	# We do our own damage routing. The hurtbox's standard area_entered
	# pipeline must NOT also pick up this hitbox (would cause an immediate
	# double-hit on entry). Disable detection by zeroing collision_layer
	# and rely entirely on our tick loop.
	hitbox.collision_layer = 0
	hitbox.owning_team = owning_team

	# Pre-fill damage_info so all targets get consistent metadata. Includes
	# burn-application list, the weapon name for damage popups, knockback
	# magnitude — the dir is filled in per-target each tick.
	hitbox.damage_info = {
		"amount": damage_per_tick,
		"element": element,
		"weapon_name": weapon_name,
		"weapon_category": weapon_category,
		"on_hit_effects": on_hit_effects,
		"knockback": knockback,
	}
	hitbox.damage = damage_per_tick

	# We DO monitor (so get_overlapping_areas works for tick polling).
	# Mask ONLY the opposing team's hurtbox layer — never the owning
	# team's. This is the same friendly-fire scheme Projectile uses
	# (see projectile.gd _ready): physical collision filtering, with
	# the team-string check below as a redundant secondary filter.
	#
	# The string filter alone is unsafe because most enemy .tscn files
	# don't set `team` on the HurtboxComponent — it defaults to
	# "neutral", so `hb.team == owning_team` is always false, and the
	# zone hits every enemy in range including its own caster.
	# Layer-based filtering side-steps the issue entirely: an enemy
	# hurtbox is on layer 32, and if we don't mask layer 32, the
	# hurtbox simply doesn't show up in get_overlapping_areas.
	#   layer 4 (bit 8) = player hurtbox
	#   layer 6 (bit 32) = enemy hurtbox
	# Neutral zones (anyone-can-hit, e.g. environmental hazards) still
	# mask both layers — that's the original behavior preserved.
	hitbox.monitoring = true
	match owning_team:
		"player": hitbox.collision_mask = 32         # enemies only
		"enemy":  hitbox.collision_mask = 8          # player only
		_:        hitbox.collision_mask = 8 | 32     # everybody


func _build_polygon() -> PackedVector2Array:
	match shape_kind:
		ShapeKind.CONE:
			# Cone tip at origin, opens forward toward +X. Use an arc of
			# points at the far edge so the cone has a rounded tip — reads
			# as a flame plume rather than a sharp wedge. Arc_steps=6 is
			# the minimum that doesn't look polygonal at this size; more
			# would be wasted detail on a transient hitbox.
			var half_rad: float = deg_to_rad(cone_angle_degrees * 0.5)
			var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
			var arc_steps: int = 6
			for i in range(arc_steps + 1):
				var t: float = float(i) / float(arc_steps)
				var ang: float = lerp(-half_rad, half_rad, t)
				pts.append(Vector2(cos(ang), sin(ang)) * length)
			return pts
		ShapeKind.RECTANGLE:
			# Long strip extending from origin forward. Origin sits at the
			# back-center so the strip emits "from the boss" forward.
			var hw: float = rect_width * 0.5
			return PackedVector2Array([
				Vector2(0, -hw),
				Vector2(length, -hw),
				Vector2(length, hw),
				Vector2(0, hw),
			])
		ShapeKind.CIRCLE:
			# Full disc centered at origin. Used for omnidirectional
			# eruption attacks (worm pop-up, ground pound) where the
			# hazard radiates equally in all directions from the user.
			# 20 sides — enough to read as circular at typical radii
			# (30-100px) without burning verts on a transient hitbox.
			# Rotation of the parent has no visible effect on the disc;
			# the polygon is rotation-invariant by construction.
			var sides: int = 20
			var pts: PackedVector2Array = PackedVector2Array()
			for i in sides:
				var ang: float = TAU * float(i) / float(sides)
				pts.append(Vector2(cos(ang), sin(ang)) * length)
			return pts
	return PackedVector2Array()


# ============================================================================
# PHYSICS — lifetime tick, damage application
# ============================================================================

func _physics_process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer += tick_interval
		_apply_tick_damage()

	queue_redraw()


func _apply_tick_damage() -> void:
	# Iterate every area currently overlapping our hitbox. Filter to
	# HurtboxComponents on opposing teams, then emit hit_received on
	# each — same path the standard area_entered pipeline uses, so
	# downstream handlers (status DoT application, knockback, stagger)
	# treat this exactly like any other hit.
	for area in hitbox.get_overlapping_areas():
		if not (area is HurtboxComponent):
			continue
		var hb: HurtboxComponent = area
		if hb.team == owning_team and owning_team != "neutral":
			continue
		# Per-target knockback dir: away from our origin. Computed in
		# global space so the receiver gets a sensible push regardless
		# of how this node is rotated.
		var info: Dictionary = hitbox.damage_info.duplicate()
		if is_instance_valid(hb):
			var away: Vector2 = (hb.global_position - global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			info["knockback_dir"] = away
		hb.hit_received.emit(damage_per_tick, info, hitbox)


# ============================================================================
# DRAW — flame/beam visual
# ============================================================================

func _draw() -> void:
	# Alpha pulse so the hazard reads as "active" without being a flat
	# blob. Quick triangle wave 0.45→0.85 at ~8 Hz reads as crackle.
	var pulse: float = 0.6 + 0.25 * sin(Time.get_ticks_msec() / 60.0)
	# Fade out the last 20% of lifetime so the disappearance is readable
	# rather than abrupt — the player can see "it's almost over."
	var life_t: float = clampf(_lifetime / duration, 0.0, 1.0)
	var fade: float = clampf(life_t / 0.20, 0.0, 1.0) if life_t < 0.20 else 1.0

	var inner: Color
	var outer: Color
	match shape_kind:
		ShapeKind.CONE:
			# Flame palette: bright yellow-white core, orange middle,
			# transparent red edge. Layer three polygons at decreasing
			# size to fake a gradient.
			inner = Color(1.00, 0.92, 0.55, pulse * fade * 0.80)
			outer = Color(1.00, 0.45, 0.15, pulse * fade * 0.55)
		ShapeKind.RECTANGLE:
			# Beam palette: white-hot core, gold halo.
			inner = Color(1.00, 0.98, 0.85, pulse * fade * 0.95)
			outer = Color(1.00, 0.70, 0.25, pulse * fade * 0.65)
		ShapeKind.CIRCLE:
			# Sand-eruption palette: pale dust core ringed by darker
			# kicked-up sand. Reads as "the ground just burst upward"
			# rather than "fire spell" — the desaturated yellow keeps it
			# distinct from the cone's hot orange.
			inner = Color(0.95, 0.86, 0.62, pulse * fade * 0.70)
			outer = Color(0.72, 0.55, 0.30, pulse * fade * 0.60)

	# Outer (full) shape.
	draw_colored_polygon(_polygon_points, outer)
	# Inner core: scaled-down copy of the same polygon for the bright
	# center. 0.6 scale gives a clean concentric look without authoring
	# a second polygon resource.
	var inner_pts: PackedVector2Array = PackedVector2Array()
	for p in _polygon_points:
		inner_pts.append(p * 0.6)
	draw_colored_polygon(inner_pts, inner)

	# Outline so the hazard's edge is unambiguous against busy
	# backgrounds. One-pixel-equivalent line keeps it readable without
	# fighting the fill colors. Outline tint matches the shape's
	# palette family — gold for fire shapes, dusky sand for the
	# eruption — so the edge color reinforces the read of "this is
	# fire/this is sand" without a separate art pass.
	var outline_color: Color
	match shape_kind:
		ShapeKind.CIRCLE:
			outline_color = Color(0.85, 0.65, 0.30, 0.75 * fade)
		_:
			outline_color = Color(1.0, 0.85, 0.40, 0.70 * fade)
	var n: int = _polygon_points.size()
	for i in n:
		var a: Vector2 = _polygon_points[i]
		var b: Vector2 = _polygon_points[(i + 1) % n]
		draw_line(a, b, outline_color, 1.5)
