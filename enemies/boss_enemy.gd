extends Enemy
## Skeleton King — first boss. Teaches the player the core combat loop:
## reading wind-up telegraphs, timing parries, and punishing recovery
## windows. Two attacks, both with long windups and large hitboxes:
##
##   SWIPE  — wide melee arc when the player is within swipe range.
##            The default attack. Slow enough that the player can
##            recognize the red flash, learn the parry window, and
##            dodge through it.
##
##   LUNGE  — long forward surge when the player stays out of swipe
##            range for too long (`lunge_patience` seconds). Punishes
##            pure kiting without making ranged play impossible — the
##            timer resets every time the player enters swipe range,
##            so weaving in and out is the intended rhythm.
##
## Phase 2 at low HP spawns four Bone Pillars (stationary hazards) and
## speeds up the windups, raising the pressure without adding new reads.
##
## ── Design intent (game-critic notes) ──────────────────────────────
## A first boss exists to TEACH, not to test. The player has just
## learned basic movement and attacks through the tutorial and early
## rooms. The Skeleton King's job is to validate that they can:
##   1. Read a wind-up telegraph (yellow → red flash)
##   2. Time a parry (red flash = stagger window)
##   3. Recognize a recovery window (post-attack plant = free hits)
##   4. Manage spacing (lunge punishes passive kiting)
## Every attack has a generous telegraph and a large-enough hitbox that
## mistakes are punished clearly. No projectile dodging, no multi-phase
## pattern memorization — just the melee combat loop, front and center.
##
## The old three-weapon ranged rotation (Royal Bone Toss / Fan / Burst)
## is preserved in its .tres files for reuse on a later boss where the
## player has already internalized the basics and is ready for projectile
## patterns. Those weapons are NOT referenced by this script.

# ============================================================================
# BOSS CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "Skeleton King"
## Identifier used for GameState.mark_boss_dead and the
## `boss_dead_<id>` story flag. KenningManager listens on this flag
## to unlock the kenning whose unlock_flag matches — Bone-King's-Bane
## currently keys off "boss_dead_skeleton_king".
@export var boss_id: String = "skeleton_king"
## Close-range arm swipe — wide arc, high knockback, long wind-up.
## The default attack when the player is within swipe range.
@export var weapon_swipe: MeleeWeapon
## Distance-punish lunge — long surge forward, narrower hitbox, higher
## damage. Fires when the player has been outside swipe range for
## `lunge_patience` seconds continuously.
@export var weapon_lunge: MeleeWeapon
## Scene to spawn as pillars in phase 2.
@export var pillar_scene: PackedScene
## Phase 2 threshold (fraction of max HP).
@export var phase2_threshold: float = 0.30
## Wind-up / recover overrides for phase 2 (faster).
@export var phase2_wind_up: float = 0.55
@export var phase2_recover: float = 0.35

## --- LEGACY: ranged weapons for a later boss (DO NOT DELETE) ---
## These were the original Skeleton King rotation. They're well-tuned
## projectile patterns that belong on a mid-game boss who can assume
## the player already knows melee fundamentals. Reference them from a
## future boss's .tscn when you need a ranged rotation.
##   res://weapons/instances/enemy_weapons/skeleton_king_toss.tres
##   res://weapons/instances/enemy_weapons/skeleton_king_fan.tres
##   res://weapons/instances/enemy_weapons/skeleton_king_burst.tres
## The exports below are kept so the .tscn can still load without
## errors during the transition. They are not used by this script.
@export var weapon_toss: Weapon
@export var weapon_fan: Weapon
@export var weapon_burst: Weapon

@export_group("Lunge Behavior")
## How long the player must stay outside swipe range before the boss
## commits to a lunge. Shorter = more aggressive anti-kite; longer =
## more forgiving to ranged-leaning players. 2.5s is a comfortable
## "you've been away long enough that I'm coming to get you" beat.
@export var lunge_patience: float = 2.5
## Phase 2 lunge patience — tighter, matching the faster windups.
@export var phase2_lunge_patience: float = 1.6

## Boss stagger defaults — harder than mooks.
const BOSS_STAGGER_THRESHOLD: float = 3.0
const BOSS_STUN_BASE: float = 0.5
const BOSS_LONG_STUN: float = 3.0
const BOSS_STAGGER_DECAY: float = 0.4
const BOSS_STAGGER_GAIN: float = 1.0
const BOSS_LEASH_RANGE: float = 0.0

# ============================================================================
# RUNTIME STATE
# ============================================================================

var _phase: int = 1
var _phase2_triggered: bool = false
var _pillars_spawned: bool = false
var _engaged: bool = false

## Accumulates while the player is outside swipe range. When this
## exceeds the patience threshold, the boss switches to lunge.
## Resets to 0 whenever the player enters swipe range.
var _out_of_range_timer: float = 0.0
## True when the boss has committed to a lunge for this attack cycle.
## Cleared after the attack fires (in _process_attack override).
var _lunge_committed: bool = false

## Pillar spawn positions (relative to boss room center).
const PILLAR_OFFSETS := [
	Vector2(-300, -220),
	Vector2(300, -220),
	Vector2(-300, 220),
	Vector2(300, 220),
]


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

	# Default weapon is the swipe — the CHASE → WIND_UP transition in
	# the base class reads `weapon` and `_attack_range`, so setting
	# them here means the boss starts looking for swipe opportunities
	# immediately.
	if weapon_swipe:
		weapon = weapon_swipe
		_attack_range = weapon.effective_range()

	health_component.health_changed.connect(_on_boss_health_changed)
	health_component.died.connect(_on_boss_died)
	base_detection = 9999.0


## Override the base hook so the HUD's boss stagger bar updates.
func _emit_stagger_if_boss() -> void:
	if _engaged:
		EventBus.boss_stagger_changed.emit(_stagger, stagger_threshold)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	if not _engaged:
		_engaged = true
		EventBus.boss_engaged.emit(boss_display_name, current, maximum)

	EventBus.boss_health_changed.emit(current, maximum)

	if not _phase2_triggered and current <= maximum * phase2_threshold:
		_phase2_triggered = true
		_phase = 2
		wind_up_duration = phase2_wind_up
		recover_duration = phase2_recover
		EventBus.boss_phase_changed.emit(2)
		_spawn_pillars()


func _physics_process(delta: float) -> void:
	super(delta)
	if not _engaged and _ai_state != AIState.IDLE:
		_engaged = true
		var hp: float = health_component.current_health if health_component else max_health
		var hp_max: float = health_component.max_health if health_component else max_health
		EventBus.boss_engaged.emit(boss_display_name, hp, hp_max)
		EventBus.boss_stagger_changed.emit(_stagger, stagger_threshold)


# ============================================================================
# WEAPON SELECTION — distance-based swipe / lunge
# ============================================================================

## Override the base _process_chase to implement the lunge-patience
## mechanic. The base class handles approach movement, engagement band,
## and the CHASE → WIND_UP trigger on `_attack_range`. We layer our
## logic on top: track how long the player has been outside swipe range,
## and when the patience timer fires, commit to a lunge.
func _process_chase(delta: float) -> void:
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return

	var dist: float = global_position.distance_to(_player.global_position)
	var effective_speed: float = max_speed \
		* status_component.get_speed_multiplier() \
		* DifficultySettings.get_enemy_speed_multiplier()

	var swipe_range: float = weapon_swipe.effective_range() if weapon_swipe else _attack_range

	if dist <= swipe_range:
		# Player is in swipe range — reset the kite timer and attack.
		_out_of_range_timer = 0.0
		_lunge_committed = false
		if weapon_swipe:
			weapon = weapon_swipe
			_attack_range = weapon.effective_range()
			_current_attack_weapon = weapon_swipe
			_attack_sprite_row = 0
			_ai_state = AIState.WIND_UP
			_state_timer = wind_up_duration
			velocity = Vector2.ZERO
			return
	else:
		# Player is outside swipe range — accumulate the kite timer.
		_out_of_range_timer += delta
		var patience: float = phase2_lunge_patience if _phase == 2 else lunge_patience
		if _out_of_range_timer >= patience and weapon_lunge:
			# Commit to a lunge: set the lunge weapon, widen the
			# attack_range so the base-class range check doesn't
			# block entry to WIND_UP, and fire.
			_lunge_committed = true
			_out_of_range_timer = 0.0
			weapon = weapon_lunge
			_attack_range = weapon_lunge.effective_range()
			_current_attack_weapon = weapon_lunge
			_attack_sprite_row = 1
			_ai_state = AIState.WIND_UP
			_state_timer = wind_up_duration
			velocity = Vector2.ZERO
			return

	# Not attacking this frame — keep approaching.
	_apply_engagement_band_movement(delta, effective_speed)


## After the attack fires, reset weapon to swipe for the next cycle.
func _process_attack() -> void:
	if _player == null or (weapon_swipe == null and weapon_lunge == null):
		_ai_state = AIState.RECOVER
		_state_timer = recover_duration
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	var firing: Weapon = _current_attack_weapon
	if firing == null:
		firing = weapon_swipe if weapon_swipe else weapon_lunge

	# Apply lunge velocity if this is the lunge weapon.
	if firing is MeleeWeapon:
		var melee: MeleeWeapon = firing
		if melee.user_lunge_distance > 0.0:
			velocity = aim * sqrt(2.0 * acceleration * melee.user_lunge_distance)

	firing.attack(self, aim)

	# Reset to swipe for the next engagement cycle.
	_lunge_committed = false
	if weapon_swipe:
		weapon = weapon_swipe
		_attack_range = weapon_swipe.effective_range()

	_ai_state = AIState.RECOVER
	_state_timer = recover_duration
	_current_attack_weapon = null


## Keep pressing during RECOVER — bosses own their arena.
func _process_recover(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_ai_state = AIState.CHASE
		return
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	var effective_speed: float = max_speed \
		* status_component.get_speed_multiplier() \
		* DifficultySettings.get_enemy_speed_multiplier()
	_apply_engagement_band_movement(delta, effective_speed)


# ============================================================================
# PHASE 2 — PILLAR SPAWNS
# ============================================================================

func _spawn_pillars() -> void:
	if _pillars_spawned or pillar_scene == null:
		return
	_pillars_spawned = true

	var parent := get_parent()
	if not is_instance_valid(parent):
		return

	for i in PILLAR_OFFSETS.size():
		var pillar: Node2D = pillar_scene.instantiate()
		pillar.name = "BossPillar%d" % i
		parent.call_deferred("add_child", pillar)
		pillar.position = PILLAR_OFFSETS[i]


# ============================================================================
# DEATH SEQUENCE
# ============================================================================

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
# DRAW OVERRIDE — crown + melee telegraph
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
		body = body.lerp(Color(0.55, 0.20, 0.65), 0.25)

	var tint: Color = status_component.get_tint()
	if tint.a > 0.0:
		body = body.lerp(Color(tint.r, tint.g, tint.b, 1.0), tint.a)

	# Body shape (uses the CROWN polygon from base enemy's shape system).
	_draw_body(body)

	# Crown — three points above the head.
	var crown_color := Color(0.95, 0.80, 0.20) if _phase == 1 else Color(0.70, 0.35, 0.80)
	var crown_y := -body_radius - 4.0
	var pts := PackedVector2Array([
		Vector2(-10, crown_y),
		Vector2(-7, crown_y - 10),
		Vector2(-3, crown_y - 4),
		Vector2(0, crown_y - 14),
		Vector2(3, crown_y - 4),
		Vector2(7, crown_y - 10),
		Vector2(10, crown_y),
	])
	draw_colored_polygon(pts, crown_color)

	# Weapon indicator dot.
	var icon_dir: Vector2 = Vector2.RIGHT
	if is_instance_valid(_player):
		icon_dir = (_player.global_position - global_position).normalized()
	var icon_pos: Vector2 = icon_dir * (body_radius * 0.5)
	draw_circle(icon_pos, 4.0, weapon_icon_color)

	# Attack telegraph — uses the base system. During a lunge wind-up,
	# draw a directional thrust indicator; during a swipe, draw the
	# standard arc. Both use the same color timing (yellow → red at
	# STAGGER_WINDOW) so the parry cue is consistent.
	if _ai_state == AIState.WIND_UP:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		if _lunge_committed and weapon_lunge:
			# Lunge telegraph: a line + arrow pointing at the player,
			# showing the direction and reach of the surge.
			var lunge_reach: float = weapon_lunge.effective_range()
			var tip: Vector2 = icon_dir * lunge_reach
			draw_line(Vector2.ZERO, tip, telegraph_color, 3.0)
			# Arrow head.
			var perp: Vector2 = icon_dir.rotated(PI * 0.5) * 8.0
			var arrow_base: Vector2 = tip - icon_dir * 14.0
			draw_colored_polygon(PackedVector2Array([tip, arrow_base + perp, arrow_base - perp]),
				telegraph_color)
		elif weapon_swipe:
			# Swipe telegraph: wide arc showing the sweep area.
			var reach: float = weapon_swipe.effective_range()
			var telegraph_pos: Vector2 = icon_dir * (reach * 0.4)
			draw_arc(telegraph_pos, reach * 0.6, 0.0, TAU, 24, telegraph_color, 2.5)

	# HP bar.
	var hp_pct: float = health_component.health_percent() if health_component else 1.0
	var bar_w: float = body_radius * 2.0
	var bar_y: float = -body_radius - 20.0
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w, 4)), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w * hp_pct, 4)), Color(0.85, 0.25, 0.25))

	# Stun stars.
	if _ai_state == AIState.STUNNED:
		var t: float = Time.get_ticks_msec() / 1000.0
		for i in range(3):
			var a: float = t * 6.0 + i * (TAU / 3.0)
			var p := Vector2(cos(a), -0.3 + sin(a) * 0.15) * 14.0 + Vector2(0, -body_radius - 18.0)
			draw_circle(p, 2.4, Color(1.0, 0.95, 0.5))
	elif _ai_state != AIState.IDLE:
		draw_circle(Vector2(0, -2), 2.5, Color(1, 0.95, 0.5))
