extends Enemy
## Eir (Boss #10) -- a fallen valkyrie. In the myths, Eir is a healer
## among the valkyries, associated with mercy and medicine. Here she
## has forgotten mercy entirely, remembering only the spear and the
## judgement. She guards the final approach before the endgame.
##
## ── Design intent ───────────────────────────────────────────────────
## Skill tested: ALL PRIOR SKILLS COMBINED. Eir is the culmination
## boss -- she has ranged (spear volley), melee (swoop, flurry),
## AOE (feather storm), and telegraphed (soul spear). The player must
## use everything they've learned from the previous bosses.
##
## Phase 1 -- The Judgement. Five-beat cycle:
##   VOLLEY   -- three spectral spears (ranged fan).
##   SWOOP    -- diving lunge attack, 90px reach.
##   FLURRY   -- rapid three-hit melee.
##   STORM    -- expanding ring of feathers.
##   SOUL     -- telegraphed spear of light at player position.
##
## Phase 2 -- The Fall (35% HP). Eir's wings break. She becomes
## faster and more desperate. The volley fires 5 spears instead of 3.
## The soul spear warning time decreases.

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "Eir"
@export var boss_id: String = "eir"
@export var weapon_volley: RangedWeapon
@export var weapon_swoop: MeleeWeapon
@export var weapon_flurry: MeleeWeapon
@export var weapon_storm: ExpandingRingWeapon
@export var weapon_soul: TelegraphedAreaWeapon

@export_group("Phase 2")
@export var phase2_threshold: float = 0.35
@export var phase2_speed: float = 100.0

@export_group("Per-Action Timing")
@export var wind_up_volley: float = 0.60
@export var wind_up_swoop: float = 0.50
@export var wind_up_flurry: float = 0.40
@export var wind_up_storm: float = 0.75
@export var wind_up_soul: float = 0.90

@export var recover_volley: float = 0.55
@export var recover_swoop: float = 0.50
@export var recover_flurry: float = 0.45
@export var recover_storm: float = 0.70
@export var recover_soul: float = 0.85

# ----------------------------------------------------------------------------
# BOSS CONSTANTS
# ----------------------------------------------------------------------------

const BOSS_STAGGER_THRESHOLD: float = 3.0
const BOSS_STUN_BASE: float = 0.5
const BOSS_LONG_STUN: float = 3.0
const BOSS_STAGGER_DECAY: float = 0.45
const BOSS_STAGGER_GAIN: float = 1.0
const BOSS_LEASH_RANGE: float = 0.0
const ENGAGEMENT_RANGE: float = 170.0
const MIN_ENGAGE_BAND: float = 0.0

# ============================================================================
# ACTIONS
# ============================================================================

enum Action { VOLLEY, SWOOP, FLURRY, STORM, SOUL_SPEAR }

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

	_cycle = [Action.VOLLEY, Action.SWOOP, Action.FLURRY, Action.STORM, Action.SOUL_SPEAR]
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
		Action.VOLLEY:     return weapon_volley
		Action.SWOOP:      return weapon_swoop
		Action.FLURRY:     return weapon_flurry
		Action.STORM:      return weapon_storm
		Action.SOUL_SPEAR: return weapon_soul
	return null


func _wind_up_for_action(a: Action) -> float:
	match a:
		Action.VOLLEY:     return wind_up_volley
		Action.SWOOP:      return wind_up_swoop
		Action.FLURRY:     return wind_up_flurry
		Action.STORM:      return wind_up_storm
		Action.SOUL_SPEAR: return wind_up_soul
	return 0.7


func _recover_for_action(a: Action) -> float:
	match a:
		Action.VOLLEY:     return recover_volley
		Action.SWOOP:      return recover_swoop
		Action.FLURRY:     return recover_flurry
		Action.STORM:      return recover_storm
		Action.SOUL_SPEAR: return recover_soul
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

	# Valkyrie silhouette with wings
	_draw_body(body)

	# Wings (two arcs behind, feather-tips)
	var wing_col := Color(0.55, 0.48, 0.60, 0.8)
	if _phase == 2:
		wing_col = Color(0.40, 0.35, 0.45, 0.5)  # Broken wings
	var back: Vector2 = -to_player
	for side in [-1.0, 1.0]:
		var wing_base: Vector2 = back.rotated(side * 0.3) * body_radius * 0.5
		var wing_tip: Vector2 = back.rotated(side * 0.8) * (body_radius + 20.0)
		var sway: float = sin(t * 2.0 + side) * 3.0
		wing_tip += back.rotated(PI*0.5) * sway
		draw_line(wing_base, wing_tip, wing_col, 2.5)
		# Feather lines
		for j in range(3):
			var f: float = 0.3 + j * 0.25
			var feather_pos: Vector2 = wing_base.lerp(wing_tip, f)
			var feather_end: Vector2 = feather_pos + back.rotated(side * 1.2) * 8.0
			draw_line(feather_pos, feather_end, wing_col, 1.5)

	# Halo (dim in phase 2)
	var halo_col := Color(0.75, 0.65, 0.80, 0.4)
	if _phase == 2:
		halo_col.a = 0.15
	draw_arc(Vector2(0, -body_radius - 6.0), 8.0, 0.0, TAU, 12, halo_col, 1.5)

	# Spear held forward
	var spear_tip: Vector2 = to_player * (body_radius + 12.0)
	draw_line(to_player * body_radius * 0.3, spear_tip, Color(0.70, 0.65, 0.75), 2.0)

	# Weapon indicator dot
	var icon_pos: Vector2 = to_player * (body_radius * 0.55)
	draw_circle(icon_pos, 4.0, weapon_icon_color)

	# Attack telegraph
	if _ai_state == AIState.WIND_UP and weapon != null:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		match _current_action():
			Action.VOLLEY:
				for i in range(3):
					var spread_dir: Vector2 = to_player.rotated(deg_to_rad((i - 1) * 15.0))
					draw_line(Vector2.ZERO, spread_dir * 160.0, telegraph_color, 1.5)
			Action.SWOOP:
				if weapon_swoop:
					var reach: float = weapon_swoop.swing_range + weapon_swoop.user_lunge_distance
					draw_line(Vector2.ZERO, to_player * reach, telegraph_color, 3.0)
			Action.FLURRY:
				if weapon_flurry:
					var reach: float = weapon_flurry.swing_range + weapon_flurry.arc_radius
					draw_arc(Vector2.ZERO, reach, to_player.angle() - 0.5, to_player.angle() + 0.5, 10, telegraph_color, 2.5)
			Action.STORM:
				if weapon_storm:
					var pulse: float = 0.5 + 0.5 * sin(t * 9.0)
					draw_arc(Vector2.ZERO, weapon_storm.start_radius + pulse * 6.0, 0.0, TAU, 24, telegraph_color, 2.5)
			Action.SOUL_SPEAR:
				if weapon_soul:
					var pulse: float = 0.5 + 0.5 * sin(t * 8.0)
					draw_arc(Vector2.ZERO, weapon_soul.damage_radius + pulse * 4.0, 0.0, TAU, 12, telegraph_color, 2.0)

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
