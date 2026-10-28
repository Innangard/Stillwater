extends Enemy
## Skadi (Boss #7) -- the mountain huntress. In the myths, Skadi is
## the jotunn goddess of bowhunting and skiing who chose her husband
## by his feet alone. Here she is a tireless hunter who never misses
## -- the question is whether the player can make her miss.
##
## ── Design intent ───────────────────────────────────────────────────
## Skill tested: DODGING RANGED ATTACKS + CLOSING DISTANCE. Skadi is
## the ranged-specialist boss. She maintains distance, punishes
## approaches with spread shots, and only uses her lance when cornered.
## The player must dodge arrows while closing the gap to exploit her
## weaker melee defense.
##
## Phase 1 -- The Hunt. Five-beat cycle:
##   AIMED    -- single precise arrow. Fast, narrow, must be sidestepped.
##   SPREAD   -- three arrows in a fan. Dodge through or stay at range.
##   THRUST   -- ice lance thrust if player is close (lunge 60px).
##   SWEEP    -- wide lance arc. Area denial melee.
##   ICE STAKE -- telegraphed ice pillar at player's position.
##
## Phase 2 -- The Winter (40% HP). Skadi gains icy ground (slow aura).
## Her arrows fire faster and the ice stake targets 2 locations.

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "Skadi"
@export var boss_id: String = "skadi"
@export var weapon_aimed: RangedWeapon
@export var weapon_spread: RangedWeapon
@export var weapon_thrust: MeleeWeapon
@export var weapon_sweep: MeleeWeapon
@export var weapon_ice_stake: TelegraphedAreaWeapon

@export_group("Phase 2")
@export var phase2_threshold: float = 0.40
@export var phase2_speed: float = 80.0

@export_group("Per-Action Timing")
@export var wind_up_aimed: float = 0.60
@export var wind_up_spread: float = 0.70
@export var wind_up_thrust: float = 0.50
@export var wind_up_sweep: float = 0.60
@export var wind_up_ice_stake: float = 0.70

@export var recover_aimed: float = 0.50
@export var recover_spread: float = 0.65
@export var recover_thrust: float = 0.45
@export var recover_sweep: float = 0.55
@export var recover_ice_stake: float = 0.80

# ----------------------------------------------------------------------------
# BOSS CONSTANTS
# ----------------------------------------------------------------------------

const BOSS_STAGGER_THRESHOLD: float = 3.0
const BOSS_STUN_BASE: float = 0.5
const BOSS_LONG_STUN: float = 3.0
const BOSS_STAGGER_DECAY: float = 0.4
const BOSS_STAGGER_GAIN: float = 1.0
const BOSS_LEASH_RANGE: float = 0.0
const ENGAGEMENT_RANGE: float = 200.0
const MIN_ENGAGE_BAND: float = 80.0

# ============================================================================
# ACTIONS
# ============================================================================

enum Action { AIMED, SPREAD, THRUST, SWEEP, ICE_STAKE }

var _cycle: Array[Action] = []
var _cycle_index: int = 0
var _phase: int = 1
var _phase2_triggered: bool = false
var _engaged: bool = false

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

	_cycle = [Action.AIMED, Action.SPREAD, Action.THRUST, Action.SWEEP, Action.ICE_STAKE]
	_cycle_index = 0

	_attack_range = ENGAGEMENT_RANGE
	min_engage_range = MIN_ENGAGE_BAND

	weapon = _weapon_for_action(_current_action())
	wind_up_duration = _wind_up_for_action(_current_action())

	health_component.health_changed.connect(_on_boss_health_changed)
	health_component.died.connect(_on_boss_died)
	base_detection = 9999.0



func _physics_process(delta: float) -> void:
	super(delta)

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
		max_speed = phase2_speed
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

func _current_action() -> Action:
	return _cycle[_cycle_index]


func _weapon_for_action(a: Action) -> Weapon:
	match a:
		Action.AIMED:     return weapon_aimed
		Action.SPREAD:    return weapon_spread
		Action.THRUST:    return weapon_thrust
		Action.SWEEP:     return weapon_sweep
		Action.ICE_STAKE: return weapon_ice_stake
	return null


func _wind_up_for_action(a: Action) -> float:
	match a:
		Action.AIMED:     return wind_up_aimed
		Action.SPREAD:    return wind_up_spread
		Action.THRUST:    return wind_up_thrust
		Action.SWEEP:     return wind_up_sweep
		Action.ICE_STAKE: return wind_up_ice_stake
	return 0.7


func _recover_for_action(a: Action) -> float:
	match a:
		Action.AIMED:     return recover_aimed
		Action.SPREAD:    return recover_spread
		Action.THRUST:    return recover_thrust
		Action.SWEEP:     return recover_sweep
		Action.ICE_STAKE: return recover_ice_stake
	return 0.6


# ============================================================================
# ATTACK PROCESSING
# ============================================================================

func _process_attack() -> void:
	if _player == null:
		_ai_state = AIState.RECOVER
		_state_timer = 0.6
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	var action: Action = _current_action()
	var w: Weapon = _weapon_for_action(action)
	if w:
		w.attack(self, aim)
	var attack_recover: float = _recover_for_action(action)

	_cycle_index = (_cycle_index + 1) % _cycle.size()

	var next_action: Action = _current_action()
	weapon = _weapon_for_action(next_action)
	wind_up_duration = _wind_up_for_action(next_action)

	_ai_state = AIState.RECOVER
	_state_timer = attack_recover


func _process_recover(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_ai_state = AIState.CHASE
		return
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	var effective_speed: float = max_speed * status_component.get_speed_multiplier()
	_apply_engagement_band_movement(delta, effective_speed)


# ============================================================================
# DRAW OVERRIDE
# ============================================================================

func _draw_animates_per_frame() -> bool:
	return true


func _draw() -> void:
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

	if _phase == 2:
		body = body.lerp(Color(0.15, 0.12, 0.10), 0.25)

	var tint: Color = status_component.get_tint()
	if tint.a > 0.0:
		body = body.lerp(Color(tint.r, tint.g, tint.b, 1.0), tint.a)

	var t: float = Time.get_ticks_msec() / 1000.0
	var to_player: Vector2 = Vector2.RIGHT
	if is_instance_valid(_player):
		to_player = (_player.global_position - global_position).normalized()

	# Huntress silhouette -- lean, athletic
	_draw_body(body)

	# Bow held diagonally
	var bow_pos: Vector2 = to_player.rotated(-0.4) * body_radius * 0.5
	draw_arc(bow_pos, body_radius * 0.6, to_player.angle() - 0.8, to_player.angle() + 0.8, 8,
		Color(0.60, 0.55, 0.45), 2.0)

	# Ice-blue eye
	var eye_pos: Vector2 = to_player * body_radius * 0.35
	draw_circle(eye_pos, 2.5, Color(0.55, 0.75, 0.90))

	# Weapon indicator dot
	var icon_pos: Vector2 = to_player * (body_radius * 0.55)
	draw_circle(icon_pos, 4.0, weapon_icon_color)

	# Attack telegraph
	if _ai_state == AIState.WIND_UP and weapon != null:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		var aim_angle: float = to_player.angle()
		match _current_action():
			Action.AIMED:
				draw_line(Vector2.ZERO, to_player * 200.0, telegraph_color, 1.5)
			Action.SPREAD:
				for i in range(3):
					var spread_dir: Vector2 = to_player.rotated(deg_to_rad((i - 1) * 25.0))
					draw_line(Vector2.ZERO, spread_dir * 150.0, telegraph_color, 1.5)
			Action.THRUST:
				if weapon_thrust:
					var reach: float = weapon_thrust.swing_range + weapon_thrust.user_lunge_distance
					draw_line(Vector2.ZERO, to_player * reach, telegraph_color, 3.0)
			Action.SWEEP:
				if weapon_sweep:
					var reach: float = weapon_sweep.swing_range + weapon_sweep.arc_radius
					draw_arc(Vector2.ZERO, reach, aim_angle - 0.8, aim_angle + 0.8, 12, telegraph_color, 2.5)
			Action.ICE_STAKE:
				if weapon_ice_stake:
					var pulse: float = 0.5 + 0.5 * sin(t * 8.0)
					draw_arc(Vector2.ZERO, weapon_ice_stake.damage_radius + pulse * 4.0, 0.0, TAU, 12, telegraph_color, 2.0)

	# HP bar
	var hp_pct: float = health_component.health_percent() if health_component else 1.0
	var bar_w: float = body_radius * 2.0
	var bar_y: float = -body_radius - 20.0
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w, 4)), Color(0.05, 0.10, 0.12))
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w * hp_pct, 4)), Color(0.35, 0.55, 0.55))

	# Stun stars
	if _ai_state == AIState.STUNNED:
		for i in range(3):
			var a: float = t * 6.0 + i * (TAU / 3.0)
			var p := Vector2(cos(a), -0.3 + sin(a) * 0.15) * 14.0 + Vector2(0, -body_radius - 14.0)
			draw_circle(p, 2.4, Color(1.0, 0.95, 0.5))
	elif _ai_state != AIState.IDLE:
		draw_circle(Vector2(0, -2), 2.5, Color(1, 0.95, 0.5))
