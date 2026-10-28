extends Enemy
## Gymir (Boss #6) -- mountain giant, father of Gerdr. In the myths,
## Gymir is a jotunn whose hall stands in the mountains. Here he is
## the mountain itself given will, a stone colossus who has forgotten
## everything except the weight of the world.
##
## ── Design intent ───────────────────────────────────────────────────
## Skill tested: SPACING + PATIENCE. Gymir is the first truly large
## enemy: big body, big hitboxes, big recovery windows. The fight
## teaches the player that "big and slow" doesn't mean "stand close
## and trade" -- his slam and shatter punish melee camping. The player
## must dash in during recoveries and retreat before the next swing.
##
## Phase 1 -- The Mountain Stands. Three-beat cycle:
##   BOULDER -- ranged rock hurl. Slow, predictable, sidestep-dodge.
##   SLAM    -- both fists, 80px telegraph. Step back or dash through.
##   SHATTER -- expanding stone ring from his body. Jump back or dash
##              through the band at the right moment.
##
## Phase 2 -- The Mountain Walks (35% HP). Gymir speeds up, his slam
## radius grows, and he gains a second boulder in his throw (two rocks
## in a spread). The arena cracks: falling rubble creates periodic
## telegraphed danger zones. The patient spacing game accelerates.

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "Gymir"
@export var boss_id: String = "gymir"
@export var weapon_boulder: RangedWeapon
@export var weapon_slam: TelegraphedAreaWeapon
@export var weapon_shatter: ExpandingRingWeapon

@export_group("Phase 2")
@export var phase2_threshold: float = 0.35
@export var phase2_speed: float = 60.0

@export_group("Per-Action Timing")
@export var wind_up_boulder: float = 0.80
@export var wind_up_slam: float = 0.90
@export var wind_up_shatter: float = 0.75

@export var recover_boulder: float = 0.70
@export var recover_slam: float = 1.00
@export var recover_shatter: float = 0.90

# ----------------------------------------------------------------------------
# BOSS CONSTANTS
# ----------------------------------------------------------------------------

const BOSS_STAGGER_THRESHOLD: float = 4.0
const BOSS_STUN_BASE: float = 0.5
const BOSS_LONG_STUN: float = 3.0
const BOSS_STAGGER_DECAY: float = 0.35
const BOSS_STAGGER_GAIN: float = 0.8
const BOSS_LEASH_RANGE: float = 0.0
const ENGAGEMENT_RANGE: float = 180.0
const MIN_ENGAGE_BAND: float = 0.0

# ============================================================================
# ACTIONS
# ============================================================================

enum Action { BOULDER, SLAM, SHATTER }

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

	_cycle = [Action.BOULDER, Action.SLAM, Action.SHATTER]
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
		Action.BOULDER: return weapon_boulder
		Action.SLAM:    return weapon_slam
		Action.SHATTER: return weapon_shatter
	return null


func _wind_up_for_action(a: Action) -> float:
	match a:
		Action.BOULDER: return wind_up_boulder
		Action.SLAM:    return wind_up_slam
		Action.SHATTER: return wind_up_shatter
	return 0.7


func _recover_for_action(a: Action) -> float:
	match a:
		Action.BOULDER: return recover_boulder
		Action.SLAM:    return recover_slam
		Action.SHATTER: return recover_shatter
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

	# Stone colossus -- large angular body
	_draw_body(body)

	# Cracks across the stone (character detail)
	var crack_col := Color(0.25, 0.22, 0.20, 0.7)
	draw_line(to_player.rotated(0.8) * body_radius * 0.3,
		to_player.rotated(1.2) * body_radius * 0.9, crack_col, 1.5)
	draw_line(to_player.rotated(-0.6) * body_radius * 0.2,
		to_player.rotated(-1.0) * body_radius * 0.85, crack_col, 1.5)

	# Glowing eyes (two amber dots)
	var eye_l: Vector2 = to_player * body_radius * 0.4 + to_player.rotated(PI*0.5) * 5.0
	var eye_r: Vector2 = to_player * body_radius * 0.4 - to_player.rotated(PI*0.5) * 5.0
	draw_circle(eye_l, 2.5, Color(0.85, 0.65, 0.25))
	draw_circle(eye_r, 2.5, Color(0.85, 0.65, 0.25))

	# Weapon indicator dot
	var icon_pos: Vector2 = to_player * (body_radius * 0.55)
	draw_circle(icon_pos, 4.0, weapon_icon_color)

	# Attack telegraph
	if _ai_state == AIState.WIND_UP and weapon != null:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		var aim_angle: float = to_player.angle()
		match _current_action():
			Action.BOULDER:
				draw_line(Vector2.ZERO, to_player * 150.0, telegraph_color, 2.0)
			Action.SLAM:
				if weapon_slam:
					var pulse: float = 0.5 + 0.5 * sin(t * 8.0)
					draw_arc(Vector2.ZERO, weapon_slam.damage_radius + pulse * 5.0, 0.0, TAU, 16, telegraph_color, 3.0)
			Action.SHATTER:
				if weapon_shatter:
					var pulse: float = 0.5 + 0.5 * sin(t * 9.0)
					var r0: float = weapon_shatter.start_radius + pulse * 6.0
					draw_arc(Vector2.ZERO, r0, 0.0, TAU, 24, telegraph_color, 2.5)

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
