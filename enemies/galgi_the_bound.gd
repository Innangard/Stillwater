extends Enemy
## Galgi the Bound — second story boss. A draugr of corpses bound together
## by rope, hanged from a gallows-tree. Odin hanged himself on Yggdrasil
## for nine nights to learn the runes; Galgi is that image gone wrong — a
## knot of people who refused the Pool and tied themselves together rather
## than face the water individually.
##
## ── Design intent ──────────────────────────────────────────────────────
## Skill tested: MOVEMENT UNDER THREAT OF BEING HELD STILL. The rope-arm
## grab rewards players who keep moving and punishes players who stand
## still to attack. This is the second boss: the player has already proven
## they can parry and read telegraphs against the Skeleton King. Now they
## have to add *constant repositioning* to that kit.
##
## Phase 1 — Hanged: Stationary. Galgi hangs from a gallows tree in the
## center of the arena. Three-attack cycle:
##   PENDULUM   — wide melee arc (the whole body swinging on the rope).
##                High damage, high knockback, lateral dodge is trivial.
##   ROPE_GRAB  — telegraphed AoE at the player's feet. Applies 80% slow
##                (the "Bound" status) for 1.5s. The danger isn't the
##                grab's damage — it's being slowed for the next attack.
##   CHOKE      — forward cone of black blood. Dark element, applies burn.
##                Dodge inward or to the sides.
##
## Phase 2 — Cut Loose (50% HP): The rope frays and Galgi falls to the
## ground. Gains movement (speed 80 — slow but relentless). Same three
## attacks, faster wind-ups. Adds a trailing-rope aura that applies a
## mild slow to players in close proximity — the counterplay is to stay
## ahead of the boss, not behind or beside it.
##
## ── Boss rhythm ────────────────────────────────────────────────────────
## Cycle: PENDULUM → ROPE_GRAB → CHOKE → repeat.
## The rhythm teaches the player to: dodge the swing, keep moving to avoid
## the grab, then dodge the cone. Three distinct reads, three distinct
## responses. Phase 2 compresses the timing and adds chase pressure.

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "Galgi the Bound"
@export var boss_id: String = "galgi_the_bound"
@export var weapon_pendulum: MeleeWeapon
@export var weapon_rope_grab: TelegraphedAreaWeapon
@export var weapon_choke: PersistentHitboxWeapon

@export_group("Phase 2")
## Phase 2 triggers at or below this fraction of max HP.
@export var phase2_threshold: float = 0.50
## Phase 2 wind-up speed — tighter than Phase 1 across the board.
@export var phase2_wind_up: float = 0.55
## Movement speed in phase 2. Phase 1 is always 0 (stationary).
@export var phase2_speed: float = 80.0

@export_group("Per-Action Timing")
## Wind-up durations per action. Phase 1 values — phase 2 uses
## phase2_wind_up for all except rope_grab (which stays slightly
## longer because the telegraph warning is the real read window).
@export var wind_up_pendulum: float = 0.75
@export var wind_up_rope_grab: float = 0.80
@export var wind_up_choke: float = 0.70

## Recover durations per action. Persistent-hitbox attacks (choke)
## must recover >= their duration so two cones can't overlap.
@export var recover_pendulum: float = 0.65
@export var recover_rope_grab: float = 0.55
@export var recover_choke: float = 2.0

@export_group("Trailing Rope (Phase 2)")
## Status effect applied by proximity in phase 2.
@export var rope_drag_effect: StatusEffect
## Radius within which the trailing rope applies its slow.
@export var rope_drag_radius: float = 50.0

# ----------------------------------------------------------------------------
# BOSS CONSTANTS
# ----------------------------------------------------------------------------

const BOSS_STAGGER_THRESHOLD: float = 3.0
const BOSS_STUN_BASE: float = 0.5
const BOSS_LONG_STUN: float = 3.0
const BOSS_STAGGER_DECAY: float = 0.4
const BOSS_STAGGER_GAIN: float = 1.0
const BOSS_LEASH_RANGE: float = 0.0

## Engagement distance for phase 2 — the boss tries to fight at this
## range, close enough for pendulum/choke to connect but not so close
## the player can't read them.
const ENGAGEMENT_RANGE: float = 120.0
const MIN_ENGAGE_BAND: float = 60.0

## Phase 1 attack range — very large so the stationary boss always
## enters WIND_UP. The individual weapons have limited actual reach;
## the pendulum whiffs if the player is far, but the rope grab targets
## wherever the player is. This means far players only dodge grabs,
## while close players face all three attacks — natural risk/reward.
const PHASE1_ATTACK_RANGE: float = 9999.0

# ============================================================================
# ACTIONS
# ============================================================================

enum Action { PENDULUM, ROPE_GRAB, CHOKE }

var _cycle: Array[Action] = []
var _cycle_index: int = 0
var _phase: int = 1
var _phase2_triggered: bool = false
var _engaged: bool = false

## Tracks the boss's movement direction for the trailing-rope visual.
## Updated every physics frame in phase 2.
var _move_direction: Vector2 = Vector2.DOWN

## Phase 1 sway — sinusoidal offset to simulate hanging on a rope.
var _sway_time: float = 0.0

# ============================================================================
# READY
# ============================================================================

func _ready() -> void:
	super()

	stagger_threshold = BOSS_STAGGER_THRESHOLD
	stun_duration_base = BOSS_STUN_BASE
	stagger_long_stun_duration = BOSS_LONG_STUN
	stagger_decay_rate = BOSS_STAGGER_DECAY
	stagger_gain_per_hit = BOSS_STAGGER_GAIN
	leash_range = BOSS_LEASH_RANGE

	_build_cycle_for_phase(_phase)
	_cycle_index = 0

	# Phase 1: stationary, attacks at any range.
	_attack_range = PHASE1_ATTACK_RANGE
	min_engage_range = 0.0

	weapon = _weapon_for_action(_cycle[_cycle_index])

	health_component.health_changed.connect(_on_boss_health_changed)
	health_component.died.connect(_on_boss_died)
	base_detection = 9999.0


func _physics_process(delta: float) -> void:
	super(delta)

	# Track movement direction for the trailing rope visual.
	if velocity.length_squared() > 1.0:
		_move_direction = velocity.normalized()

	# Phase 1 sway animation.
	if _phase == 1:
		_sway_time += delta

	# Engagement trigger — same belt-and-braces as boss_enemy.gd.
	if not _engaged and _ai_state != AIState.IDLE:
		_engaged = true
		var hp: float = health_component.current_health if health_component else max_health
		var hp_max: float = health_component.max_health if health_component else max_health
		EventBus.boss_engaged.emit(boss_display_name, hp, hp_max)
		EventBus.boss_stagger_changed.emit(_stagger, stagger_threshold)


func _emit_stagger_if_boss() -> void:
	if _engaged:
		EventBus.boss_stagger_changed.emit(_stagger, stagger_threshold)


# ============================================================================
# HEALTH / PHASE TRANSITION
# ============================================================================

func _on_boss_health_changed(current: float, maximum: float) -> void:
	if not _engaged:
		_engaged = true
		EventBus.boss_engaged.emit(boss_display_name, current, maximum)
	EventBus.boss_health_changed.emit(current, maximum)

	if not _phase2_triggered and current <= maximum * phase2_threshold:
		_phase2_triggered = true
		_phase = 2
		# Unlock movement.
		max_speed = phase2_speed
		# Tighten engagement to the standard boss fight distance.
		_attack_range = ENGAGEMENT_RANGE
		min_engage_range = MIN_ENGAGE_BAND
		# Faster wind-ups — the fight accelerates.
		wind_up_duration = phase2_wind_up
		# Activate trailing rope aura.
		aura_effect = rope_drag_effect
		aura_radius = rope_drag_radius
		_build_cycle_for_phase(_phase)
		_cycle_index = _cycle_index % _cycle.size()
		EventBus.boss_phase_changed.emit(2)


func _on_boss_died() -> void:
	EventBus.boss_defeated.emit(boss_display_name)
	GameState.mark_boss_dead(boss_id)
	BossDeathFx.play(self, boss_display_name, body_tint)


func _on_died() -> void:
	EventBus.entity_died.emit(self)
	EventBus.enemy_killed.emit(self, _last_hit_info)
	RunState.mark_node_consumed(self)
	call_deferred("_spawn_drops_at", global_position, get_parent())


# ============================================================================
# CYCLE MANAGEMENT
# ============================================================================

func _build_cycle_for_phase(_p: int) -> void:
	_cycle.clear()
	# Same three-beat cycle in both phases. Phase 2 changes TIMING,
	# not STRUCTURE — the player's learned rhythm stays valid, it just
	# runs faster and the boss is now chasing. This follows the design
	# principle: "a phase shift should be a new fight sharing an arena
	# with the old one," not a new rotation to memorize.
	_cycle = [Action.PENDULUM, Action.ROPE_GRAB, Action.CHOKE]


func _weapon_for_action(a: Action) -> Weapon:
	match a:
		Action.PENDULUM:  return weapon_pendulum
		Action.ROPE_GRAB: return weapon_rope_grab
		Action.CHOKE:     return weapon_choke
	return null


# ============================================================================
# ATTACK PROCESSING
# ============================================================================

func _process_attack() -> void:
	if _player == null:
		_ai_state = AIState.RECOVER
		_state_timer = recover_pendulum
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	var action: Action = _cycle[_cycle_index]
	var attack_recover: float = 0.0

	match action:
		Action.PENDULUM:
			if weapon_pendulum:
				weapon_pendulum.attack(self, aim)
			attack_recover = recover_pendulum
		Action.ROPE_GRAB:
			if weapon_rope_grab:
				weapon_rope_grab.attack(self, aim)
			attack_recover = recover_rope_grab
		Action.CHOKE:
			if weapon_choke:
				weapon_choke.attack(self, aim)
			attack_recover = recover_choke

	# Advance the cycle.
	_cycle_index = (_cycle_index + 1) % _cycle.size()

	# Update weapon slot for next cycle.
	weapon = _weapon_for_action(_cycle[_cycle_index])

	# Set per-action wind-up for the NEXT attack.
	var next_action: Action = _cycle[_cycle_index]
	if _phase == 2:
		# Phase 2: tighter across the board, but rope grab keeps
		# a slightly longer wind-up because the telegraph warning
		# IS the player's read window.
		match next_action:
			Action.ROPE_GRAB: wind_up_duration = phase2_wind_up + 0.10
			_:                wind_up_duration = phase2_wind_up
	else:
		match next_action:
			Action.PENDULUM:  wind_up_duration = wind_up_pendulum
			Action.ROPE_GRAB: wind_up_duration = wind_up_rope_grab
			Action.CHOKE:     wind_up_duration = wind_up_choke

	_ai_state = AIState.RECOVER
	_state_timer = attack_recover


## Keep pressing during RECOVER — same rationale as Cinder Sovereign.
func _process_recover(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_ai_state = AIState.CHASE
		return
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	if _phase == 2:
		var effective_speed: float = max_speed * status_component.get_speed_multiplier()
		_apply_engagement_band_movement(delta, effective_speed)
	else:
		# Phase 1: stationary. No movement during recover.
		velocity = Vector2.ZERO


# ============================================================================
# DRAW OVERRIDE — the hanged man, phase visuals, rope, telegraph
# ============================================================================

func _draw_animates_per_frame() -> bool:
	return true


func _draw() -> void:
	# --- Body tint ---
	var body: Color = body_tint
	match _ai_state:
		AIState.IDLE:
			body = body.lerp(Color(0.3, 0.3, 0.3), 0.55)
		AIState.WIND_UP:
			if _state_timer <= STAGGER_WINDOW:
				body = body.lerp(Color(1.0, 0.2, 0.2), 0.85)
			else:
				body = body.lerp(Color(1.0, 0.9, 0.3), 0.65)
		AIState.STUNNED:
			body = body.lerp(Color(0.85, 0.85, 1.0), 0.55)

	# Phase 2: darker, angrier — the bound dead walk.
	if _phase == 2:
		body = body.lerp(Color(0.25, 0.15, 0.12), 0.30)

	var tint: Color = status_component.get_tint()
	if tint.a > 0.0:
		body = body.lerp(Color(tint.r, tint.g, tint.b, 1.0), tint.a)

	# --- Phase 1 sway offset ---
	var sway_offset: Vector2 = Vector2.ZERO
	if _phase == 1:
		sway_offset = Vector2(sin(_sway_time * 1.8) * 4.0, sin(_sway_time * 1.2) * 2.0)

	# --- Rope (phase 1: to gallows above; phase 2: trailing behind) ---
	var rope_color := Color(0.40, 0.30, 0.18)
	if _phase == 1:
		# Rope going up to the gallows (implied offscreen above).
		var rope_top: Vector2 = sway_offset + Vector2(0, -body_radius - 80.0)
		var rope_bottom: Vector2 = sway_offset + Vector2(0, -body_radius * 0.90)
		draw_line(rope_bottom, rope_top, rope_color, 2.5)
		# Noose loop around the "neck" area.
		var noose_center: Vector2 = sway_offset + Vector2(0, -body_radius * 0.75)
		draw_arc(noose_center, 6.0, 0.0, TAU, 12, rope_color, 2.0)
	else:
		# Cut rope trails behind based on movement direction.
		var trail_dir: Vector2 = -_move_direction
		var rope_start: Vector2 = trail_dir * (body_radius * 0.6)
		var rope_end: Vector2 = trail_dir * (body_radius + 35.0)
		# Frayed end — the rope wiggles.
		var wiggle: float = sin(Time.get_ticks_msec() / 120.0) * 6.0
		var rope_mid: Vector2 = (rope_start + rope_end) * 0.5 + trail_dir.rotated(PI * 0.5) * wiggle
		draw_line(rope_start, rope_mid, rope_color, 2.0)
		draw_line(rope_mid, rope_end, rope_color, 1.5)
		# Frayed tip — two thin lines splitting.
		var fray_perp: Vector2 = trail_dir.rotated(PI * 0.5) * 5.0
		draw_line(rope_end, rope_end + trail_dir * 8.0 + fray_perp, rope_color.darkened(0.2), 1.0)
		draw_line(rope_end, rope_end + trail_dir * 6.0 - fray_perp, rope_color.darkened(0.2), 1.0)

	# --- Body ---
	# In phase 1, draw body at sway offset.
	if _phase == 1 and sway_offset != Vector2.ZERO:
		# We can't easily offset draw_colored_polygon to sway, so we'll
		# draw the body with the sway baked in by translating the polygon.
		var pts: PackedVector2Array = _body_polygon()
		var shifted := PackedVector2Array()
		for p in pts:
			shifted.append(p + sway_offset)
		var outline_color: Color = body.darkened(0.35)
		draw_colored_polygon(shifted, body)
		var outline_pts: PackedVector2Array = shifted.duplicate()
		outline_pts.append(shifted[0])
		draw_polyline(outline_pts, outline_color, 1.5)
	else:
		_draw_body(body)

	# --- Black blood drip (visual flavor) ---
	var t: float = Time.get_ticks_msec() / 1000.0
	var drip_offset: Vector2 = sway_offset if _phase == 1 else Vector2.ZERO
	for i in range(3):
		# Each drip has a different phase and speed.
		var drip_phase: float = t * (0.8 + i * 0.3) + i * 1.7
		var drip_y: float = fmod(drip_phase, 2.0) * 12.0 + body_radius * 0.4
		var drip_x: float = (i - 1) * 7.0
		var drip_alpha: float = 1.0 - fmod(drip_phase, 2.0) / 2.0
		if drip_alpha > 0.05:
			draw_circle(
				drip_offset + Vector2(drip_x, drip_y),
				1.5,
				Color(0.08, 0.05, 0.05, drip_alpha * 0.7)
			)

	# --- Weapon indicator dot ---
	var icon_dir: Vector2 = Vector2.RIGHT
	if is_instance_valid(_player):
		icon_dir = (_player.global_position - global_position).normalized()
	var icon_pos: Vector2 = icon_dir * (body_radius * 0.5) + sway_offset
	var icon_color: Color = _icon_color_for_next_action()
	draw_circle(icon_pos, 4.0, icon_color)

	# --- Attack telegraph ---
	if _ai_state == AIState.WIND_UP and weapon != null:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		_draw_galgi_telegraph(icon_dir, telegraph_color, sway_offset)

	# --- HP bar (proximity nameplate) ---
	var hp_pct: float = health_component.health_percent() if health_component else 1.0
	var bar_w: float = body_radius * 2.0
	var bar_y: float = -body_radius - 20.0 + sway_offset.y
	var bar_x: float = -bar_w * 0.5 + sway_offset.x
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w, 4)), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_w * hp_pct, 4)), Color(0.50, 0.25, 0.20))

	# --- Stun stars / engaged dot ---
	if _ai_state == AIState.STUNNED:
		var st: float = Time.get_ticks_msec() / 1000.0
		for i in range(3):
			var a: float = st * 6.0 + i * (TAU / 3.0)
			var p := Vector2(cos(a), -0.3 + sin(a) * 0.15) * 14.0 + Vector2(0, -body_radius - 18.0) + sway_offset
			draw_circle(p, 2.4, Color(1.0, 0.95, 0.5))
	elif _ai_state != AIState.IDLE:
		draw_circle(sway_offset + Vector2(0, -2), 2.5, Color(1, 0.95, 0.5))


## Color hint of the NEXT action — same design language as Cinder Sovereign.
func _icon_color_for_next_action() -> Color:
	match _cycle[_cycle_index]:
		Action.PENDULUM:  return Color(0.70, 0.55, 0.35)   # brown — impact / rope
		Action.ROPE_GRAB: return Color(0.55, 0.30, 0.55)   # dark purple — grab
		Action.CHOKE:     return Color(0.15, 0.10, 0.08)   # near-black — blood
	return weapon_icon_color


## Attack telegraph — shape matches the current cycle slot.
func _draw_galgi_telegraph(icon_dir: Vector2, telegraph_color: Color, sway: Vector2) -> void:
	var action: Action = _cycle[_cycle_index]
	var aim_angle: float = icon_dir.angle()

	match action:
		Action.PENDULUM:
			# Wide arc sweep — the pendulum's path.
			if weapon_pendulum:
				var reach: float = weapon_pendulum.swing_range + weapon_pendulum.arc_radius
				var telegraph_pos: Vector2 = icon_dir * (reach * 0.4) + sway
				draw_arc(telegraph_pos, reach * 0.6, 0.0, TAU, 24, telegraph_color, 2.5)
		Action.ROPE_GRAB:
			# Pulsing circle at the boss's feet — ground-targeted.
			# The actual telegraph on the floor is handled by the
			# Telegraph scene; this is just the wind-up cue.
			var pulse_alpha: float = 0.30 + 0.25 * sin(Time.get_ticks_msec() / 90.0)
			var grab_color := Color(0.55, 0.30, 0.55, pulse_alpha)
			draw_arc(sway, body_radius + 10.0, 0.0, TAU, 16, grab_color, 2.0)
			# Three small lines radiating outward to suggest "tendrils."
			for i in range(3):
				var angle: float = Time.get_ticks_msec() / 500.0 + i * (TAU / 3.0)
				var start: Vector2 = sway + Vector2(cos(angle), sin(angle)) * (body_radius + 5.0)
				var end: Vector2 = sway + Vector2(cos(angle), sin(angle)) * (body_radius + 20.0)
				draw_line(start, end, grab_color, 1.5)
		Action.CHOKE:
			# Cone telegraph — same approach as Cinder Sovereign.
			if weapon_choke:
				_draw_cone_telegraph(aim_angle, weapon_choke.length,
					weapon_choke.cone_angle_degrees, telegraph_color, sway)


func _draw_cone_telegraph(aim_angle: float, length: float,
		cone_angle_degrees: float, telegraph_color: Color,
		offset: Vector2 = Vector2.ZERO) -> void:
	var half_rad: float = deg_to_rad(cone_angle_degrees * 0.5)
	var arc_steps: int = 8
	var pts: PackedVector2Array = PackedVector2Array([offset])
	for i in range(arc_steps + 1):
		var local_t: float = float(i) / float(arc_steps)
		var local_ang: float = lerp(-half_rad, half_rad, local_t)
		var world_ang: float = aim_angle + local_ang
		pts.append(offset + Vector2(cos(world_ang), sin(world_ang)) * length)
	var fill: Color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b,
		telegraph_color.a * 0.35)
	draw_colored_polygon(pts, fill)
	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, telegraph_color, thickness)
