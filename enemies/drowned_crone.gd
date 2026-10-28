extends Enemy
## The Drowned Crone (Rán of the Reefs) — third story boss. In the myths,
## Rán caught drowning sailors in her net and dragged them to her hall
## under the sea. The Crone is one of her acolytes — a sea-witch who
## never let go of the net even after she herself drowned.
##
## ── Design intent ──────────────────────────────────────────────────────
## Skill tested: ANTI-CC MANAGEMENT. Galgi taught the player to keep
## moving; the Crone tests whether they can also keep a dash BANKED.
## The net cast is the whole fight: dash i-frames break the catch
## entirely (the existing perfect-dodge path eats the hit, the pull,
## and the root in one), running laterally at cast time dodges the arc,
## and a player who panic-dashes early gets netted with their escape on
## cooldown — then meets the scythe, or in phase 2, the Drag Under.
##
## Phase 1 — Net & Hook. Three-attack cycle:
##   NET    — wide forward cone (bone-braided net). On catch: 6 damage,
##            a -900 pull impulse toward her, and the "Netted" root for
##            1s. A banked dash escapes even after the catch (dash sets
##            velocity directly, ignoring the root's speed multiplier) —
##            deliberate anti-frustration: the root stops walking, not
##            a saved escape. The Drag Under punishes whoever spent it.
##   SCYTHE — fish-hook sweep with a 48px lunge. Heavy 420 knockback:
##            thematically it hurls the catch back into the water.
##   WAVE   — expanding ring from her position. 8 damage + 40% slow.
##            The front travels ~190 px/s: outrunnable with a head
##            start, trivially dashable — it exists to TAX the dash so
##            the net timing stays honest.
##
## Phase 2 — The Drowning (40% HP): the wreck capsizes, the arena
## floods. An arena-wide aura applies "Waterlogged" (-15% speed) to the
## player; she slows herself too (70 → 55). Summons two Drowned Sailors
## — slow armored draugr who are not the threat, they are the CLOCK
## PRESSURE during net windows. Adds the DRAG UNDER finisher: if the
## player is caught by the net, her next action becomes a both-hands-on-
## the-rope grab that pulls them beneath the water — 14 damage plus
## 1.5s of helpless DoT. Netted players who banked a dash escape before
## it lands; netted players who didn't learn why the kenning she drops
## is called Net-Cutter.
##
## ── Boss rhythm ────────────────────────────────────────────────────────
## Cycle: NET → SCYTHE → WAVE → repeat. Phase 2 keeps the cycle (same
## principle as Galgi: phase shifts change the fight, not the rotation
## the player already learned) but the flood, the sailors, and the
## drag-under intercept change what the rhythm MEANS: space is worth
## less, the dash is worth more, and getting caught escalates.

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Boss")
@export var boss_display_name: String = "The Drowned Crone"
@export var boss_id: String = "drowned_crone"
@export var weapon_net: PersistentHitboxWeapon
@export var weapon_scythe: MeleeWeapon
@export var weapon_wave: ExpandingRingWeapon
@export var weapon_drag_under: TelegraphedAreaWeapon

@export_group("Phase 2")
## Phase 2 triggers at or below this fraction of max HP.
@export var phase2_threshold: float = 0.40
## Her own speed once the arena floods (she wades too).
@export var phase2_speed: float = 55.0
## Arena-flood slow applied to the player via the base aura system.
@export var waterlogged_effect: StatusEffect
## Minion scene summoned once at the phase transition.
@export var sailor_scene: PackedScene
## How many sailors rise from the water.
@export var sailor_count: int = 2

@export_group("Per-Action Timing")
## NET wind-up is the longest — it is THE read of the fight, and the
## read has to be honest for the dash-timing lesson to stick.
@export var wind_up_net: float = 0.85
@export var wind_up_scythe: float = 0.60
@export var wind_up_wave: float = 0.75
@export var wind_up_drag_under: float = 0.55

@export var recover_net: float = 0.90
@export var recover_scythe: float = 0.60
@export var recover_wave: float = 1.00
@export var recover_drag_under: float = 1.10

# ----------------------------------------------------------------------------
# BOSS CONSTANTS
# ----------------------------------------------------------------------------

const BOSS_STAGGER_THRESHOLD: float = 3.0
const BOSS_STUN_BASE: float = 0.5
const BOSS_LONG_STUN: float = 3.0
const BOSS_STAGGER_DECAY: float = 0.4
const BOSS_STAGGER_GAIN: float = 1.0
const BOSS_LEASH_RANGE: float = 0.0

## She fights at net range — inside the cone's effective reach, outside
## the player's easy melee. The scythe's 48px lunge covers the gap when
## the player closes, so the band doesn't need to.
const ENGAGEMENT_RANGE: float = 160.0
## She holds a 160px band while repositioning, but attacks fire at ANY
## closer distance (min_engage 0): a player who hugs her must meet the
## lunging scythe, not a boss shuffling backward refusing to swing.
const MIN_ENGAGE_BAND: float = 0.0

## Radius of the phase 2 flood aura — effectively arena-wide.
const FLOOD_AURA_RADIUS: float = 9999.0

## Sailor spawn offsets relative to the Crone (they rise from the water
## flanking her, not on top of her or the player).
const SAILOR_OFFSETS: Array[Vector2] = [Vector2(-70, 30), Vector2(70, 30)]

# ============================================================================
# ACTIONS
# ============================================================================

enum Action { NET, SCYTHE, WAVE, DRAG_UNDER }

var _cycle: Array[Action] = []
var _cycle_index: int = 0
var _phase: int = 1
var _phase2_triggered: bool = false
var _engaged: bool = false

## True while the NEXT attack has been swapped to DRAG_UNDER. Kept
## separate from the cycle array so the learned three-beat rotation
## resumes exactly where it left off after the interrupt.
var _drag_under_armed: bool = false

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

	_cycle = [Action.NET, Action.SCYTHE, Action.WAVE]
	_cycle_index = 0

	_attack_range = ENGAGEMENT_RANGE
	min_engage_range = MIN_ENGAGE_BAND

	weapon = _weapon_for_action(_current_action())
	_sync_attack_sprite_row()
	wind_up_duration = _wind_up_for_action(_current_action())

	health_component.health_changed.connect(_on_boss_health_changed)
	health_component.died.connect(_on_boss_died)
	base_detection = 9999.0


func _physics_process(delta: float) -> void:
	super(delta)

	# Engagement trigger — same belt-and-braces as boss_enemy.gd.
	if not _engaged and _ai_state != AIState.IDLE:
		_engaged = true
		var hp: float = health_component.current_health if health_component else max_health
		var hp_max: float = health_component.max_health if health_component else max_health
		EventBus.boss_engaged.emit(boss_display_name, hp, hp_max)
		EventBus.boss_stagger_changed.emit(_stagger, stagger_threshold)

	# Drag-under arming (phase 2): watch for the player carrying the
	# Netted status. Two care-points in the timing:
	#
	#   1. NEVER arm during WIND_UP/ATTACK — the swap would change
	#      which attack fires AFTER the player already read the
	#      current telegraph. Telegraphs must not lie. Arming waits
	#      for CHASE/RECOVER, and the netted root (1.0s) comfortably
	#      outlives her net-recover (0.9s), so the observation window
	#      can't slip past.
	#
	#   2. On arming, CUT THE CURRENT RECOVER SHORT (0.15s floor).
	#      Without this the chain math never connects: root 1.0s vs
	#      full recover 0.9 + wind-up 0.55 + warning 0.7 = the marker
	#      lands ~1.15s after the root already released, and any
	#      walking player strolls out of the 55px radius. Cut short,
	#      the warning overlaps the root's tail: a player who spent
	#      their dash on nothing gets dragged under — the roster's
	#      "punishes greedy net-eaten players brutally" — while a
	#      player with a banked dash (or Net-Cutter) escapes clean.
	#
	# Once armed it stays armed until it fires: if she gets stunned
	# through the window, the eventual grab is just a dodgeable ground
	# marker at the player's position — fair, and thematically she is
	# still furious about the catch that got away.
	if _phase == 2 and not _drag_under_armed \
			and _ai_state != AIState.WIND_UP and _ai_state != AIState.ATTACK \
			and is_instance_valid(_player):
		var scc: StatusEffectComponent = _player.get_node_or_null("StatusEffectComponent")
		if scc and scc.has_effect(&"netted"):
			_drag_under_armed = true
			weapon = weapon_drag_under
			wind_up_duration = wind_up_drag_under
			if _ai_state == AIState.RECOVER:
				_state_timer = minf(_state_timer, 0.15)


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
		# The flood: she wades too.
		max_speed = phase2_speed
		# Arena-wide waterlogged aura on the player, via the base
		# enemy aura system (re-applied every active frame; decays
		# naturally when the fight ends).
		aura_effect = waterlogged_effect
		aura_radius = FLOOD_AURA_RADIUS
		_summon_sailors()
		EventBus.boss_phase_changed.emit(2)


func _summon_sailors() -> void:
	if sailor_scene == null:
		return
	var parent: Node = get_parent()
	for i in range(mini(sailor_count, SAILOR_OFFSETS.size())):
		var sailor: Node2D = sailor_scene.instantiate()
		parent.call_deferred("add_child", sailor)
		# Same set-then-deferred-add pattern boss_enemy.gd uses for
		# pillars: the property write persists and applies when the
		# deferred add_child lands.
		sailor.position = position + SAILOR_OFFSETS[i]


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
	if _drag_under_armed:
		return Action.DRAG_UNDER
	return _cycle[_cycle_index]


func _weapon_for_action(a: Action) -> Weapon:
	match a:
		Action.NET:        return weapon_net
		Action.SCYTHE:     return weapon_scythe
		Action.WAVE:       return weapon_wave
		Action.DRAG_UNDER: return weapon_drag_under
	return null


func _wind_up_for_action(a: Action) -> float:
	match a:
		Action.NET:        return wind_up_net
		Action.SCYTHE:     return wind_up_scythe
		Action.WAVE:       return wind_up_wave
		Action.DRAG_UNDER: return wind_up_drag_under
	return wind_up_net


func _recover_for_action(a: Action) -> float:
	match a:
		Action.NET:        return recover_net
		Action.SCYTHE:     return recover_scythe
		Action.WAVE:       return recover_wave
		Action.DRAG_UNDER: return recover_drag_under
	return recover_net


# ============================================================================
# ATTACK PROCESSING
# ============================================================================

func _process_attack() -> void:
	if _player == null:
		_ai_state = AIState.RECOVER
		_state_timer = recover_net
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	var action: Action = _current_action()
	var w: Weapon = _weapon_for_action(action)
	if w:
		w.attack(self, aim)
	var attack_recover: float = _recover_for_action(action)

	if action == Action.DRAG_UNDER:
		# The interrupt consumed itself; resume the cycle at the slot
		# it displaced — the player's learned rotation stays intact.
		_drag_under_armed = false

	else:
		_cycle_index = (_cycle_index + 1) % _cycle.size()

	# Prime the NEXT attack's weapon + wind-up.
	var next_action: Action = _current_action()
	weapon = _weapon_for_action(next_action)
	wind_up_duration = _wind_up_for_action(next_action)
	_sync_attack_sprite_row()

	_ai_state = AIState.RECOVER
	_state_timer = attack_recover


## Keep repositioning during RECOVER — same rationale as the other
## bosses: a boss that stands still between attacks gets orbited.
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
# DRAW OVERRIDE — crescent witch, net drag, phase visuals, telegraphs
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

	# Phase 2: colder, darker — half-sunk.
	if _phase == 2:
		body = body.lerp(Color(0.12, 0.22, 0.30), 0.35)

	var tint: Color = status_component.get_tint()
	if tint.a > 0.0:
		body = body.lerp(Color(tint.r, tint.g, tint.b, 1.0), tint.a)

	var t: float = Time.get_ticks_msec() / 1000.0

	# --- Phase 2 wading ripples (drawn UNDER the body) ---
	if _phase == 2:
		for i in range(2):
			var ripple_phase: float = fmod(t * 0.7 + i * 0.5, 1.0)
			var ripple_r: float = body_radius * (0.9 + ripple_phase * 1.1)
			var ripple_a: float = (1.0 - ripple_phase) * 0.30
			draw_arc(Vector2.ZERO, ripple_r, 0.0, TAU, 24,
				Color(0.55, 0.75, 0.85, ripple_a), 1.5)

	# --- The dragged net (behind her, opposite the player) ---
	var to_player: Vector2 = Vector2.RIGHT
	if is_instance_valid(_player):
		to_player = (_player.global_position - global_position).normalized()
	var net_dir: Vector2 = -to_player
	var net_color := Color(0.65, 0.62, 0.50, 0.85)
	# Three rope strands fanning back, tied with bone-knot dots.
	for i in range(3):
		var fan: float = (i - 1) * 0.38
		var strand_dir: Vector2 = net_dir.rotated(fan)
		var sway: float = sin(t * 2.2 + i * 1.3) * 4.0
		var strand_end: Vector2 = strand_dir * (body_radius + 26.0) \
			+ strand_dir.rotated(PI * 0.5) * sway
		draw_line(strand_dir * body_radius * 0.6, strand_end, net_color, 1.5)
		draw_circle(strand_end, 2.0, Color(0.85, 0.82, 0.72))
	# Cross-ties between strand midpoints — the mesh read.
	for i in range(2):
		var a_dir: Vector2 = net_dir.rotated((i - 1) * 0.38)
		var b_dir: Vector2 = net_dir.rotated(i * 0.38)
		var mid_a: Vector2 = a_dir * (body_radius + 13.0)
		var mid_b: Vector2 = b_dir * (body_radius + 13.0)
		draw_line(mid_a, mid_b, net_color * Color(1, 1, 1, 0.6), 1.0)

	# --- Body (hooked crescent) ---
	_draw_body(body)

	# --- Shell eye: a pearly dot offset toward the player ---
	var eye_pos: Vector2 = to_player * (body_radius * 0.35) \
		+ to_player.rotated(PI * 0.5) * (body_radius * 0.25)
	draw_circle(eye_pos, 3.0, Color(0.92, 0.88, 0.80))
	draw_arc(eye_pos, 3.0, 0.0, TAU, 8, Color(0.55, 0.45, 0.35), 1.0)

	# --- Weapon indicator dot ---
	var icon_pos: Vector2 = to_player * (body_radius * 0.55)
	draw_circle(icon_pos, 4.0, _icon_color_for_next_action())

	# --- Attack telegraph ---
	if _ai_state == AIState.WIND_UP and weapon != null:
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		_draw_crone_telegraph(to_player, telegraph_color, t)

	# --- HP bar (proximity nameplate) ---
	var hp_pct: float = health_component.health_percent() if health_component else 1.0
	var bar_w: float = body_radius * 2.0
	var bar_y: float = -body_radius - 20.0
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w, 4)), Color(0.05, 0.10, 0.12))
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w * hp_pct, 4)), Color(0.35, 0.55, 0.55))

	# --- Stun stars / engaged dot ---
	if _ai_state == AIState.STUNNED:
		for i in range(3):
			var a: float = t * 6.0 + i * (TAU / 3.0)
			var p := Vector2(cos(a), -0.3 + sin(a) * 0.15) * 14.0 + Vector2(0, -body_radius - 14.0)
			draw_circle(p, 2.4, Color(1.0, 0.95, 0.5))
	elif _ai_state != AIState.IDLE:
		draw_circle(Vector2(0, -2), 2.5, Color(1, 0.95, 0.5))


func _icon_color_for_next_action() -> Color:
	match _current_action():
		Action.NET:        return Color(0.75, 0.72, 0.55)   # rope-tan — the net
		Action.SCYTHE:     return Color(0.70, 0.75, 0.75)   # steel-grey — the hook
		Action.WAVE:       return Color(0.45, 0.70, 0.85)   # sea-blue — the pulse
		Action.DRAG_UNDER: return Color(0.10, 0.20, 0.30)   # deep-water — the grab
	return weapon_icon_color


func _draw_crone_telegraph(to_player: Vector2, telegraph_color: Color, t: float) -> void:
	var aim_angle: float = to_player.angle()
	match _current_action():
		Action.NET:
			# Cone outline of the net's arc, with a mesh of cross-lines
			# so it reads as a NET incoming, not a flame cone.
			if weapon_net:
				var half_rad: float = deg_to_rad(weapon_net.cone_angle_degrees * 0.5)
				var reach: float = weapon_net.length
				var left: Vector2 = Vector2(cos(aim_angle - half_rad), sin(aim_angle - half_rad))
				var right: Vector2 = Vector2(cos(aim_angle + half_rad), sin(aim_angle + half_rad))
				draw_line(Vector2.ZERO, left * reach, telegraph_color, 2.0)
				draw_line(Vector2.ZERO, right * reach, telegraph_color, 2.0)
				draw_arc(Vector2.ZERO, reach, aim_angle - half_rad, aim_angle + half_rad,
					10, telegraph_color, 2.0)
				# Net mesh: three interior arcs at fractions of reach.
				for i in range(1, 4):
					var f: float = reach * i / 4.0
					draw_arc(Vector2.ZERO, f, aim_angle - half_rad, aim_angle + half_rad,
						8, Color(telegraph_color.r, telegraph_color.g, telegraph_color.b,
							telegraph_color.a * 0.4), 1.0)
		Action.SCYTHE:
			if weapon_scythe:
				var reach: float = weapon_scythe.swing_range + weapon_scythe.arc_radius \
					+ weapon_scythe.user_lunge_distance
				var telegraph_pos: Vector2 = to_player * (reach * 0.45)
				draw_arc(telegraph_pos, reach * 0.55, 0.0, TAU, 24, telegraph_color, 2.5)
		Action.WAVE:
			# Pulsing ring at the ring's start radius — "the stomp is
			# coming, the water is gathering."
			if weapon_wave:
				var pulse: float = 0.5 + 0.5 * sin(t * 9.0)
				var r0: float = weapon_wave.start_radius + pulse * 6.0
				draw_arc(Vector2.ZERO, r0, 0.0, TAU, 24, telegraph_color, 2.5)
				draw_arc(Vector2.ZERO, r0 * 0.6, 0.0, TAU, 16,
					Color(telegraph_color.r, telegraph_color.g, telegraph_color.b,
						telegraph_color.a * 0.5), 1.5)
		Action.DRAG_UNDER:
			# Both hands close on the rope: two short heavy strokes
			# pulled in toward her center, plus a taut line snapping
			# straight to the player. The ground marker itself comes
			# from the TelegraphedAreaWeapon's telegraph scene.
			var grip_perp: Vector2 = to_player.rotated(PI * 0.5)
			for s in [-1.0, 1.0]:
				var hand: Vector2 = grip_perp * (s * 7.0) + to_player * (body_radius * 0.4)
				draw_line(hand + to_player * 10.0, hand, telegraph_color, 3.0)
			if is_instance_valid(_player):
				var taut_end: Vector2 = to_local(_player.global_position)
				var wobble: float = sin(t * 30.0) * 1.5
				draw_line(to_player * body_radius * 0.5,
					taut_end + grip_perp * wobble, telegraph_color, 1.5)


## Map the current action to the correct sprite sheet attack row.
## NET=0, SCYTHE=1, WAVE=2, DRAG_UNDER=3.
func _sync_attack_sprite_row() -> void:
	match _current_action():
		Action.NET:        _attack_sprite_row = 0
		Action.SCYTHE:     _attack_sprite_row = 1
		Action.WAVE:       _attack_sprite_row = 2
		Action.DRAG_UNDER: _attack_sprite_row = 3
