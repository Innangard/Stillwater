class_name Player
extends CharacterBody2D

## Player controller.
## - 8-directional movement, mouse aim, dash with i-frames
## - 2 active attack slots:
##     LMB → primary_weapon  (MeleeWeapon or RangedWeapon)
##     RMB → secondary_weapon (MeleeWeapon or RangedWeapon)
## - 2 prepared weapon slots (swap with active set via Q):
##     prepared_primary, prepared_secondary
## - Status effects: incoming on-hit effects rolled and applied;
##   modifiers applied to movement, incoming damage, and outgoing damage.
## - Armor: reduces incoming damage in the intercept layer.

@export_group("Movement")
@export var max_speed: float = 220.0
@export var acceleration: float = 1800.0
@export var friction: float = 1500.0
## Multiplier applied to max_speed while sneak is held.
@export var sneak_speed_multiplier: float = 0.5

@export_group("Dash")
@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.14
@export var dash_cooldown: float = 0.55
## Base number of dashes before cooldown starts. Rune DASH_CHARGES
## adds to this. The cooldown only begins after ALL charges are spent.
@export var base_dash_charges: int = 1

@export_group("Starting Loadout")
@export var starting_primary: Weapon
@export var starting_secondary: Weapon
@export var starting_helmet: Armor
@export var starting_chest: Armor
@export var starting_boots: Armor

@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var status_component: StatusEffectComponent = $StatusEffectComponent
@onready var noise_component: NoiseComponent = $NoiseComponent
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _camera: Camera2D = $Camera2D

# Always-available unarmed melee.
const BARE_HANDS: MeleeWeapon = preload("res://weapons/instances/player_weapons/bare_hands.tres")

# --- Detection signature tuning ---
const MOVE_CAP_BASE_PCT: float = 0.40
const MOVE_FILL_RATE: float = 60.0
const SNEAK_CAP_PCT: float = 0.15
const MOVE_STOP_LINGER: float = 0.12

const NOISE_DASH: float = 12.0
const NOISE_DASH_TTL: float = 0.35
const NOISE_MELEE: float = 14.0
const NOISE_MELEE_TTL: float = 0.45
const NOISE_RANGED: float = 22.0
const NOISE_RANGED_TTL: float = 0.55
const NOISE_SPELL: float = 30.0
const NOISE_SPELL_TTL: float = 0.65

const SMELL_MOVE_RATE: float = 0.12
const SMELL_FIGHTING_RATE: float = 0.28
const SMELL_BLOOD_PER_HIT: float = 2.0
const FIGHTING_POLL_INTERVAL: float = 0.4

# --- Perfect dodge ---
## Fraction of dash_cooldown refunded on a perfect dodge. Tuned so that
## one dodge → one extra dodge available immediately if you would
## otherwise have ~60% cd left, which is the sweet spot for "I just
## dashed and now I can dash again" without making dash spammable.
const PERFECT_DODGE_CD_REFUND: float = 0.30
## Time after a dodge during which subsequent hits don't re-trigger the
## reward (anti-spam — multi-shot weapons could otherwise pay out
## several dodges per dash).
const PERFECT_DODGE_COOLDOWN: float = 0.3

enum State { NORMAL, DASHING, SWAPPING, DEAD }
var state: State = State.NORMAL
var aim_direction: Vector2 = Vector2.RIGHT
var team: String = "player"

# --- Weapon swap tuning ---
## Total real-time seconds the swap animation takes before the new
## weapons become usable. Long enough that swapping mid-fight is a
## commitment the player has to find space for, short enough that it
## doesn't feel like punishment. 1.25s sits in the sweet spot where
## most enemy attack cycles have one gap the player can slot a swap
## into without getting hit — provided they read the pattern.
const SWAP_DURATION: float = 1.25
## How many seconds before both primary and secondary cooldowns finish
## during which the player is allowed to initiate a swap. Without this
## window, the player has to wait until BOTH cooldowns hit exactly zero
## before pressing Q — which feels sluggish and unresponsive. 0.3s of
## breathing room lets skilled players overlap the tail of a recovery
## with the start of a swap for fluid combat tempo.
const SWAP_EARLY_WINDOW: float = 0.3

var _fighting_poll_timer: float = 0.0
var _is_fighting: bool = false
var _dash_timer: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
## Current available dash charges. Refills to max when cooldown finishes.
var _dash_charges: int = 1
var _primary_cd: float = 0.0
var _secondary_cd: float = 0.0
## Locks out perfect-dodge reward after a successful one. Prevents
## multi-pellet weapons (skeleton_fan fires several projectiles per shot)
## from paying out three rewards on one dash through a fan.
var _dodge_lockout: float = 0.0

# --- Swap state ---
var _swap_timer: float = 0.0
## The actual swap duration used (after rune speed bonus), so
## get_swap_progress can compute a 0→1 ratio correctly.
var _swap_duration_actual: float = SWAP_DURATION

# === SHIELD STATE ===
# Set by _update_shield_state each frame. The shield system is
# entirely runtime-driven — there's no save/restore needed for these
# because raising the shield is just "hold the input"; on save load
# the input is not pressed, so the shield is down.
var _is_blocking: bool = false
var _active_shield_weapon: ShieldWeapon = null
var _shield_zone: ShieldZone = null

func _ready() -> void:
	add_to_group("player")
	_refill_dash_charges()
	health_component.max_health = RunState.max_health
	health_component.current_health = RunState.current_health

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.hit_received.connect(_on_hit_received)
	status_component.tick_damage.connect(_on_status_tick_damage)
	status_component.tick_heal.connect(_on_status_tick_heal)
	status_component.effect_applied.connect(EventBus.player_status_applied.emit)
	status_component.effect_removed.connect(EventBus.player_status_removed.emit)
	# Re-sync max HP when the player swaps kennings mid-run. KenningManager
	# already updates RunState.max_health and the HUD bar; we just need to
	# mirror that into the HealthComponent so future heals respect the
	# new cap. The bool false means "don't heal to full" — KenningManager
	# already added the delta to current_health.
	EventBus.kenning_equipped.connect(_on_kenning_loadout_changed.unbind(1))
	EventBus.kenning_unequipped.connect(_on_kenning_loadout_changed.unbind(1))

	# Camera shake. request_screen_shake has been emitted in several
	# places (player got hit, perfect-dodge feedback, long-stun HUD pulse,
	# now boss death) without a subscriber, so it was a no-op. Wire it
	# to the player camera now — same camera the HUD already reads via
	# get_viewport().get_camera_2d() for world-text positioning.
	EventBus.request_screen_shake.connect(_on_request_screen_shake)
	EventBus.player_spawned.emit(self)


func _on_kenning_loadout_changed() -> void:
	if not is_instance_valid(health_component):
		return
	# Compute the delta between the old max (still in the HealthComponent)
	# and the new max (already updated in RunState by KenningManager).
	# If the player gained HP cap, heal them by the delta — feels like a
	# Hades-boon top-off rather than "you earned +30 HP but your bar is
	# now an awkwardly smaller fraction of full." If they LOST cap (e.g.
	# unequipped Mead-Hall-Sated), set_max_health's own clamp handles it.
	var old_max: float = health_component.max_health
	var new_max: float = RunState.max_health
	health_component.set_max_health(new_max, false)
	if new_max > old_max:
		health_component.heal(new_max - old_max)
	# Mirror back into RunState so death-respawn picks up the right value.
	RunState.current_health = health_component.current_health

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	_primary_cd = max(0.0, _primary_cd - delta)
	_secondary_cd = max(0.0, _secondary_cd - delta)
	_dodge_lockout = max(0.0, _dodge_lockout - delta)
	_tick_dash_cooldown(delta)

	_fighting_poll_timer -= delta
	if _fighting_poll_timer <= 0.0:
		_fighting_poll_timer = FIGHTING_POLL_INTERVAL
		_is_fighting = _check_any_enemy_alert()

	_update_aim()
	RunState.tick_smell(delta, _is_fighting)
	if _is_fighting:
		RunState.add_smell(SMELL_FIGHTING_RATE * delta)
	_tick_passive_regen(delta)

	if status_component.is_action_prevented():
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		noise_component.stop_sustained("move")
		move_and_slide()
		_update_animations()
		return

	match state:
		State.NORMAL:
			_process_normal(delta)
		State.DASHING:
			_process_dash(delta)
		State.SWAPPING:
			_process_swap(delta)

	move_and_slide()
	_update_animations()

func _update_animations() -> void:
	if state == State.DEAD:
		return 

	var anim_type: String = "stand"
	
	if state == State.DASHING:
		anim_type = "hurt" 
	elif velocity.length() > 10.0:
		anim_type = "run"
	
	var suffix: String = " side"
	if abs(aim_direction.y) > abs(aim_direction.x):
		suffix = " up" if aim_direction.y < 0 else " down"
	
	sprite.flip_h = aim_direction.x < 0
	sprite.play(anim_type + suffix)

## Out-of-combat passive heal — only active on Easy difficulty (other
## profiles have a rate of 0 and short-circuit immediately).
##
## Three gates beyond the rate check:
##   - _is_fighting must be false. Reuses the existing poll that already
##     drives smell-during-combat buildup, so there's no extra detection
##     work. The 0.4s poll interval means up to ~0.4s of regen could
##     happen during the start of a fight before the flag flips — that's
##     small enough to be invisible in practice and not worth tightening.
##   - state must be NORMAL. We don't want to heal mid-dash or during
##     the death animation; either would feel weird.
##   - current HP must be below the cap fraction (50% on Easy). Heals
##     from other sources can still take the player above 50%; the
##     passive regen only fills the FIRST half of the bar. This is the
##     critical design decision — passive regen as a comeback tool for
##     when you've been chunked, not a "you can never lose HP" mode.
##
## When healing, we cap at the threshold so the player doesn't tick a
## frame past 50% and have the regen quietly do nothing on the next
## frame — visually the bar fills exactly to the half-mark and stops.
func _tick_passive_regen(delta: float) -> void:
	var rate: float = DifficultySettings.get_player_regen_rate()
	if rate <= 0.0:
		return
	if _is_fighting:
		return
	if state != State.NORMAL:
		return
	if not is_instance_valid(health_component) or health_component.is_dead():
		return
	var cap_fraction: float = DifficultySettings.get_player_regen_cap_fraction()
	if cap_fraction <= 0.0:
		return
	var cap_hp: float = RunState.max_health * cap_fraction
	if health_component.current_health >= cap_hp:
		return
	var headroom: float = cap_hp - health_component.current_health
	var amount: float = minf(rate * delta, headroom)
	if amount > 0.0:
		health_component.heal(amount)


func _check_any_enemy_alert() -> bool:
	# Walks all enemies in-scene and asks each "is this one engaged with
	# me?". Engaged = anything other than IDLE. Used to drive the
	# SMELL_FIGHTING_RATE bonus — your scent builds when fights are
	# actually happening.
	#
	# Previously this compared `node._ai_state == DummyEnemy.AIState.ALERT`,
	# but DummyEnemy is a legacy unused class whose enum doesn't match the
	# real Enemy base class. It only worked while enemies were in CHASE
	# (the enum values happened to collide at 1) and silently missed
	# WIND_UP / ATTACK / RECOVER. The shared Enemy.is_engaged() helper is
	# the right channel.
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy and (node as Enemy).is_engaged():
			return true
	return false

func _update_aim() -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse.length() > 4.0:
		aim_direction = to_mouse.normalized()

func _process_normal(delta: float) -> void:
	var input_vec := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	var sneaking: bool = Input.is_action_pressed("sneak")
	var speed_mult := status_component.get_speed_multiplier()
	speed_mult *= KenningManager.get_move_speed_multiplier()
	speed_mult *= RunState.get_armor_move_speed_multiplier()
	speed_mult *= RunState.get_weapon_move_speed_multiplier()
	# Rune move speed bonus stacks on top of all other multipliers.
	speed_mult *= RunState.get_rune_multiplier(RunestoneItem.RuneStat.MOVE_SPEED)
	if sneaking:
		speed_mult *= sneak_speed_multiplier
	# Shield blocking applies its movement_speed_multiplier on top of
	# everything else. Composes the same way as status / kenning /
	# armor / sneak — multiplicatively. With a 0.5 shield mult and
	# the default sneak mult of 0.5, blocking-while-sneaking yields
	# 25% speed; that's intentional (sneaking with a shield up is a
	# defensive stance, deliberately slow).
	if _is_blocking and _active_shield_weapon != null:
		speed_mult *= _active_shield_weapon.movement_speed_multiplier
	var effective_max := max_speed * speed_mult

	if input_vec != Vector2.ZERO:
		velocity = velocity.move_toward(input_vec * effective_max, acceleration * delta)
		var max_noise: float = noise_component.max_noise
		var move_cap: float
		if sneaking:
			move_cap = SNEAK_CAP_PCT * max_noise
		else:
			var armor_total: float = 0.0
			for piece in [RunState.helmet, RunState.chest, RunState.boots]:
				if piece is Armor:
					armor_total += (piece as Armor).noise_weight
			move_cap = MOVE_CAP_BASE_PCT * max_noise + armor_total
		noise_component.start_sustained("move", MOVE_FILL_RATE, move_cap)

		var smell_mult: float = 0.5 if sneaking else 1.0
		RunState.add_smell(SMELL_MOVE_RATE * smell_mult * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		noise_component.stop_sustained("move", MOVE_STOP_LINGER)

	if Input.is_action_just_pressed("dash") and _dash_charges > 0:
		_start_dash(input_vec if input_vec != Vector2.ZERO else aim_direction)
		return

	# Shield state update — must run BEFORE the regular attack dispatch
	# so the dispatch can see the updated _is_blocking flag and skip
	# the not-shield hand while the shield is raised. The shield
	# system is hold-to-block (rather than tap-to-fire), so it doesn't
	# fit the cooldown/_attack_with pipeline that melee/ranged/magic
	# use — instead it has its own state machine here.
	_update_shield_state()

	var primary_actual: Weapon = _get_attack_weapon("primary")
	# Skip dispatch if (a) this hand IS the shield, since shields are
	# routed through _update_shield_state above and shouldn't fire
	# attack(), or (b) the other-or-this hand is currently raising a
	# shield (_is_blocking), since the spec is "while using a shield
	# they should not be able to use their other equipped weapon."
	if _primary_cd == 0.0 \
			and not (primary_actual is ShieldWeapon) \
			and not _is_blocking \
			and _is_attack_input_active("attack_melee", primary_actual):
		_attack_with(primary_actual, "primary")

	var secondary_actual: Weapon = RunState.secondary_weapon
	if _secondary_cd == 0.0 \
			and not (secondary_actual is ShieldWeapon) \
			and not _is_blocking \
			and _is_attack_input_active("attack_ranged", secondary_actual):
		_attack_with(secondary_actual, "secondary")

	# Weapon set swap: Q swaps active ↔ prepared weapon pair. Allowed
	# when both attack cooldowns are within SWAP_EARLY_WINDOW of done
	# (so the player doesn't have to wait for exact zero, but can't
	# swap-cancel out of a fresh attack's full recovery). The swap
	# takes SWAP_DURATION seconds during which the player can move but
	# cannot attack or dodge.
	if Input.is_action_just_pressed("swap_weapons"):
		if _primary_cd <= SWAP_EARLY_WINDOW and _secondary_cd <= SWAP_EARLY_WINDOW:
			_start_swap()

func _get_attack_weapon(slot: String) -> Weapon:
	match slot:
		"primary":
			return RunState.primary_weapon if RunState.primary_weapon != null else BARE_HANDS
		"secondary":
			return RunState.secondary_weapon
	return null

## Hold-to-block input handler for ShieldWeapons. Called once per
## physics frame from the main attack dispatch (BEFORE the regular
## attack(weapon, aim) calls — see _physics_process).
##
## Determines which slot holds a shield (if any), checks whether its
## bound action is held, and transitions between raised/lowered
## states. A shield in the primary slot is bound to attack_melee
## (LMB); in the secondary slot, attack_ranged (RMB). If neither
## slot holds a shield, the function clears any stale block state
## (e.g. after the player swaps to a non-shield mid-block) and exits.
##
## The state transitions are edge-triggered: we only call _raise_shield
## on the input's first frame of press, and _lower_shield on the
## first frame of release. This means the shield zone is instantiated
## ONCE per press-and-hold sequence, not every frame.
func _update_shield_state() -> void:
	var primary_actual: Weapon = _get_attack_weapon("primary")
	var secondary_actual: Weapon = RunState.secondary_weapon

	# Find the shield (if any) and which input action raises it.
	# Primary slot wins if both slots hold shields — an unusual
	# configuration but possible. The user can only actively hold
	# one shield up at a time regardless.
	var shield_weapon: ShieldWeapon = null
	var shield_action: String = ""
	if primary_actual is ShieldWeapon:
		shield_weapon = primary_actual
		shield_action = "attack_melee"
	elif secondary_actual is ShieldWeapon:
		shield_weapon = secondary_actual
		shield_action = "attack_ranged"

	if shield_weapon == null:
		# No shield equipped. If we were blocking (player swapped
		# weapons mid-block, or unequipped the shield somehow),
		# clean up so we don't carry a phantom block state. This
		# also handles the State.DEAD case below — once death wipes
		# the equipped weapons, blocking implicitly cancels.
		if _is_blocking:
			_lower_shield()
		_active_shield_weapon = null
		return

	# Don't allow blocking while dashing or dead. Dashing is the
	# perfect-dodge i-frame and the visual is committed to the dash —
	# raising a shield during it would let players cheese both i-frame
	# and block in the same input window. Dead is dead.
	var can_block: bool = state != State.DEAD and state != State.DASHING \
		and state != State.SWAPPING
	var input_held: bool = Input.is_action_pressed(shield_action)
	var should_block: bool = can_block and input_held

	if should_block and not _is_blocking:
		_raise_shield(shield_weapon)
	elif not should_block and _is_blocking:
		_lower_shield()


## Spawn the shield zone as a child of the player and flip state to
## blocking. Called once when the shield's input transitions from
## not-pressed to pressed (see _update_shield_state).
func _raise_shield(shield_weapon: ShieldWeapon) -> void:
	_is_blocking = true
	_active_shield_weapon = shield_weapon
	# Instantiate the zone scene declared on the weapon. Default is
	# shield_zone.tscn, but each shield can specify a custom variant
	# (a glowing ward, a flame barrier) by overriding shield_zone_scene
	# on the .tres. The zone reads block_arc_size / block_distance
	# directly from the weapon, so we don't duplicate those here.
	_shield_zone = shield_weapon.shield_zone_scene.instantiate()
	_shield_zone.shield_weapon = shield_weapon
	_shield_zone.owner_actor = self
	add_child(_shield_zone)


## Despawn the shield zone and flip state to not-blocking. Called
## when the input is released, the player swaps away from the
## shield, dies, or starts dashing.
func _lower_shield() -> void:
	_is_blocking = false
	if _shield_zone != null and is_instance_valid(_shield_zone):
		_shield_zone.queue_free()
	_shield_zone = null
	# _active_shield_weapon stays set for one more frame; it's cleared
	# by _update_shield_state next tick (or here if you prefer
	# immediate). The damage-reduction lookup in _on_hit_received
	# guards on _is_blocking, so the lingering reference is harmless.


func _is_attack_input_active(action: String, weapon: Weapon) -> bool:
	if weapon == null:
		return false
	if weapon is RangedWeapon:
		return Input.is_action_pressed(action)
	return Input.is_action_just_pressed(action)

func _attack_with(weapon: Weapon, slot: String) -> void:
	if weapon == null:
		return
	weapon.attack(self, aim_direction)
	var burst_id: String = "burst_" + slot
	if weapon is RangedWeapon:
		noise_component.add_burst(burst_id, NOISE_RANGED, NOISE_RANGED_TTL)
	else:
		noise_component.add_burst(burst_id, NOISE_MELEE, NOISE_MELEE_TTL)
	match slot:
		"primary":   _primary_cd = weapon.cooldown
		"secondary": _secondary_cd = weapon.cooldown


## Begin the weapon swap animation. The player enters SWAPPING state
## for SWAP_DURATION seconds: movement continues, attacks and dodge are
## locked out. At the end, RunState.swap_weapon_sets() exchanges the
## active and prepared pairs atomically. If both prepared slots are empty,
## the player swaps to unarmed — the BARE_HANDS fallback in
## _get_attack_weapon catches that case naturally.
func _start_swap() -> void:
	state = State.SWAPPING
	# Rune SWAP_SPEED bonus reduces the swap duration.
	var swap_mult: float = 1.0 - RunState.get_rune_bonus(
		RunestoneItem.RuneStat.SWAP_SPEED) / 100.0
	swap_mult = maxf(swap_mult, 0.25)  # floor at 75% reduction
	_swap_timer = SWAP_DURATION * swap_mult
	_swap_duration_actual = _swap_timer
	# Drop the shield immediately — same reason as in _start_dash.
	# Blocking must not persist through a swap.
	if _is_blocking:
		_lower_shield()
	# Zero out any remaining attack cooldowns so the new weapons start
	# fresh after the swap completes. The swap time IS the recovery.
	_primary_cd = 0.0
	_secondary_cd = 0.0
	EventBus.weapon_swap_started.emit()


## Process the swap animation. Player can move (same velocity/friction
## as NORMAL) but cannot attack, dodge, or raise a shield. The swap
## timer ticks down in real gameplay time; when it hits zero the weapon
## sets exchange and we return to NORMAL.
func _process_swap(delta: float) -> void:
	var input_vec := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	var sneaking: bool = Input.is_action_pressed("sneak")
	var speed_mult := status_component.get_speed_multiplier()
	speed_mult *= KenningManager.get_move_speed_multiplier()
	speed_mult *= RunState.get_armor_move_speed_multiplier()
	speed_mult *= RunState.get_weapon_move_speed_multiplier()
	speed_mult *= RunState.get_rune_multiplier(RunestoneItem.RuneStat.MOVE_SPEED)
	if sneaking:
		speed_mult *= sneak_speed_multiplier
	var effective_max := max_speed * speed_mult

	if input_vec != Vector2.ZERO:
		velocity = velocity.move_toward(input_vec * effective_max, acceleration * delta)
		var max_noise: float = noise_component.max_noise
		var move_cap: float
		if sneaking:
			move_cap = SNEAK_CAP_PCT * max_noise
		else:
			var armor_total: float = 0.0
			for piece in [RunState.helmet, RunState.chest, RunState.boots]:
				if piece is Armor:
					armor_total += (piece as Armor).noise_weight
			move_cap = MOVE_CAP_BASE_PCT * max_noise + armor_total
		noise_component.start_sustained("move", MOVE_FILL_RATE, move_cap)
		var smell_mult: float = 0.5 if sneaking else 1.0
		RunState.add_smell(SMELL_MOVE_RATE * smell_mult * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		noise_component.stop_sustained("move", MOVE_STOP_LINGER)

	_swap_timer -= delta
	if _swap_timer <= 0.0:
		RunState.swap_weapon_sets()
		state = State.NORMAL
	# move_and_slide and _update_animations are called by _physics_process
	# after this function returns — no need to call them here.


func _start_dash(dir: Vector2) -> void:
	state = State.DASHING
	_lower_shield()
	_dash_dir = dir.normalized()
	_dash_timer = dash_duration
	_dash_charges -= 1
	# Cooldown only starts when all charges are spent. If the player
	# has charges remaining (from rune bonuses), no cd yet — they can
	# chain dashes. Once charges hit 0, the full cooldown begins and
	# all charges refill when it finishes.
	if _dash_charges <= 0:
		# Rune DASH_COOLDOWN reduces the cooldown percentage.
		var cd_mult: float = KenningManager.get_dash_cooldown_multiplier()
		cd_mult *= (1.0 - RunState.get_rune_bonus(RunestoneItem.RuneStat.DASH_COOLDOWN) / 100.0)
		cd_mult = maxf(cd_mult, 0.15)  # floor at 85% reduction
		_dash_cd = dash_cooldown * cd_mult
	velocity = _dash_dir * dash_speed
	noise_component.add_burst("dash", NOISE_DASH, NOISE_DASH_TTL)


func _process_dash(delta: float) -> void:
	_dash_timer -= delta
	velocity = _dash_dir * dash_speed
	if _dash_timer <= 0.0:
		state = State.NORMAL


## Called from _physics_process every frame to tick dash cooldown and
## refill charges. Separated from _process_dash because the cooldown
## ticks while in NORMAL state (after all charges are spent), not
## during the dash itself.
func _tick_dash_cooldown(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd -= delta
		if _dash_cd <= 0.0:
			_dash_cd = 0.0
			_refill_dash_charges()


func _refill_dash_charges() -> void:
	var max_charges: int = base_dash_charges \
		+ int(RunState.get_rune_bonus(RunestoneItem.RuneStat.DASH_CHARGES))
	_dash_charges = max_charges


func _on_hit_received(amount: float, info: Dictionary, source: HitboxComponent) -> void:
	# ── Perfect dodge intercept ───────────────────────────────────────
	# A hit landing while dashing is dodged, not absorbed. The dash
	# state is the i-frame: no damage, no on-hit statuses, no smell
	# from bleeding. The reward is a partial dash-cooldown refund so
	# chaining dodges is a real (and skill-rewarded) option, plus a
	# signal the HUD can use to flash.
	#
	# The _dodge_lockout prevents a multi-projectile weapon (e.g.
	# skeleton_fan's 5-shot spread) from paying out five rewards on
	# one dash through the fan. First contact pays; subsequent
	# overlapping hits in the same dash window are silently dodged.
	if state == State.DASHING:
		if _dodge_lockout <= 0.0:
			_dash_cd = maxf(0.0, _dash_cd - dash_cooldown * PERFECT_DODGE_CD_REFUND)
			_dodge_lockout = PERFECT_DODGE_COOLDOWN
			EventBus.player_perfect_dodge.emit()
			EventBus.request_screen_shake.emit(2.0, 0.08)
		return

	# ── Shield damage reduction / projectile block ──────────────────
	# Applied early in the receive pipeline — before knockback (so
	# blocked hits still knock back proportionally to their full force,
	# which feels right — a shield blocks the cut but not the shove)
	# and before status / kenning / armor multipliers (so the shield
	# stacks multiplicatively with all of them, the same as any other
	# damage modifier).
	#
	# Two cases when the source hitbox is currently overlapping the
	# shield zone:
	#
	#   1. Projectile-parented hitbox → full block (return early).
	#      The shield zone's area_entered handler queue_frees the
	#      projectile in the same frame, but if the hurtbox ALSO
	#      detected the projectile in that frame (a same-frame entry,
	#      possible with fast projectiles), the hit_received signal
	#      already fired and the damage would be delivered without
	#      this check. The check zeros that damage out so the spec's
	#      "projectiles should be removed after coming in contact
	#      with the shield" reads as full immunity, not just the
	#      multiplier-reduced version.
	#
	#   2. Other hitbox (melee swing, persistent AOE, etc.) → reduce
	#      damage by the shield's melee_damage_reduction multiplier,
	#      optionally further reduced for specific damage elements via
	#      the shield's element_multipliers dict. The result is clamped
	#      at the 0.10 floor so shields never grant more than 90%
	#      damage reduction — late-game shields earn their extra power
	#      via max_health_bonus and element-specific advantage rather
	#      than ever-deeper raw reduction.
	#
	# Both cases are gated on the source actually overlapping the
	# shield — which is what makes blocking directional. A swing from
	# the player's back never enters the front-facing shield zone, so
	# this check fails and full damage is taken.
	if _is_blocking and _shield_zone != null \
			and is_instance_valid(_shield_zone) \
			and _active_shield_weapon != null \
			and _shield_zone.is_blocking_hitbox(source):
		if is_instance_valid(source) and source.get_parent() is Projectile:
			# Full block. Skip damage AND status effects AND
			# knockback — the projectile didn't connect.
			return
		var reduction: float = _active_shield_weapon.melee_damage_reduction
		# Rune SHIELD_REDUCTION bonus improves shield effectiveness.
		var shield_rune_bonus: float = RunState.get_rune_bonus(
			RunestoneItem.RuneStat.SHIELD_REDUCTION) / 100.0
		reduction *= (1.0 - shield_rune_bonus)
		# Optional per-element multiplier on top of base reduction.
		# Same dict-keyed-by-element shape as Armor.element_multipliers.
		# Missing element entries leave reduction at the base value.
		if info.has("element"):
			var elem: int = int(info["element"])
			if _active_shield_weapon.element_multipliers.has(elem):
				reduction *= float(_active_shield_weapon.element_multipliers[elem])
		# Floor at 0.10 — never more than 90% reduction regardless of
		# base shield + element matchup. The cap is what makes the
		# shield archetype balanced.
		reduction = max(reduction, 0.10)
		amount *= reduction

	# Knockback application. Every weapon already attaches `knockback`
	# to its damage_info (see melee_weapon.gd, persistent_hitbox.gd,
	# projectile.gd), and enemies have always consumed it via
	# enemy.gd line ~570 — the player simply never wired the receive
	# side, so every enemy knockback value silently no-op'd. Wiring it
	# now activates intended design across the codebase: cinder_maw's
	# flame cone pushes you out of itself (per its own .tres comment),
	# wolf swipes have impact, and AOE eruptions feel like impacts
	# rather than damage popups. Mirrors enemy.gd's velocity-replace
	# pattern so the impact reads as a hard interruption rather than
	# an additive nudge stacked on existing motion.
	#
	# Skips:
	# - State.DEAD: no point shoving a corpse; also avoids writing to
	#   velocity on a node that may be mid-cleanup.
	# - missing source: we need a direction vector, which comes from
	#   the hitbox's global_position. If source vanished mid-frame
	#   (queue_free'd projectile that already hit) we have no anchor.
	# - knockback == 0: most player-team weapons don't push enemies
	#   that way anyway; same nullity applies here.
	if state != State.DEAD and info.has("knockback") and is_instance_valid(source):
		var kb: float = float(info["knockback"])
		if kb > 0.0:
			var kb_dir: Vector2 = (global_position - source.global_position).normalized()
			# Zero vector means source and player share a position —
			# vanishingly rare but possible with overlapping AOE
			# spawns. Fall back to RIGHT so we still apply force
			# rather than silently dropping the knockback.
			if kb_dir == Vector2.ZERO:
				kb_dir = Vector2.RIGHT
			velocity = kb_dir * kb
		elif kb < 0.0:
			# NEGATIVE knockback = PULL toward the source. Convention
			# introduced for the Drowned Crone's net cast: the hit
			# yanks the player toward the caster. Same velocity-replace
			# pattern as push knockback — the impulse decays under the
			# player's own acceleration, and when the accompanying root
			# status zeroes their input speed, the decay integrates to
			# a meaningful drag distance (~200-240px at kb -850, player accel 1800).
			#
			# Net-Cutter negates the yank along with the root: pulls
			# are binding-class force, so binding immunity covers both
			# halves of the catch.
			if not KenningManager.is_binding_immune():
				var pull_dir: Vector2 = (source.global_position - global_position).normalized()
				if pull_dir == Vector2.ZERO:
					pull_dir = Vector2.RIGHT
				velocity = pull_dir * -kb

	amount *= status_component.get_damage_taken_multiplier()
	amount *= KenningManager.get_damage_taken_multiplier(info)
	# Rune damage resistance: flat percentage reduction from collected runes.
	# Floor at 0.05 so damage never goes to zero or negative from rune stacking.
	var dr_mult: float = maxf(0.05, 1.0 - RunState.get_rune_bonus(
		RunestoneItem.RuneStat.DAMAGE_RESISTANCE) / 100.0)
	amount *= dr_mult
	# Rune elemental resistances: additional reduction gated on element.
	if info.has("element"):
		var elem: int = int(info["element"])
		var elem_stat: int = -1
		match elem:
			Weapon.Element.FIRE:      elem_stat = RunestoneItem.RuneStat.FIRE_RESIST
			Weapon.Element.ICE:       elem_stat = RunestoneItem.RuneStat.ICE_RESIST
			Weapon.Element.LIGHTNING: elem_stat = RunestoneItem.RuneStat.LIGHTNING_RESIST
			Weapon.Element.POISON:    elem_stat = RunestoneItem.RuneStat.POISON_RESIST
		if elem_stat >= 0:
			var elem_mult: float = maxf(0.05, 1.0 - RunState.get_rune_bonus(elem_stat) / 100.0)
			amount *= elem_mult
	amount = RunState.apply_armor_to_damage(amount, info)
	health_component.take_damage(amount, info)
	EventBus.damage_dealt_visual.emit(self, amount, info)
	RunState.add_smell(SMELL_BLOOD_PER_HIT)
	if info.has("on_hit_effects"):
		status_component.try_apply_each(info["on_hit_effects"], source)
	EventBus.request_screen_shake.emit(4.0, 0.15)

func _on_status_tick_damage(amount: float, info: Dictionary) -> void:
	amount = RunState.apply_armor_to_damage(amount, info)
	health_component.take_damage(amount, info)
	EventBus.damage_dealt_visual.emit(self, amount, info)

func _on_status_tick_heal(amount: float, _info: Dictionary) -> void:
	if health_component.current_health < health_component.max_health:
		health_component.heal(amount)

func _on_health_changed(current: float, maximum: float) -> void:
	RunState.current_health = current
	EventBus.player_health_changed.emit(current, maximum)

func _on_died() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	# Drop any raised shield. _physics_process early-returns on DEAD,
	# so the normal _update_shield_state path won't run — we need to
	# clean up the shield zone here or it'd dangle as an orphaned
	# child of the corpse until respawn.
	if _is_blocking:
		_lower_shield()
	
	var suffix: String = " side"
	if abs(aim_direction.y) > abs(aim_direction.x):
		suffix = " down" 
	sprite.play("died" + suffix)
	
	EventBus.player_died.emit()
	EventBus.run_ended.emit("death")

func get_primary_cooldown_ratio() -> float:
	var w: Weapon = _get_attack_weapon("primary")
	if w == null or w.cooldown <= 0.0: return 0.0
	return clampf(_primary_cd / w.cooldown, 0.0, 1.0)

func get_secondary_cooldown_ratio() -> float:
	var w: Weapon = RunState.secondary_weapon
	if w == null or w.cooldown <= 0.0: return 0.0
	return clampf(_secondary_cd / w.cooldown, 0.0, 1.0)

## 0.0 = no swap in progress, 1.0 = swap just started.
## HUD uses this to drive a swap progress indicator on the prepared
## weapon slots.
func get_swap_progress() -> float:
	if state != State.SWAPPING or _swap_duration_actual <= 0.0:
		return 0.0
	return clampf(_swap_timer / _swap_duration_actual, 0.0, 1.0)

func noise_factor() -> float:
	return noise_component.factor() if noise_component else 0.0

func smell_factor() -> float:
	return RunState.smell / RunState.max_smell if RunState.max_smell > 0.0 else 0.0


## Camera shake. Strength is in pixels (peak amplitude). Duration is in
## seconds. The shake decays linearly over the duration and randomizes
## the offset each physics frame via a Tween.
##
## Latch guard: a stronger/longer shake REPLACES a weaker one in flight,
## but a weaker incoming shake during a stronger active one is ignored.
## Prevents a string of small hits from suppressing a big punch by
## constantly re-driving the camera at low amplitude — the boss-death
## shake at strength 16, duration 0.6 will read even if a routine hit
## fires at strength 4 a frame later.
var _shake_active_strength: float = 0.0
var _shake_active_remaining: float = 0.0
var _shake_tween: Tween = null

func _on_request_screen_shake(strength: float, duration: float) -> void:
	if not is_instance_valid(_camera):
		return
	# Latch: ignore weaker re-triggers while a stronger shake is running.
	# "Strength × remaining" approximates total energy and is more
	# stable than strength alone (a long weak shake would otherwise
	# beat a short strong one's residual).
	var active_energy: float = _shake_active_strength * _shake_active_remaining
	var new_energy: float = strength * duration
	if active_energy > new_energy * 1.2 and _shake_active_remaining > 0.05:
		return
	_shake_active_strength = strength
	_shake_active_remaining = duration

	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	# Sample the shake at ~60Hz over the duration. Each sample sets a
	# random offset, scaled by the linear decay envelope. End on offset
	# zero so the camera settles cleanly.
	var samples: int = max(1, int(round(duration * 60.0)))
	var step: float = duration / float(samples)
	for i in samples:
		var t: float = float(i) / float(samples)
		var amp: float = strength * (1.0 - t)
		var ox: float = randf_range(-amp, amp)
		var oy: float = randf_range(-amp, amp)
		_shake_tween.tween_property(_camera, "offset", Vector2(ox, oy), step)
	_shake_tween.tween_property(_camera, "offset", Vector2.ZERO, 0.05)
	_shake_tween.tween_callback(_on_shake_finished)

func _on_shake_finished() -> void:
	_shake_active_strength = 0.0
	_shake_active_remaining = 0.0
