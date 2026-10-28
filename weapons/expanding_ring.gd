class_name ExpandingRing
extends Node2D
## A radial wave-front that expands outward from its spawn point and hits
## each opposing target ONCE as the front passes over them. Built for the
## Drowned Crone's wave pulse, but generic: any "shockwave ring" attack
## (ground pound ripple, thunderclap, tide surge) can reuse it.
##
## Unlike PersistentHitbox (a fixed zone that ticks anyone inside it),
## the ring is a MOVING FRONT: only targets within the ring band
## [radius - band/2, radius + band/2] at the moment the front reaches
## them are hit, and each target is hit at most once per ring. The
## counterplay is timing — dash through the front with i-frames, or
## simply outrun it (the ring has finite expansion speed).
##
## Collision strategy: direct distance checks against opposing
## hurtboxes each physics frame, hits delivered by emitting
## hit_received on the target's HurtboxComponent — the same external-
## emission pattern PersistentHitbox._apply_tick_damage uses, so all
## downstream handling (dash i-frames, shield, statuses, knockback)
## behaves identically to any other hit. A bare HitboxComponent child
## (no collision shape, monitoring off) rides at the ring's CENTER as
## the `source` anchor: knockback direction is computed victim-minus-
## source, so anchoring at center makes positive knockback push
## radially outward — exactly what a wave should do.

## Radius the front starts at (usually just outside the caster's body).
var start_radius: float = 30.0
## Radius the front dies at.
var end_radius: float = 240.0
## Seconds the front takes to travel start → end. Expansion speed is
## therefore (end - start) / expand_duration px/s — tune so a walking
## player CAN outrun it only with a head start, making the dash the
## reliable answer.
var expand_duration: float = 1.1
## Half-band on each side of the front line within which a target
## counts as "in the wave." Wide enough that a 60fps frame step never
## tunnels the front past a stationary target: max frame travel is
## expansion_speed / 60 ≈ 3.2px at default tuning, far under the band.
var band_half_width: float = 14.0
var damage: float = 8.0
var element: int = 0
var knockback: float = 150.0
var on_hit_effects: Array[StatusApplication] = []
var owning_team: String = "enemy"
var weapon_name: String = "Wave Pulse"
var weapon_category: String = "persistent"
## Visual color of the ring (drawn as two concentric arcs + fill band).
var ring_color: Color = Color(0.45, 0.70, 0.85, 0.65)

var _elapsed: float = 0.0
## Targets already struck by this ring — one hit per target per wave.
var _already_hit: Dictionary = {}

@onready var _anchor: HitboxComponent = $HitboxComponent


func _ready() -> void:
	# The anchor never participates in physics detection — it exists
	# only as the `source` argument for hit_received (position + team
	# + damage_info metadata for downstream consumers).
	_anchor.monitoring = false
	_anchor.monitorable = false
	_anchor.collision_layer = 0
	_anchor.collision_mask = 0
	_anchor.owning_team = owning_team
	_anchor.damage = damage
	_anchor.damage_info = {
		"amount": damage,
		"element": element,
		"weapon_name": weapon_name,
		"weapon_category": weapon_category,
		"on_hit_effects": on_hit_effects,
		"knockback": knockback,
	}


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= expand_duration:
		queue_free()
		return
	_check_front_hits()
	queue_redraw()


func _current_radius() -> float:
	return lerp(start_radius, end_radius, clampf(_elapsed / expand_duration, 0.0, 1.0))


func _check_front_hits() -> void:
	var radius: float = _current_radius()
	var group_name: String = "player" if owning_team == "enemy" else "enemies"
	for target in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(target):
			continue
		if _already_hit.has(target.get_instance_id()):
			continue
		var dist: float = global_position.distance_to(target.global_position)
		if absf(dist - radius) <= band_half_width:
			var hb: HurtboxComponent = target.get_node_or_null("HurtboxComponent")
			if hb == null:
				continue
			_already_hit[target.get_instance_id()] = true
			hb.hit_received.emit(damage, _anchor.damage_info, _anchor)


func _draw() -> void:
	var radius: float = _current_radius()
	# Fade the ring out over its last 25% of travel so it dissipates
	# at the edge rather than blinking off.
	var life_t: float = _elapsed / expand_duration
	var alpha_scale: float = 1.0 if life_t < 0.75 else 1.0 - (life_t - 0.75) / 0.25
	var c: Color = ring_color
	c.a *= alpha_scale
	# Leading edge — brightest line, the actual hit front.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, c, 3.0)
	# Trailing edge — thinner, dimmer, gives the band visual depth.
	var trail: Color = c
	trail.a *= 0.45
	draw_arc(Vector2.ZERO, maxf(radius - band_half_width, 2.0), 0.0, TAU, 40, trail, 1.5)
	# Foam flecks on the leading edge — small dashes at rotating offsets
	# so the wave reads as churning water rather than a sterile circle.
	var t: float = Time.get_ticks_msec() / 300.0
	for i in range(10):
		var ang: float = t + TAU * i / 10.0
		var p: Vector2 = Vector2(cos(ang), sin(ang)) * radius
		draw_circle(p, 2.0, Color(0.85, 0.92, 0.95, c.a * 0.8))
