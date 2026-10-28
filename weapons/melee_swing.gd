class_name MeleeSwing
extends Node2D
## The visual + hitbox node spawned by MeleeWeapon.attack(). Lives for
## swing_duration seconds, drawing a weapon-shaped silhouette that
## matches the actual collision geometry.
##
## ── Visual ↔ hitbox contract ────────────────────────────────────────
## Every drawn weapon fills the same space as the collision shape:
##   CIRCLE hitbox  → the weapon tip sweeps an arc whose reach matches
##                    swing_range + arc_radius (the far edge of the
##                    circle). The drawn weapon's total length (handle
##                    to tip) equals that reach, measured from the
##                    visual_origin (pulled back by radius so lines
##                    appear to come from the wielder's hands).
##   RECTANGLE hitbox → the weapon tip thrusts from -length/2 to
##                    +length/2, matching the rectangle's extent.
##                    Width scales to radius (half-width of the rect).
##
## The result: what the player sees IS the hitbox. No phantom range,
## no invisible reach, no undersized visuals.

enum ShapeKind { CIRCLE, RECTANGLE }

@export var shape_kind: ShapeKind = ShapeKind.CIRCLE
@export var radius: float = 32.0    # arc_radius from MeleeWeapon
@export var length: float = 36.0    # swing_range from MeleeWeapon
@export var lifetime_max: float = 0.16
@export var swing_direction: Vector2 = Vector2.RIGHT

## Visual shape of the weapon being swung. Set by MeleeWeapon at spawn.
var swing_visual: int = 0  # MeleeWeapon.SwingVisual enum value
## Element of the weapon — colors the blade/head edge.
var swing_element: int = 0  # Weapon.Element enum value

@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var collision_shape: CollisionShape2D = $HitboxComponent/CollisionShape2D

var _lifetime: float


func _ready() -> void:
	_lifetime = lifetime_max

	match shape_kind:
		ShapeKind.CIRCLE:
			var s := CircleShape2D.new()
			s.radius = radius
			collision_shape.shape = s
			collision_shape.position = Vector2.ZERO
		ShapeKind.RECTANGLE:
			var s := RectangleShape2D.new()
			s.size = Vector2(length, radius * 2.0)
			collision_shape.shape = s
			collision_shape.position = Vector2.ZERO

	hitbox.monitoring = false
	rotation = swing_direction.angle()

func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	queue_redraw()


# ============================================================================
# DRAW — weapon-shaped visuals matched to hitbox geometry
# ============================================================================

func _get_t() -> float:
	return 1.0 - clamp(_lifetime / lifetime_max, 0.0, 1.0)


func _draw() -> void:
	var t: float = _get_t()
	# MeleeWeapon.SwingVisual: SWORD=0 DAGGER=1 SPEAR=2 AXE=3
	# MACE=4 HAMMER=5 MAUL=6 CRUSHER=7 CLAW=8
	match swing_visual:
		0: _draw_bladed(t, 1.0)       # SWORD — full scale
		1: _draw_bladed(t, 0.7)       # DAGGER — 70% blade width
		2: _draw_spear(t)
		3: _draw_axe(t)
		4: _draw_shaft_head(t, "circle")
		5: _draw_shaft_head(t, "square")
		6: _draw_shaft_head(t, "rect")
		7: _draw_shaft_head(t, "star")
		8: _draw_claw(t)
		_: _draw_bladed(t, 1.0)


func _edge_color() -> Color:
	return Weapon.element_color(swing_element)


const SHAFT_COLOR := Color(0.45, 0.32, 0.18)
const BLADE_COLOR := Color(0.78, 0.76, 0.72)
const TRAIL_ALPHA_DECAY := 0.06


## Total visual reach — must match the hitbox's farthest extent so
## what the player sees IS what hits.
##   CIRCLE:    hitbox center is at +length from visual_origin, radius
##              extends past that → total reach = length + radius.
##   RECTANGLE: hitbox spans -length/2 to +length/2 → total = length.
##              (thrust weapons draw from the back edge forward)
func _reach() -> float:
	if shape_kind == ShapeKind.CIRCLE:
		return length + radius
	return length


# ── SWORD / DAGGER ──────────────────────────────────────────────────
## Rectangle blade + triangle tip. Total drawn length = _reach() so the
## tip touches the far edge of the hitbox circle/rectangle. `width_scale`
## controls blade width (1.0 for swords, 0.7 for daggers).
func _draw_bladed(t: float, width_scale: float) -> void:
	var reach: float = _reach()
	var blade_w: float = clampf(radius * 0.16 * width_scale, 2.5, 8.0)
	var handle_frac: float = 0.18
	var tip_frac: float = 0.15
	var edge: Color = _edge_color()

	match shape_kind:
		ShapeKind.CIRCLE:
			var visual_origin := Vector2(-radius, 0)
			var sweep_half: float = PI * 0.35
			var angle_at: float = lerp(-sweep_half, sweep_half, t)
			var dir: Vector2 = Vector2.RIGHT.rotated(angle_at)
			var perp: Vector2 = dir.rotated(PI * 0.5)
			_draw_blade_at(visual_origin, dir, perp, reach, blade_w, handle_frac, tip_frac, edge, 0.9)
			for i in range(1, 5):
				var trail_t: float = max(0.0, t - TRAIL_ALPHA_DECAY * i)
				var a: float = lerp(-sweep_half, sweep_half, trail_t)
				var td: Vector2 = Vector2.RIGHT.rotated(a)
				var tp: Vector2 = td.rotated(PI * 0.5)
				_draw_blade_at(visual_origin, td, tp, reach, blade_w, handle_frac, tip_frac, edge, 0.25 - 0.05 * i)
		ShapeKind.RECTANGLE:
			var tp_prog: float = sin(t * PI)
			var tip_x: float = -length * 0.5 + length * tp_prog
			var dir := Vector2.RIGHT
			var perp := Vector2.UP
			_draw_blade_at(Vector2(tip_x - reach, 0), dir, perp, reach, blade_w, handle_frac, tip_frac, edge, 0.9)
			for i in range(1, 4):
				var trail_t: float = max(0.0, t - 0.05 * i)
				var ttp: float = sin(trail_t * PI)
				_draw_blade_at(Vector2(-length * 0.5 + length * ttp - reach, 0), dir, perp, reach, blade_w, handle_frac, tip_frac, edge, 0.25 - 0.05 * i)


func _draw_blade_at(origin: Vector2, dir: Vector2, perp: Vector2,
		total_len: float, blade_w: float, handle_frac: float,
		tip_frac: float, edge_col: Color, alpha: float) -> void:
	var hw: float = blade_w * 0.5
	var handle_len: float = total_len * handle_frac
	var blade_len: float = total_len * (1.0 - handle_frac - tip_frac)
	var tip_len: float = total_len * tip_frac
	# Handle
	var h0: Vector2 = origin
	var h1: Vector2 = origin + dir * handle_len
	draw_colored_polygon(PackedVector2Array([
		h0 - perp * (hw * 0.6), h1 - perp * (hw * 0.6),
		h1 + perp * (hw * 0.6), h0 + perp * (hw * 0.6),
	]), Color(SHAFT_COLOR, alpha))
	# Blade body
	var b1: Vector2 = h1 + dir * blade_len
	draw_colored_polygon(PackedVector2Array([
		h1 - perp * hw, b1 - perp * hw,
		b1 + perp * hw, h1 + perp * hw,
	]), Color(BLADE_COLOR.r, BLADE_COLOR.g, BLADE_COLOR.b, alpha))
	# Tip
	var tip: Vector2 = b1 + dir * tip_len
	draw_colored_polygon(PackedVector2Array([
		b1 - perp * hw, tip, b1 + perp * hw,
	]), Color(edge_col.r, edge_col.g, edge_col.b, alpha))


# ── SPEAR ───────────────────────────────────────────────────────────
## Thin shaft + wider triangle head. Total length = _reach().
## Shaft width is thin (fixed 2.5px); head width scales with radius
## so a wide-arc spear has a visually wider head.
func _draw_spear(t: float) -> void:
	var reach: float = _reach()
	var edge: Color = _edge_color()
	var shaft_w: float = 2.5
	var head_frac: float = 0.22
	var head_w: float = clampf(radius * 0.3, 4.0, 12.0)

	match shape_kind:
		ShapeKind.CIRCLE:
			var visual_origin := Vector2(-radius, 0)
			var sweep_half: float = PI * 0.35
			var angle_at: float = lerp(-sweep_half, sweep_half, t)
			var dir: Vector2 = Vector2.RIGHT.rotated(angle_at)
			var perp: Vector2 = dir.rotated(PI * 0.5)
			_draw_spear_at(visual_origin, dir, perp, reach, shaft_w, head_frac, head_w, edge, 0.9)
			for i in range(1, 5):
				var trail_t: float = max(0.0, t - TRAIL_ALPHA_DECAY * i)
				var a: float = lerp(-sweep_half, sweep_half, trail_t)
				_draw_spear_at(visual_origin, Vector2.RIGHT.rotated(a), Vector2.RIGHT.rotated(a + PI * 0.5),
					reach, shaft_w, head_frac, head_w, edge, 0.25 - 0.05 * i)
		ShapeKind.RECTANGLE:
			var tp_prog: float = sin(t * PI)
			var tip_x: float = -length * 0.5 + length * tp_prog
			_draw_spear_at(Vector2(tip_x - reach, 0), Vector2.RIGHT, Vector2.UP,
				reach, shaft_w, head_frac, head_w, edge, 0.9)
			for i in range(1, 4):
				var trail_t: float = max(0.0, t - 0.05 * i)
				var ttp: float = sin(trail_t * PI)
				_draw_spear_at(Vector2(-length * 0.5 + length * ttp - reach, 0), Vector2.RIGHT, Vector2.UP,
					reach, shaft_w, head_frac, head_w, edge, 0.25 - 0.05 * i)


func _draw_spear_at(origin: Vector2, dir: Vector2, perp: Vector2,
		total_len: float, shaft_w: float, head_frac: float,
		head_w: float, edge_col: Color, alpha: float) -> void:
	var shw: float = shaft_w * 0.5
	var hhw: float = head_w * 0.5
	var shaft_len: float = total_len * (1.0 - head_frac)
	var head_len: float = total_len * head_frac
	var s0: Vector2 = origin
	var s1: Vector2 = origin + dir * shaft_len
	draw_colored_polygon(PackedVector2Array([
		s0 - perp * shw, s1 - perp * shw,
		s1 + perp * shw, s0 + perp * shw,
	]), Color(SHAFT_COLOR, alpha))
	var tip: Vector2 = s1 + dir * head_len
	draw_colored_polygon(PackedVector2Array([
		s1 - perp * hhw, tip, s1 + perp * hhw,
	]), Color(edge_col.r, edge_col.g, edge_col.b, alpha))


# ── AXE ─────────────────────────────────────────────────────────────
## Thin shaft + trapezoid wedge head. Head width scales with radius.
func _draw_axe(t: float) -> void:
	var reach: float = _reach()
	var edge: Color = _edge_color()
	var head_frac: float = 0.28
	var head_narrow: float = clampf(radius * 0.1, 3.0, 6.0)
	var head_wide: float = clampf(radius * 0.35, 6.0, 16.0)
	var shaft_w: float = 2.5

	var visual_origin: Vector2
	var dir: Vector2
	var perp: Vector2
	match shape_kind:
		ShapeKind.CIRCLE:
			visual_origin = Vector2(-radius, 0)
			var sweep_half: float = PI * 0.35
			var angle_at: float = lerp(-sweep_half, sweep_half, t)
			dir = Vector2.RIGHT.rotated(angle_at)
			perp = dir.rotated(PI * 0.5)
		_:
			var tp: float = sin(t * PI)
			visual_origin = Vector2(-length * 0.5 + length * tp - reach, 0)
			dir = Vector2.RIGHT
			perp = Vector2.UP

	var shaft_len: float = reach * (1.0 - head_frac)
	var head_len: float = reach * head_frac
	var shw: float = shaft_w * 0.5
	var s0: Vector2 = visual_origin
	var s1: Vector2 = visual_origin + dir * shaft_len
	draw_colored_polygon(PackedVector2Array([
		s0 - perp * shw, s1 - perp * shw,
		s1 + perp * shw, s0 + perp * shw,
	]), Color(SHAFT_COLOR, 0.9))
	var h1: Vector2 = s1 + dir * head_len
	draw_colored_polygon(PackedVector2Array([
		s1 - perp * head_narrow, h1 - perp * head_wide,
		h1 + perp * head_wide, s1 + perp * head_narrow,
	]), Color(edge.r, edge.g, edge.b, 0.9))

	for i in range(1, 4):
		var trail_t: float = max(0.0, t - TRAIL_ALPHA_DECAY * i)
		var trail_tip: Vector2
		match shape_kind:
			ShapeKind.CIRCLE:
				var ta: float = lerp(-PI * 0.35, PI * 0.35, trail_t)
				trail_tip = Vector2(-radius, 0) + Vector2.RIGHT.rotated(ta) * reach
			_:
				var ttp: float = sin(trail_t * PI)
				trail_tip = Vector2(-length * 0.5 + length * ttp, 0)
		draw_line(visual_origin, trail_tip, Color(edge.r, edge.g, edge.b, 0.2 - 0.05 * i), 2.0)


# ── MACE / HAMMER / MAUL / CRUSHER ─────────────────────────────────
## All share a thin shaft; head shape and size scale with radius so the
## drawn head fills the hitbox area.

func _shaft_and_head_pos(t: float) -> Dictionary:
	var reach: float = _reach()
	var head_frac: float = 0.25
	var shaft_len: float = reach * (1.0 - head_frac)
	var visual_origin: Vector2
	var dir: Vector2
	var perp: Vector2
	match shape_kind:
		ShapeKind.CIRCLE:
			visual_origin = Vector2(-radius, 0)
			var angle_at: float = lerp(-PI * 0.35, PI * 0.35, t)
			dir = Vector2.RIGHT.rotated(angle_at)
			perp = dir.rotated(PI * 0.5)
		_:
			var tp: float = sin(t * PI)
			visual_origin = Vector2(-length * 0.5 + length * tp - reach, 0)
			dir = Vector2.RIGHT
			perp = Vector2.UP
	var shw: float = 1.8
	var s0: Vector2 = visual_origin
	var s1: Vector2 = visual_origin + dir * shaft_len
	draw_colored_polygon(PackedVector2Array([
		s0 - perp * shw, s1 - perp * shw,
		s1 + perp * shw, s0 + perp * shw,
	]), Color(SHAFT_COLOR, 0.9))
	return {"tip": s1, "dir": dir, "perp": perp, "head_len": reach * head_frac}


func _draw_shaft_head(t: float, head_type: String) -> void:
	var d: Dictionary = _shaft_and_head_pos(t)
	var edge: Color = _edge_color()
	# Head size scales with radius so it fills the hitbox area.
	var head_r: float = clampf(radius * 0.28, 4.0, 18.0)
	var head_center: Vector2 = d["tip"] + d["dir"] * d["head_len"] * 0.5

	match head_type:
		"circle":
			draw_circle(head_center, head_r, Color(edge.r, edge.g, edge.b, 0.9))
			draw_arc(head_center, head_r, 0.0, TAU, 12, Color(edge.darkened(0.3), 0.9), 1.0)
		"square":
			var s: float = head_r * 0.85
			var dr: Vector2 = d["dir"]
			var pr: Vector2 = d["perp"]
			draw_colored_polygon(PackedVector2Array([
				head_center - dr * s - pr * s, head_center + dr * s - pr * s,
				head_center + dr * s + pr * s, head_center - dr * s + pr * s,
			]), Color(edge.r, edge.g, edge.b, 0.9))
		"rect":
			var hw: float = head_r * 0.6
			var hh: float = head_r * 1.1
			var dr: Vector2 = d["dir"]
			var pr: Vector2 = d["perp"]
			draw_colored_polygon(PackedVector2Array([
				head_center - dr * hw - pr * hh, head_center + dr * hw - pr * hh,
				head_center + dr * hw + pr * hh, head_center - dr * hw + pr * hh,
			]), Color(edge.r, edge.g, edge.b, 0.9))
		"star":
			var outer: float = head_r
			var inner: float = head_r * 0.45
			var pts := PackedVector2Array()
			for i in 10:
				var angle: float = TAU * i / 10.0 - PI / 2.0
				var r: float = outer if i % 2 == 0 else inner
				pts.append(head_center + Vector2(cos(angle), sin(angle)) * r)
			draw_colored_polygon(pts, Color(edge.r, edge.g, edge.b, 0.9))


# ── CLAW ────────────────────────────────────────────────────────────
## Three curved slash marks whose reach matches _reach().
func _draw_claw(t: float) -> void:
	var reach: float = _reach()
	var edge: Color = _edge_color()

	var visual_origin: Vector2
	var base_angle: float
	match shape_kind:
		ShapeKind.CIRCLE:
			visual_origin = Vector2(-radius * 0.3, 0)
			base_angle = lerp(-PI * 0.4, PI * 0.4, t)
		_:
			var tp: float = sin(t * PI)
			visual_origin = Vector2(-length * 0.3 + length * 0.6 * tp, 0)
			base_angle = 0.0

	for k in range(-1, 2):
		var spread: float = k * 0.3
		var slash_angle: float = base_angle + spread
		var dir: Vector2 = Vector2.RIGHT.rotated(slash_angle)
		# Slash reach matches hitbox reach from visual_origin
		var tip: Vector2 = visual_origin + dir * (reach * 0.95)
		var mid: Vector2 = visual_origin + dir * (reach * 0.5) + dir.rotated(PI * 0.5) * (k * 3.0)
		var alpha: float = 0.85 - abs(k) * 0.15
		draw_line(visual_origin, mid, Color(edge.r, edge.g, edge.b, alpha), 2.5)
		draw_line(mid, tip, Color(edge.r, edge.g, edge.b, alpha * 0.7), 2.0)

	for i in range(1, 3):
		var trail_t: float = max(0.0, t - 0.08 * i)
		var trail_angle: float
		match shape_kind:
			ShapeKind.CIRCLE:
				trail_angle = lerp(-PI * 0.4, PI * 0.4, trail_t)
			_:
				trail_angle = 0.0
		for k in range(-1, 2):
			var sa: float = trail_angle + k * 0.3
			var td: Vector2 = Vector2.RIGHT.rotated(sa)
			var ttip: Vector2 = visual_origin + td * (reach * 0.9)
			draw_line(visual_origin, ttip, Color(edge.r, edge.g, edge.b, 0.15 - 0.05 * i), 1.5)
