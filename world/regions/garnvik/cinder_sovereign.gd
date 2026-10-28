extends Enemy
## Cinder Sovereign — second boss, fire-themed. Easier than the Skeleton
## King in raw numbers (less HP, earlier phase shift, fewer projectiles
## per burst), but the *type* of pressure is different: persistent
## hitboxes you must position out of, not bullet rings you weave through.
##
## Phase 1 cycles three attacks in order:
##   1. Sovereign Pyre — wide forward cone, 2.5s persistent. Telegraphed
##      by a yellow→red cone outline at the windup spot.
##   2. Sovereign Cinder Pod — slow projectile that explodes into 6
##      shrapnel pieces in a ring when its lifetime ends. Walk through
##      to absorb the pod (less total damage); dodge but stay clear of
##      where it lands (more damage if caught by shrapnel).
##   3. Summon — spawns an Ember-bearer minion behind the boss. Gated
##      by max_minions_in_room: if 2+ summoned-team spears are alive
##      the action is SKIPPED entirely (no windup, no spawn) and the
##      cycle advances. This rewards the player for clearing minions
##      promptly — keep them alive and the boss "wastes" cycle slots
##      summoning; kill them fast and the boss attacks faster.
##
## Phase 2 (≤40% HP) adds a fourth attack to the cycle:
##   4. Sun Lance — a long thin beam (~720px reach). Same persistent-
##      hitbox principle as the Pyre but a different shape: laterally
##      dodgeable, frontally devastating, telegraphed by a rectangle
##      outline.
##
## Engagement: the boss fights at a fixed ~180px from the player
## regardless of current cycle slot, sized so that:
##   - the cone (170 reach) catches a player who doesn't move
##   - the pod (~273 reach) lands at midrange
##   - the beam (~720 reach) sweeps far past the player but still
##     covers them if in line
## A single consistent fighting distance lets the player learn the
## boss's spacing once, then focus on *which* attack is coming next
## rather than juggling positioning.

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "Cinder Sovereign"
## Identifier used for GameState.mark_boss_dead and the
## `boss_dead_<id>` story flag. KenningManager unlocks the kenning
## whose unlock_flag matches — Ash-Walker keys off
## "boss_dead_cinder_sovereign" (a fire-creature defeat).
@export var boss_id: String = "cinder_sovereign"
## Phase-1 weapons.
@export var weapon_flamethrower: PersistentHitboxWeapon
@export var weapon_pod: ExplodingRangedWeapon
## Phase-2 addition. Wired in the .tscn; used only after phase 2 triggers.
@export var weapon_beam: PersistentHitboxWeapon

@export_group("Summon")
@export var minion_scene: PackedScene
## Distance behind the boss to spawn a summoned minion. Behind = opposite
## the player direction at summon time. 60px puts the minion outside
## the boss body but inside its visual silhouette.
@export var minion_spawn_offset: float = 60.0
## Skip the Summon action when this many minions from prior summons are
## already alive. 2 is the sweet spot from playtesting: one is trivial,
## three+ overwhelms the player's parry attention.
@export var max_minions_in_room: int = 2

@export_group("Phase 2")
## Phase 2 triggers at or below this fraction of max HP. 0.40 (vs Bone
## King's 0.30) means the player sees the beam attack earlier in the
## fight — more time to learn it before the boss dies.
@export var phase2_threshold: float = 0.40
## In phase 2 the boss winds up faster — keeps pressure on as the
## player closes the kill.
@export var phase2_wind_up: float = 0.50

@export_group("Per-Action Recover")
## How long the boss is "rooted" after each attack type. Persistent
## hitbox attacks MUST have recover >= duration so the boss can't fire
## another while the previous cone/beam is still alive (which would
## stack two zones and look wrong). Other attacks get short recover
## so the cycle keeps pace.
@export var recover_flamethrower: float = 2.6
@export var recover_pod: float = 0.75
@export var recover_summon: float = 0.50
@export var recover_beam: float = 2.1

## Wind-up for the Summon action specifically — kept shorter than
## damage-dealing windups since the summon isn't directly threatening
## (the minion has to walk over). Quick "puff into being" cue.
@export var wind_up_summon: float = 0.60

# ----------------------------------------------------------------------------
# BOSS-WIDE CONSTANTS (mirroring boss_enemy.gd's pattern)
# ----------------------------------------------------------------------------

## Boss stagger threshold — same value as the Bone King so the
## "parry three times for the punish" learning transfers directly.
const BOSS_STAGGER_THRESHOLD: float = 3.0
const BOSS_STUN_BASE: float = 0.5
const BOSS_LONG_STUN: float = 3.0
const BOSS_STAGGER_DECAY: float = 0.4
const BOSS_STAGGER_GAIN: float = 1.0
const BOSS_LEASH_RANGE: float = 0.0

## Fixed engagement distance. Boss prefers to fight here regardless of
## current cycle slot. Sized to keep the cone (170 reach) reliably
## catching a stationary player while not getting in melee tickle range.
const ENGAGEMENT_RANGE: float = 180.0
const MIN_ENGAGE_BAND: float = 130.0  # boss reverses if player closes inside this

# ============================================================================
# ACTIONS
# ============================================================================

enum Action { FLAMETHROWER, POD, SUMMON, BEAM }

## Phase-specific cycles. Built in _ready and rebuilt on phase change.
## Order matters — it's the rhythm the player learns.
var _cycle: Array[Action] = []
var _cycle_index: int = 0
var _phase: int = 1
var _phase2_triggered: bool = false
var _engaged: bool = false

## Tracking list of summoned minions for the cap check. We hold weak
## refs via instance_valid() so dead/freed minions don't keep the cap
## artificially full.
var _summoned_minions: Array[Node] = []


# ============================================================================
# READY
# ============================================================================

func _ready() -> void:
	super()

	# Boss-tuned stagger / leash override. Same pattern as boss_enemy.gd
	# — centralize tunables in code so all bosses inherit the rules and
	# only need .tscn tweaks for their unique weapons.
	stagger_threshold = BOSS_STAGGER_THRESHOLD
	stun_duration_base = BOSS_STUN_BASE
	stagger_long_stun_duration = BOSS_LONG_STUN
	stagger_decay_rate = BOSS_STAGGER_DECAY
	stagger_gain_per_hit = BOSS_STAGGER_GAIN
	leash_range = BOSS_LEASH_RANGE

	# Build the initial cycle. Phase 1 = [pyre, pod, summon]; that's
	# the rhythm the player learns first. Phase 2 inserts the beam
	# after summon: [pyre, pod, summon, beam].
	_build_cycle_for_phase(_phase)
	_cycle_index = 0

	# Lock the engagement range to a fixed value (see header comment).
	# Don't update this on cycle advance — the boss stays at a single
	# learnable fighting distance.
	_attack_range = ENGAGEMENT_RANGE
	min_engage_range = MIN_ENGAGE_BAND

	# A weapon reference is required for the WIND_UP→ATTACK→RECOVER
	# pipeline (Enemy.gd guards on weapon != null). Set it to the
	# current cycle's weapon so the base class is happy; we override
	# `weapon` ourselves before each fire in _process_attack.
	weapon = _weapon_for_action(_cycle[_cycle_index])
	_sync_attack_sprite_row()

	# Listen to our own health for phase transitions. Same pattern as
	# boss_enemy.gd — we own the phase logic, not the HealthComponent.
	health_component.health_changed.connect(_on_boss_health_changed)
	health_component.died.connect(_on_boss_died)

	# Boss always starts aggressive — engages on sight, no detection roll.
	base_detection = 9999.0


# Fire boss_engaged the instant the boss leaves IDLE. Same belt-and-
# braces pattern as boss_enemy.gd: latch via _engaged so we only emit
# once even if the AI state oscillates.
func _physics_process(delta: float) -> void:
	super(delta)
	if not _engaged and _ai_state != AIState.IDLE:
		_engaged = true
		var hp: float = health_component.current_health if health_component else max_health
		var hp_max: float = health_component.max_health if health_component else max_health
		EventBus.boss_engaged.emit(boss_display_name, hp, hp_max)
		EventBus.boss_stagger_changed.emit(_stagger, stagger_threshold)


# Override the stagger emit hook so the HUD bar updates while engaged.
# No-ops before engagement so the boss doesn't pre-show a stagger bar.
func _emit_stagger_if_boss() -> void:
	if _engaged:
		EventBus.boss_stagger_changed.emit(_stagger, stagger_threshold)


# ============================================================================
# HEALTH / PHASE TRANSITION
# ============================================================================

func _on_boss_health_changed(current: float, maximum: float) -> void:
	# Belt-and-braces engagement trigger — primary trigger is the
	# state-machine check in _physics_process. This branch fires only
	# if the boss takes damage before its AI state machine has run
	# (same edge case as boss_enemy.gd's same-named handler).
	if not _engaged:
		_engaged = true
		EventBus.boss_engaged.emit(boss_display_name, current, maximum)
	EventBus.boss_health_changed.emit(current, maximum)

	# Phase 2 transition. Latched — never reverts on heal.
	if not _phase2_triggered and current <= maximum * phase2_threshold:
		_phase2_triggered = true
		_phase = 2
		wind_up_duration = phase2_wind_up
		_build_cycle_for_phase(_phase)
		# Don't reset _cycle_index — let the current pre-phase-2 commit
		# play out, then resume into the phase-2 cycle. Modulo wraps
		# the index into the new cycle's length safely.
		_cycle_index = _cycle_index % _cycle.size()
		EventBus.boss_phase_changed.emit(2)


func _on_boss_died() -> void:
	# Same flow as boss_enemy.gd:
	#   1) emit boss_defeated for HUD fade-out
	#   2) mark boss dead in GameState → writes boss_dead_cinder_sovereign,
	#      which Ash-Walker keys off (a "fire creature defeated" unlock).
	#   3) play the spectacle — fade-out, ash burst, falls text, bonus
	#      currency, hit-stop, screen shake. The spectacle defers
	#      queue_free until after the fade.
	EventBus.boss_defeated.emit(boss_display_name)
	GameState.mark_boss_dead(boss_id)
	BossDeathFx.play(self, boss_display_name, body_tint)


## Override base Enemy _on_died so the boss isn't queue_freed instantly.
## Same pattern as boss_enemy.gd — fire the bookkeeping signals and
## drops, but skip queue_free; the spectacle (triggered by the
## separately-connected _on_boss_died handler) schedules the free
## at the end of its fade tween.
func _on_died() -> void:
	EventBus.entity_died.emit(self)
	EventBus.enemy_killed.emit(self, _last_hit_info)
	RunState.mark_node_consumed(self)
	call_deferred("_spawn_drops_at", global_position, get_parent())
	# Queue_free is deferred by BossDeathFx.play (invoked from _on_boss_died).


# ============================================================================
# CYCLE MANAGEMENT
# ============================================================================

func _build_cycle_for_phase(p: int) -> void:
	_cycle.clear()
	# Order is the chord progression of the fight. Pyre/Pod/Summon is
	# "pressure, projectile, pressure-release"; phase 2 inserts the
	# Beam between Summon and the next Pyre — a long-range hammer to
	# punctuate each rotation.
	if p == 1:
		_cycle = [Action.FLAMETHROWER, Action.POD, Action.SUMMON]
	else:
		_cycle = [Action.FLAMETHROWER, Action.POD, Action.SUMMON, Action.BEAM]


## Returns the Weapon resource that backs an Action, or null for
## actions that don't fire a weapon (Summon). Used to drive the base
## Enemy class's `weapon` field, which is what state-machine code
## like _process_chase reads to decide attack range and existence.
func _weapon_for_action(a: Action) -> Weapon:
	match a:
		Action.FLAMETHROWER: return weapon_flamethrower
		Action.POD:          return weapon_pod
		Action.BEAM:         return weapon_beam
		Action.SUMMON:       return weapon_flamethrower  # placeholder — see below
	return null


## Skip the SUMMON action if minions are capped. Loop with a safety
## bound so even a pathological "every cycle slot is SUMMON and capped"
## state can't infinite-loop. In practice the cycle always contains
## at least one non-summon attack.
func _skip_capped_summons() -> void:
	var safety: int = _cycle.size()
	while _cycle[_cycle_index] == Action.SUMMON and _count_live_minions() >= max_minions_in_room:
		_cycle_index = (_cycle_index + 1) % _cycle.size()
		safety -= 1
		if safety <= 0:
			break


func _count_live_minions() -> int:
	# Compact the list as we go so it doesn't grow unbounded over the
	# fight as minions die. Iterating once and rebuilding is cheaper
	# than a separate prune pass.
	var live: Array[Node] = []
	for m in _summoned_minions:
		if is_instance_valid(m):
			live.append(m)
	_summoned_minions = live
	return live.size()


# ============================================================================
# ATTACK PROCESSING — override the base single-weapon attack
# ============================================================================

func _process_attack() -> void:
	if _player == null:
		_ai_state = AIState.RECOVER
		_state_timer = recover_pod
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	var action: Action = _cycle[_cycle_index]
	var attack_recover: float = 0.0

	match action:
		Action.FLAMETHROWER:
			if weapon_flamethrower:
				weapon_flamethrower.attack(self, aim)
			attack_recover = recover_flamethrower
		Action.POD:
			if weapon_pod:
				weapon_pod.attack(self, aim)
			attack_recover = recover_pod
		Action.SUMMON:
			_perform_summon(aim)
			attack_recover = recover_summon
		Action.BEAM:
			if weapon_beam:
				weapon_beam.attack(self, aim)
			attack_recover = recover_beam

	# Advance the cycle pointer, then skip any SUMMON slot we can't fire.
	# Skipping happens AFTER the fire so the next windup-target already
	# reflects the next real attack.
	_cycle_index = (_cycle_index + 1) % _cycle.size()
	_skip_capped_summons()

	# Update the `weapon` slot so the base WIND_UP/CHASE pipeline reads
	# the correct attack on the NEXT cycle iteration. _attack_range
	# stays fixed at ENGAGEMENT_RANGE regardless of cycle index.
	weapon = _weapon_for_action(_cycle[_cycle_index])
	_sync_attack_sprite_row()

	# Use the longer summon wind-up specifically for the SUMMON slot, so
	# the player gets a slightly different cue (shorter than flamethrower,
	# longer than nothing) — a "I'm casting" cadence rather than the
	# regular fast pre-attack flash.
	if _cycle[_cycle_index] == Action.SUMMON:
		wind_up_duration = wind_up_summon
	else:
		wind_up_duration = phase2_wind_up if _phase == 2 else 0.85

	_ai_state = AIState.RECOVER
	_state_timer = attack_recover


## Override RECOVER to keep advancing on the player. Same rationale as
## boss_enemy.gd's override: the Sovereign's persistent attacks have
## long recover times (2.6s flamethrower, 2.1s beam), and a stationary
## RECOVER turns the boss into a turret. Sweeping forward while the
## flame cone is still alive also keeps the pressure on — the cone is
## anchored to the boss's position, so a forward-walking boss drags
## its plume right after a retreating player.
##
## We intentionally do NOT move during WIND_UP — the telegraph must
## render at a fixed location so the player can read the shape and
## sidestep. We also don't change *which* attack is next; the cycle
## advance happens inside _process_attack and isn't affected by
## continued movement.
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
# SUMMON
# ============================================================================

func _perform_summon(aim: Vector2) -> void:
	# Hard re-check just before the spawn — possible the player killed
	# a minion *during* the windup, but we want to keep the cap honest
	# at the moment of spawn.
	if _count_live_minions() >= max_minions_in_room:
		return
	if minion_scene == null:
		return

	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return

	# Spawn position is "behind" the boss — opposite the player aim.
	# Defensive: if aim degenerates, fall back to left of the boss so
	# the minion still spawns somewhere visible.
	var behind: Vector2 = -aim
	if behind == Vector2.ZERO:
		behind = Vector2.LEFT
	var spawn_pos: Vector2 = global_position + behind * minion_spawn_offset

	var minion: Enemy = minion_scene.instantiate()
	# Add to tree FIRST so RunState / _ready can run with a valid parent.
	parent.call_deferred("add_child", minion)
	minion.position = spawn_pos
	# Track for cap. Deferred-add means _ready runs next frame, so this
	# reference is fine for tracking but is_instance_valid won't go
	# false until queue_free runs after a kill — exactly what we want.
	_summoned_minions.append(minion)


# ============================================================================
# DRAW OVERRIDE — phase-tinted body, crown, shape-aware telegraph
# ============================================================================

## Sovereign _draw is animated (phase visuals, wind-up flash, crown), so it
## must redraw every frame even if it ever gains a sprite.
func _draw_animates_per_frame() -> bool:
	return true


func _draw() -> void:
	# Phase-aware tint, identical structure to boss_enemy.gd's _draw
	# so the crown/HP/stagger language is consistent across bosses.
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

	# Phase 2 tints the body deeper red — visual cue that the fight
	# has escalated. Subtle enough not to clash with the parry-flash
	# colors above (those overlay on top).
	if _phase == 2:
		body = body.lerp(Color(0.95, 0.30, 0.10), 0.30)

	var tint: Color = status_component.get_tint()
	if tint.a > 0.0:
		body = body.lerp(Color(tint.r, tint.g, tint.b, 1.0), tint.a)

	draw_circle(Vector2.ZERO, body_radius, body)

	# Crown of flame — three "tongues" instead of the Bone King's
	# pointy three-spike crown. Phase 2 brightens to white-hot.
	var crown_color := Color(1.00, 0.55, 0.10) if _phase == 1 else Color(1.00, 0.85, 0.30)
	var crown_y := -body_radius - 4.0
	var pts := PackedVector2Array([
		Vector2(-12, crown_y),
		Vector2(-9, crown_y - 8),
		Vector2(-5, crown_y - 14),
		Vector2(-2, crown_y - 6),
		Vector2(0, crown_y - 16),
		Vector2(2, crown_y - 6),
		Vector2(5, crown_y - 14),
		Vector2(9, crown_y - 8),
		Vector2(12, crown_y),
	])
	draw_colored_polygon(pts, crown_color)

	# Weapon indicator — different glyph per cycle slot. Helps the
	# player read "what's next" at a glance during chase/recover.
	var icon_dir: Vector2 = Vector2.RIGHT
	if is_instance_valid(_player):
		icon_dir = (_player.global_position - global_position).normalized()
	var icon_pos: Vector2 = icon_dir * (body_radius * 0.5)
	var icon_color: Color = _icon_color_for_next_action()
	draw_circle(icon_pos, 4.0, icon_color)

	# Attack telegraph — shape-aware. Uses the same red/yellow logic
	# as the base class but delegates to _draw_attack_telegraph for
	# the actual geometry, which we override below.
	if _ai_state == AIState.WIND_UP and weapon != null:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		_draw_attack_telegraph(icon_dir, telegraph_color)

	# HP bar (proximity nameplate — main bar is the HUD's panel).
	var hp_pct: float = health_component.health_percent() if health_component else 1.0
	var bar_w: float = body_radius * 2.0
	var bar_y: float = -body_radius - 20.0
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w, 4)), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w * hp_pct, 4)), Color(0.95, 0.40, 0.15))

	# Stunned stars / engaged dot — same affordances as the base class.
	if _ai_state == AIState.STUNNED:
		var t: float = Time.get_ticks_msec() / 1000.0
		for i in range(3):
			var a: float = t * 6.0 + i * (TAU / 3.0)
			var p := Vector2(cos(a), -0.3 + sin(a) * 0.15) * 14.0 + Vector2(0, -body_radius - 18.0)
			draw_circle(p, 2.4, Color(1.0, 0.95, 0.5))
	elif _ai_state != AIState.IDLE:
		draw_circle(Vector2(0, -2), 2.5, Color(1, 0.95, 0.5))


## Color hint of the NEXT action so the player can read the cycle.
## Subtle but useful — players who notice it can pre-position.
func _icon_color_for_next_action() -> Color:
	match _cycle[_cycle_index]:
		Action.FLAMETHROWER: return Color(1.00, 0.50, 0.10)   # deep flame
		Action.POD:          return Color(1.00, 0.55, 0.35)   # pod/shrapnel hue
		Action.SUMMON:       return Color(0.95, 0.85, 0.30)   # gold — "casting"
		Action.BEAM:         return Color(1.00, 0.95, 0.80)   # white-hot
	return weapon_icon_color


## Shape-aware telegraph: cone for flamethrower-style attacks,
## rectangle outline for beams, the default circle for projectile
## attacks (pod, summon). Lets the player position out of the
## upcoming hitbox by reading the windup shape directly.
func _draw_attack_telegraph(icon_dir: Vector2, telegraph_color: Color) -> void:
	# Look at the *current cycle slot* (the action we're winding up
	# for), not the `weapon` field, because for SUMMON the weapon field
	# is a placeholder.
	var action: Action = _cycle[_cycle_index]
	var aim_angle: float = icon_dir.angle()

	match action:
		Action.FLAMETHROWER:
			if weapon_flamethrower:
				_draw_cone_telegraph(aim_angle,
					weapon_flamethrower.length,
					weapon_flamethrower.cone_angle_degrees,
					telegraph_color)
		Action.BEAM:
			if weapon_beam:
				_draw_rect_telegraph(aim_angle,
					weapon_beam.length,
					weapon_beam.rect_width,
					telegraph_color)
		Action.POD:
			# Pod is a projectile — keep the default circle telegraph
			# so the player knows "something is coming from there,"
			# but the actual spread is at the impact point, not here.
			super(icon_dir, telegraph_color)
		Action.SUMMON:
			# Small ring behind the boss to signal "something will
			# appear here." Less aggressive than the danger telegraph
			# colors because the summon itself isn't directly damaging.
			var behind_dir: Vector2 = -icon_dir
			var summon_pos: Vector2 = behind_dir * minion_spawn_offset
			var pulse_alpha: float = 0.35 + 0.25 * sin(Time.get_ticks_msec() / 80.0)
			draw_arc(summon_pos, 14.0, 0.0, TAU, 18,
				Color(0.95, 0.85, 0.30, pulse_alpha), 2.0)


func _draw_cone_telegraph(aim_angle: float, length: float,
		cone_angle_degrees: float, telegraph_color: Color) -> void:
	var half_rad: float = deg_to_rad(cone_angle_degrees * 0.5)
	var arc_steps: int = 8
	var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for i in range(arc_steps + 1):
		var t: float = float(i) / float(arc_steps)
		var local_ang: float = lerp(-half_rad, half_rad, t)
		var world_ang: float = aim_angle + local_ang
		pts.append(Vector2(cos(world_ang), sin(world_ang)) * length)
	var fill: Color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b,
		telegraph_color.a * 0.35)
	draw_colored_polygon(pts, fill)
	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, telegraph_color, thickness)


func _draw_rect_telegraph(aim_angle: float, length: float, rect_width: float,
		telegraph_color: Color) -> void:
	var hw: float = rect_width * 0.5
	var local_pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -hw),
		Vector2(length, -hw),
		Vector2(length, hw),
		Vector2(0, hw),
	])
	var pts: PackedVector2Array = PackedVector2Array()
	var c: float = cos(aim_angle)
	var s: float = sin(aim_angle)
	for p in local_pts:
		pts.append(Vector2(p.x * c - p.y * s, p.x * s + p.y * c))
	var fill: Color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b,
		telegraph_color.a * 0.35)
	draw_colored_polygon(pts, fill)
	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, telegraph_color, thickness)


## Map the current action to the correct sprite sheet attack row.
## FLAMETHROWER=0, POD=1, SUMMON=2, BEAM=3.
func _sync_attack_sprite_row() -> void:
	match _cycle[_cycle_index]:
		Action.FLAMETHROWER: _attack_sprite_row = 0
		Action.POD:          _attack_sprite_row = 1
		Action.SUMMON:       _attack_sprite_row = 2
		Action.BEAM:         _attack_sprite_row = 3
