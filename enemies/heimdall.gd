extends Enemy
## Heimdall (Boss #11, Final Boss) -- the watchman of Bifrost. In the
## myths, Heimdall guards the rainbow bridge between Midgard and Asgard,
## sees all, hears the grass grow, and will blow Gjallarhorn at Ragnarok.
## Here he is the last guardian, standing between the player and whatever
## truth waits at the top of the King's Tower.
##
## ── Design intent ───────────────────────────────────────────────────
## Skill tested: EVERYTHING. Heimdall is the final exam. He has no
## gimmick, no puzzle mechanic -- just clean, fair, demanding combat.
## Every attack is readable, every window is real, but the margin for
## error is razor-thin. He rewards mastery of every prior lesson.
##
## Phase 1 -- The Guardian. Four-beat cycle:
##   HEAVY SWORD   -- overhead strike, high damage, 35px lunge.
##   SHIELD BASH   -- lunging ram (60px), heavy knockback.
##   CROSS STRIKE  -- scissoring sword + shield arc.
##   SPIN ADVANCE  -- whirlwind advance, persistent damage zone.
##
## Phase 2 -- Ragnarok (30% HP). Heimdall shatters the bridge beneath
## him. The arena shrinks. He becomes faster, his recovery windows
## shorter. Summons 2 corrupted knights. This is the DPS check: the
## player must kill the knights while dodging Heimdall's unrelenting
## assault, or be overwhelmed.

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "Heimdall"
@export var boss_id: String = "heimdall"
@export var weapon_heavy: MeleeWeapon
@export var weapon_bash: MeleeWeapon
@export var weapon_cross: MeleeWeapon
@export var weapon_spin: PersistentHitboxWeapon

@export_group("Phase 2")
@export var phase2_threshold: float = 0.30
@export var phase2_speed: float = 100.0
@export var knight_scene: PackedScene
@export var max_knights: int = 2

@export_group("Per-Action Timing")
@export var wind_up_heavy: float = 0.65
@export var wind_up_bash: float = 0.50
@export var wind_up_cross: float = 0.55
@export var wind_up_spin: float = 0.70

@export var recover_heavy: float = 0.55
@export var recover_bash: float = 0.45
@export var recover_cross: float = 0.50
@export var recover_spin: float = 0.60

# ----------------------------------------------------------------------------
# BOSS CONSTANTS
# ----------------------------------------------------------------------------

const BOSS_STAGGER_THRESHOLD: float = 4.0
const BOSS_STUN_BASE: float = 0.4
const BOSS_LONG_STUN: float = 2.5
const BOSS_STAGGER_DECAY: float = 0.45
const BOSS_STAGGER_GAIN: float = 0.8
const BOSS_LEASH_RANGE: float = 0.0
const ENGAGEMENT_RANGE: float = 110.0
const MIN_ENGAGE_BAND: float = 0.0
const KNIGHT_OFFSETS: Array[Vector2] = [Vector2(-80, 60), Vector2(80, 60)]

# ============================================================================
# ACTIONS
# ============================================================================

enum Action { HEAVY_SWORD, SHIELD_BASH, CROSS_STRIKE, SPINNING_ADVANCE }

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

	_cycle = [Action.HEAVY_SWORD, Action.SHIELD_BASH, Action.CROSS_STRIKE, Action.SPINNING_ADVANCE]
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
		_summon_knights()
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


func _summon_knights() -> void:
	if knight_scene == null:
		return
	var parent: Node = get_parent()
	for i in range(mini(max_knights, KNIGHT_OFFSETS.size())):
		var knight: Node2D = knight_scene.instantiate()
		parent.call_deferred("add_child", knight)
		knight.position = position + KNIGHT_OFFSETS[i]

# ============================================================================
# CYCLE MANAGEMENT
# ============================================================================

func _current_action() -> Action:
	return _cycle[_cycle_index]


func _weapon_for_action(a: Action) -> Weapon:
	match a:
		Action.HEAVY_SWORD:      return weapon_heavy
		Action.SHIELD_BASH:      return weapon_bash
		Action.CROSS_STRIKE:     return weapon_cross
		Action.SPINNING_ADVANCE: return weapon_spin
	return null


func _wind_up_for_action(a: Action) -> float:
	match a:
		Action.HEAVY_SWORD:      return wind_up_heavy
		Action.SHIELD_BASH:      return wind_up_bash
		Action.CROSS_STRIKE:     return wind_up_cross
		Action.SPINNING_ADVANCE: return wind_up_spin
	return 0.7


func _recover_for_action(a: Action) -> float:
	match a:
		Action.HEAVY_SWORD:      return recover_heavy
		Action.SHIELD_BASH:      return recover_bash
		Action.CROSS_STRIKE:     return recover_cross
		Action.SPINNING_ADVANCE: return recover_spin
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

	# Guardian silhouette -- broad-shouldered, shield + sword
	_draw_body(body)

	# Shield (left side)
	var shield_pos: Vector2 = to_player.rotated(-0.5) * body_radius * 0.6
	draw_rect(Rect2(shield_pos - Vector2(6, 10), Vector2(12, 20)),
		Color(0.65, 0.60, 0.50))
	draw_rect(Rect2(shield_pos - Vector2(4, 8), Vector2(8, 16)),
		Color(0.75, 0.70, 0.60))

	# Sword (right side)
	var sword_base: Vector2 = to_player.rotated(0.4) * body_radius * 0.5
	var sword_tip: Vector2 = to_player.rotated(0.3) * (body_radius + 16.0)
	draw_line(sword_base, sword_tip, Color(0.80, 0.78, 0.72), 2.5)

	# Rainbow shimmer on armor
	var rainbow_phase: float = fmod(t * 0.5, 1.0)
	var shimmer := Color.from_hsv(rainbow_phase, 0.3, 0.8, 0.25)
	draw_arc(Vector2.ZERO, body_radius * 0.8, 0.0, TAU, 16, shimmer, 2.0)

	# Helm eye slit
	var eye_pos: Vector2 = to_player * body_radius * 0.35
	draw_line(eye_pos - to_player.rotated(PI*0.5) * 4.0,
		eye_pos + to_player.rotated(PI*0.5) * 4.0,
		Color(0.90, 0.85, 0.60), 2.0)

	# Weapon indicator dot
	var icon_pos: Vector2 = to_player * (body_radius * 0.55)
	draw_circle(icon_pos, 4.0, weapon_icon_color)

	# Attack telegraph
	if _ai_state == AIState.WIND_UP and weapon != null:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		var aim_angle: float = to_player.angle()
		match _current_action():
			Action.HEAVY_SWORD:
				if weapon_heavy:
					var reach: float = weapon_heavy.swing_range + weapon_heavy.arc_radius + weapon_heavy.user_lunge_distance
					draw_arc(Vector2.ZERO, reach, aim_angle - 0.5, aim_angle + 0.5, 10, telegraph_color, 3.0)
			Action.SHIELD_BASH:
				if weapon_bash:
					var reach: float = weapon_bash.swing_range + weapon_bash.user_lunge_distance
					draw_line(Vector2.ZERO, to_player * reach, telegraph_color, 4.0)
			Action.CROSS_STRIKE:
				if weapon_cross:
					var reach: float = weapon_cross.swing_range + weapon_cross.arc_radius
					draw_arc(Vector2.ZERO, reach, aim_angle - 0.7, aim_angle + 0.7, 12, telegraph_color, 2.5)
			Action.SPINNING_ADVANCE:
				if weapon_spin:
					var pulse: float = 0.5 + 0.5 * sin(t * 10.0)
					draw_arc(Vector2.ZERO, weapon_spin.length + pulse * 5.0, 0.0, TAU, 20, telegraph_color, 2.5)

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
