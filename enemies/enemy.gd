class_name Enemy
extends CharacterBody2D

## Generic enemy. Wields a Weapon Resource the same way the Player does.
## All archetype variation (kobold, goblin, wolf, crab, etc.) is data —
## scenes set the appropriate exports.
##
## State machine:
##   IDLE     — drifts. Polls detection every _DETECT_INTERVAL seconds.
##   CHASE    — moves toward the player, holding inside the engage band.
##   WIND_UP  — stops, telegraphs the attack with a yellow tint, then
##              flashes red for the final STAGGER_WINDOW seconds — the
##              "parry window."
##   ATTACK   — single frame of damage application.
##   RECOVER  — brief post-attack pause.
##   STUNNED  — entered when a player hit lands during the late wind-up
##              (red flash) or on the ATTACK frame itself. Earlier
##              wind-up hits (yellow phase) deal damage normally but
##              do NOT stagger — the enemy commits through the chip
##              shot and still swings. This is the parry skill check:
##              wait for the red, then strike. Hitting an already-
##              stunned enemy extends the stun timer slightly (capped
##              at STUN_HIT_EXTENSION_MAX) so a clean stun + follow-up
##              combo prolongs the punish.

enum AIState { IDLE, CHASE, WIND_UP, ATTACK, RECOVER, STUNNED }

# ============================================================================
# CONFIG
# ============================================================================

@export_group("Identity")
@export var enemy_name: String = "Wretch"
@export var body_tint: Color = Color(0.8, 0.2, 0.2)
@export var weapon_icon_color: Color = Color(0.9, 0.9, 0.9)
@export var body_radius: float = 14.0
## Placeholder body shape for enemies without sprites. Each shape
## communicates a behavioral archetype so the player can read threat
## type from silhouette alone:
##   CIRCLE   — melee grunts (swords, spears, claws)
##   DIAMOND  — ranged / projectile (bows, bone toss, ashbombs)
##   TRIANGLE — aggressive beasts / chargers (wolves, worms)
##   SQUARE   — heavy tanks (bears, crabs, armored skeletons)
##   HEXAGON  — casters / summoners (pillar callers, cinder pods)
## Boss shapes — each is unique so the player identifies the boss from
## silhouette alone, before the name tag even registers:
##   SKULL    — Skeleton King: minimalist skull, jaw narrower than cranium
##   PINCERS  — Giant Scorpion: wide body + two forward claws
##   FLAME    — Cinder Sovereign: teardrop with flickering points
##   MAW      — Sandworm Broodmother: jagged tooth-ring
##   NOOSE    — Galgi the Bound: lumpy asymmetric mass of lashed corpses
##   CRONE    — Drowned Crone: hooked crescent, bent like a wave or a bowed back
enum BodyShape { CIRCLE, DIAMOND, TRIANGLE, SQUARE, HEXAGON, SKULL, PINCERS, FLAME, MAW, NOOSE, CRONE }
@export var body_shape: BodyShape = BodyShape.CIRCLE
@export var sprite_scale: Vector2 = Vector2(1.0, 1.0)
## Sprite sheet name (without extension). If set and the PNG exists at
## res://sprites/<sprite_name>.png, a Sprite2D is created automatically
## using the 3×4 sheet layout (rows: idle/attack/recover × cols:
## south/west/north/east, each cell 64×64). Takes priority over
## AnimatedSprite2D if both are present. Leave empty to use
## AnimatedSprite2D or the placeholder circle fallback.
@export var sprite_name: String = ""

@export_group("Stats")
@export var max_health: float = 30.0
@export var max_speed: float = 110.0
@export var acceleration: float = 800.0

@export_group("Senses")
@export var base_detection: float = 80.0
@export var noise_sensitivity: float = 5.0
@export var smell_sensitivity: float = 4.0

@export_group("Combat")
@export var weapon: Weapon
@export var wind_up_duration: float = 0.55
@export var recover_duration: float = 0.45
@export var min_engage_range: float = 0.0

## Optional secondary attack that takes over when the player is too
## close. Specifically: if the player is within
## reactive_attack_trigger_distance when this enemy enters WIND_UP,
## we substitute reactive_attack into the weapon slot for THIS attack
## cycle. Once the cycle finishes (RECOVER ends), the main weapon
## comes back.
##
## Used for "ranged with a panic melee" enemies — a crossbow user
## switches to a bite when you close, then resumes ranged when you
## back out. Also useful inversely: a melee enemy can carry a small
## reactive_attack ranged shot for "when you're just-out-of-reach
## I throw a rock," which adds menace to otherwise simple chasers.
##
## Leave null on enemies with only one attack mode (default).
@export var reactive_attack: Weapon = null

## Distance at which reactive_attack takes over. If the player is
## within this radius when WIND_UP starts, reactive_attack fires
## instead of weapon. Set this comfortably inside the main weapon's
## range so the substitution feels natural — a crossbow at 220px
## might switch to bite within 70px, leaving a clear middle band
## where neither attack is preferred.
@export var reactive_attack_trigger_distance: float = 60.0

## How this enemy moves once it has decided to engage. Picked per
## enemy resource — the default APPROACH_BAND is the historical
## behavior (close to within attack range, stop, fire), preserving
## every existing enemy's feel. New ranged enemies pick a different
## profile to express their fantasy: a perched shooter sits still,
## a wisp circles, an ambusher waits then closes.
##
## Each profile resolves to a velocity in _apply_movement_profile.
## Adding a new profile means adding an enum value and a match arm.
##
## Detailed semantics:
##   APPROACH_BAND      — Move toward player until inside [min_engage,
##                        _attack_range]. Stop. Fire. The default;
##                        every melee enemy and basic archer wants
##                        this. Re-pursues if the player kites out.
##   MAINTAIN_DISTANCE  — Same band logic, but if the player comes
##                        WITHIN min_engage_range, retreat to push
##                        the player back out. Doesn't try to close
##                        the band aggressively — slow drift toward
##                        ideal range. The "I am a sniper, get away"
##                        profile. Used by goblin_bow.
##   PERCH_STATIC       — Never moves once alerted. Stays in place,
##                        rotates to face player, fires when in range.
##                        Used by perched/turret-style enemies (Stein-
##                        Skytta when behind cover, Glóð-Hrafn in the
##                        sky above the player).
##   CIRCLE_AT_RANGE    — Orbit the player at preferred distance
##                        (_attack_range mid-band). Tangent movement
##                        relative to the player rather than radial.
##                        Used by Helkattr — feels like a scout
##                        keeping itself unpredictable.
##   AMBUSH             — Stay still until player is within
##                        ambush_trigger_distance, then switch
##                        permanently to APPROACH_BAND. Visible
##                        identity: blends with terrain. After
##                        triggering, behaves like any other
##                        approacher. Used by Stein-Skarn-style
##                        enemies in future content.
enum MovementProfile {
	APPROACH_BAND,
	MAINTAIN_DISTANCE,
	PERCH_STATIC,
	CIRCLE_AT_RANGE,
	AMBUSH,
}

@export_group("Movement")
@export var movement_profile: MovementProfile = MovementProfile.APPROACH_BAND

## Circle direction — used only by CIRCLE_AT_RANGE. 1 = clockwise,
## -1 = counterclockwise. Authoring per-instance lets a pair of
## circling enemies sweep opposite ways so the player can't predict
## one rule for both.
@export var circle_direction: int = 1

## Distance at which AMBUSH-profile enemies wake up. Only relevant
## if movement_profile == AMBUSH. The enemy stays inert (no movement,
## no firing, no detection cascade) until the player crosses inside
## this radius. Should typically be smaller than base_detection so
## the ambusher doesn't reveal itself early; pair with very low
## noise_sensitivity to keep the ambush honest.
@export var ambush_trigger_distance: float = 100.0

@export_group("Aura")
## Optional persistent status effect this enemy applies to the player
## just by being near. The effect is re-applied every frame the player
## is within aura_radius, which (because StatusEffectComponent refreshes
## existing effects in-place) keeps the timer topped up rather than
## stacking. Leaving the area lets the effect decay normally.
##
## Used for "presence-based" debuffs — Helkattr's dark-yowl, future
## frost-aura enemies, etc. The effect itself decides what it does
## (damage tick, slow, attack penalty); the aura system is just the
## delivery mechanism.
##
## Important: don't put a hit-on-damage effect here. The hit pipeline
## handles those via on_hit_effects on weapons. Auras are for things
## that should be true SIMPLY BECAUSE THIS ENEMY IS NEAR YOU — fear,
## chill, ill omen.
@export var aura_effect: StatusEffect = null

## Radius within which aura_effect applies. Should be larger than
## base_detection in some cases (a debuff aura that catches the
## player BEFORE they even know the enemy is there is one valid
## design — though it's a stealth-build counter, so use with care),
## or smaller than detection if the aura is meant as "while you're
## fighting me." Default 0 = disabled (no aura even if aura_effect
## is set, prevents accidental zero-radius bugs from being silent).
@export var aura_radius: float = 0.0

@export_group("Stagger")
## Base stun applied when a player hit interrupts WIND_UP. Short by design —
## enough for the player to land a follow-up but not a free combo.
@export var stun_duration_base: float = 0.4
## When the stagger meter reaches stagger_threshold, the next wind-up
## interrupt applies a long stun (stagger_long_stun_duration) and resets
## the meter to zero. For regular enemies this rarely matters (they die
## first); for bosses, this is the mastery mechanic — chip-shot their
## wind-ups three times to earn a big punish window.
@export var stagger_threshold: float = 3.0
@export var stagger_long_stun_duration: float = 2.5
## Stagger meter loses this per second while not being hit.
@export var stagger_decay_rate: float = 0.5
## How much each successful WIND_UP interrupt adds to the stagger meter.
@export var stagger_gain_per_hit: float = 1.0

@export_group("Leash")
## If the player is more than leash_range pixels away for leash_seconds,
## the enemy returns to IDLE and re-runs the normal detection check.
## Means players can actually disengage by running far enough.
## Set to 0 to disable (the enemy chases forever, old behavior).
@export var leash_range: float = 720.0
@export var leash_seconds: float = 4.0

@export_group("Drops")
@export var currency_drop_min: int = 3
@export var currency_drop_max: int = 8
@export var item_drops: Array[Item] = []
@export_range(0.0, 1.0) var item_drop_chance: float = 0.35
## Optional rare-drop pool. Rolled FIRST, before the regular drop. If
## the rare roll succeeds, ONE item from this pool drops and the regular
## drop is skipped entirely (an enemy never produces both a rare and a
## regular drop in the same death). If the rare roll fails, the regular
## drop pipeline runs normally — so setting rare_drop_chance doesn't
## erode the player's usual reagent flow.
##
## Designed for boss-unique loot, named-enemy drops, and low-probability
## prestige items (e.g. the Wraithfoot Shiv off orcs at ~2%). Leave the
## array empty and the chance at 0.0 for normal enemies.
@export var rare_item_drops: Array[Item] = []
@export_range(0.0, 1.0) var rare_drop_chance: float = 0.0

# ============================================================================
# CONSTANTS / NODES
# ============================================================================

const _PICKUP_SCENE: PackedScene = preload("res://pickups/pickup.tscn")
const _DEFAULT_DROP_PATHS: Array = [
	"res://items/instances/pale_ash.tres",
	"res://items/instances/bog_bile.tres",
	"res://items/instances/frost_filament.tres",
	"res://items/instances/wraithseed.tres",
	"res://items/instances/soul_phial.tres",
]

const _DETECT_INTERVAL: float = 0.25
## Hard cap on how long a stun can last after chain-extension. Caps the
## "you keep hitting them while they're staggered" reward at something
## meaningful but not chain-lockable on the boss with a fast weapon.
const STUN_HIT_EXTENSION_MAX: float = 3.5
## Parry window — seconds at the END of wind-up during which a player
## hit triggers a stagger. Outside this window (early/mid wind-up,
## a.k.a. the "yellow flash" phase) hits land for damage but do NOT
## interrupt — the enemy carries through with the attack. This is the
## core skill check: wait for the red telegraph flash, then strike.
##
## Aligned with the visual flash threshold in _draw so the player's
## "now!" cue matches their input window — change both together if
## you tune this. 0.15s is tight but readable; for reference, the
## default mook wind-up is 0.55s, so the parry window is ~27% of the
## total wind-up, and the player has to recognize the flash → swing
## in a fraction of a second. Boss phase 2 (0.40s wind-up) gives a
## proportionally wider window (~37%), which feels right because the
## boss has faster overall tempo and the player has less reaction time.
const STAGGER_WINDOW: float = 0.15

var team: String = "enemy"

@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var status_component: StatusEffectComponent = $StatusEffectComponent
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Safely look for the sprite node to avoid null errors on generic enemies
@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

## Sprite2D created at runtime when sprite_name is set and the sheet PNG
## exists. Null when using AnimatedSprite2D or placeholder circles.
var _sheet_sprite: Sprite2D = null

## Sprite sheet layout constants.
## Sheet is 4 columns (directions) × 3 rows (states), each cell 64×64.
const _SHEET_COLS: int = 4
const _SHEET_CELL: int = 64  # pixels per cell

## Cardinal direction indices matching the sheet column order.
enum _FacingDir { SOUTH = 0, WEST = 1, NORTH = 2, EAST = 3 }

## Sprite row indices matching the sheet row order.
const _ROW_IDLE: int = 0
const _ROW_ATTACK: int = 1
const _ROW_RECOVER: int = 2

## For bosses with multiple attack types, this selects which attack row
## to display (1-indexed from row 1). Set by boss scripts before/during
## WIND_UP. Default 0 means "use row 1" (single attack sheet).
## Example: Skeleton King sets 0 for swipe, 1 for lunge.
## The recover row is always the LAST row in the sheet.
var _attack_sprite_row: int = 0

## Current facing — persists when velocity is zero so the enemy holds
## its last direction during wind-up, attack, and recover.
var _facing_dir: int = _FacingDir.SOUTH

## Brief white flash on hit — counts down each physics frame.
## Set to 3 in _on_hit_received, decays to 0. While > 0 the tint
## shader shows a white flash so the player feels impact.
var _hit_flash_timer: int = 0

# ============================================================================
# RUNTIME STATE
# ============================================================================

var _player: Player = null
var _ai_state: AIState = AIState.IDLE
var _detect_timer: float = 0.0
var _state_timer: float = 0.0
## The weapon that will fire on the NEXT _process_attack tick.
## Normally points at `weapon`; can be swapped to `reactive_attack`
## by the wind-up trigger if the player is too close. Reset to null
## after firing so the next wind-up picks fresh — prevents a stale
## "I locked in the bite once, now I bite forever" bug.
var _current_attack_weapon: Weapon = null
var _attack_range: float = 0.0

# Stagger meter — fills on wind-up interrupts, decays passively. Reaching
# stagger_threshold triggers a long stun on the next interrupt.
var _stagger: float = 0.0
# Leash timer — accumulates while the player is outside leash_range.
# When it crosses leash_seconds, the enemy forgets and returns to IDLE.
# Resets the moment the player comes back inside the leash radius.
var _leash_timer: float = 0.0
## Cached damage_info from the most recent incoming hit. Read by _on_died
## so kill-tracking code can attribute the kill to its weapon category
## (melee/ranged/spell/persistent). Default-empty so a dying enemy that
## somehow never took a tracked hit (e.g. self-damaging future effects)
## still queries safely with .get().
var _last_hit_info: Dictionary = {}


# ============================================================================
# QUERIES
# ============================================================================

## True when this enemy has noticed the player — any state other than
## IDLE counts. Used by Player._is_fighting to drive smell-during-combat
## buildup. Replaces the old (broken) DummyEnemy enum check.
func is_engaged() -> bool:
	return _ai_state != AIState.IDLE


## Current stagger / threshold — used by boss HUD to draw the stagger bar.
func get_stagger() -> float:
	return _stagger


func get_stagger_threshold() -> float:
	return stagger_threshold

# ============================================================================
# READY
# ============================================================================

## Redraw gating. A sprite-based enemy's _draw is nothing but a static HP
## bar, so it only needs to redraw when its health changes — not every
## physics frame. This flag is raised on any health change (see the
## health_changed connection in _ready) and consumed by _redraw_if_needed.
## Starts true so the very first frame always draws. Placeholder-circle
## enemies animate continuously (aim dot tracking the player, wind-up
## flash, stun stars, stagger decay) and are handled by
## _draw_animates_per_frame() returning true, so they keep redrawing every
## frame regardless of this flag.
var _needs_redraw: bool = true


func _ready() -> void:
	# Boss kills are game-persistent — once a boss falls it stays dead
	# across all future runs. Check this BEFORE the run-scoped consumed
	# set so the boss is removed even on a fresh run after the player
	# died. Regular enemies skip this (they don't have boss_id).
	if "boss_id" in self:
		var bid: String = self.get("boss_id")
		if bid != "" and GameState.is_boss_dead(bid):
			queue_free()
			return

	if RunState.is_node_consumed(self):
		queue_free()
		return

	add_to_group("enemies")
	_detect_timer = randf() * _DETECT_INTERVAL

	# Tag with source scene so QuestManager can identify enemy type on death.
	if scene_file_path != "":
		set_meta("source_scene", scene_file_path)

	if sprite:
		sprite.scale = sprite_scale

	# Sprite sheet setup — if sprite_name is set and the PNG exists,
	# create a Sprite2D with hframes/vframes for the 3×4 sheet.
	# This takes priority over AnimatedSprite2D.
	if sprite_name != "":
		var sheet_path: String = _find_sprite_sheet(sprite_name)
		if sheet_path != "":
			var tex: Texture2D = load(sheet_path)
			if tex:
				# Debug: confirm sprite loaded. Remove once working.
				print("SpriteSheet: loaded '%s' from %s (%dx%d)" % [
					sprite_name, sheet_path, tex.get_width(), tex.get_height()])
				_sheet_sprite = Sprite2D.new()
				_sheet_sprite.texture = tex
				_sheet_sprite.scale = sprite_scale
				# Detect sheet layout from texture height:
				#   192px = 3 rows (idle/attack/recover)
				#    64px = 1 row (idle only)
				var tex_h: int = tex.get_height()
				_sheet_sprite.hframes = _SHEET_COLS
				if tex_h >= _SHEET_CELL * 3:
					_sheet_sprite.vframes = 3
				else:
					_sheet_sprite.vframes = 1
				_sheet_sprite.frame = 0
				add_child(_sheet_sprite)
				# Apply the combat tint shader so state/status tints
				# work regardless of sprite base colors.
				var shader: Shader = load("res://shaders/combat_tint.gdshader")
				if shader:
					var mat := ShaderMaterial.new()
					mat.shader = shader
					_sheet_sprite.material = mat
				# Disable AnimatedSprite2D if we have a sheet
				if sprite:
					sprite.visible = false

	# Scale max HP by the active difficulty profile. Read once here
	# rather than every frame — an enemy's HP cap is fixed for the life
	# of the instance, and re-reading mid-fight would create the
	# unpleasant edge case of an enemy's bar shifting if a hypothetical
	# future feature changed difficulty mid-save.
	#
	# We multiply BEFORE writing into the HealthComponent so the bar
	# fills to the scaled value, not the authored one. The base value
	# in the .tres remains the Normal baseline — Easy enemies have
	# less HP than authored, Hard enemies more.
	var hp_mult: float = DifficultySettings.get_enemy_health_multiplier()
	health_component.max_health = max_health * hp_mult
	health_component.current_health = health_component.max_health

	if collision_shape and collision_shape.shape is CircleShape2D:
		var s := CircleShape2D.new()
		s.radius = body_radius
		collision_shape.shape = s

	# Sync the hurtbox to body_radius with a slight buffer so hits that
	# visually graze the sprite still connect. Without this the hurtbox
	# stays at the base 14px from enemy.tscn regardless of enemy size.
	var hurtbox_shape: CollisionShape2D = get_node_or_null("HurtboxComponent/HurtboxShape")
	if hurtbox_shape:
		var hs := CircleShape2D.new()
		hs.radius = body_radius * 1.15
		hurtbox_shape.shape = hs

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed_redraw)
	hurtbox.hit_received.connect(_on_hit_received)
	status_component.tick_damage.connect(_on_status_tick_damage)

	EventBus.player_spawned.connect(_on_player_spawned)
	call_deferred("_find_player")

	if weapon:
		_attack_range = weapon.effective_range()
	else:
		_attack_range = 32.0


func _find_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")


func _on_player_spawned(player: Node) -> void:
	_player = player


# ============================================================================
# PHYSICS / PROCESS
# ============================================================================

func _physics_process(delta: float) -> void:
	# Passive stagger decay — gives players a window to land the next
	# wind-up interrupt while the meter is still warm. Skip while
	# already in STUNNED so a stunned enemy doesn't "shake off" the
	# meter mid-punishment (feels worse than it sounds — you want the
	# meter visible during the stun so it reads as "you earned this").
	if _stagger > 0.0 and _ai_state != AIState.STUNNED:
		var new_stagger: float = maxf(0.0, _stagger - stagger_decay_rate * delta)
		if new_stagger != _stagger:
			_stagger = new_stagger
			_emit_stagger_if_boss()

	if status_component.is_action_prevented():
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		_update_animations()
		_redraw_if_needed()
		return

	if not is_instance_valid(_player):
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		_update_animations()
		_redraw_if_needed()
		return

	# Leash check — if engaged but the player has been far away for
	# long enough, drop back to IDLE. The enemy will re-detect normally
	# if the player returns. Skip during STUNNED (the enemy isn't
	# making AI decisions while staggered) and during WIND_UP/ATTACK
	# (mid-swing escapes shouldn't get a free pass).
	if leash_range > 0.0 and _ai_state in [AIState.CHASE, AIState.RECOVER]:
		var dist_to_player: float = global_position.distance_to(_player.global_position)
		if dist_to_player > leash_range:
			_leash_timer += delta
			if _leash_timer >= leash_seconds:
				_ai_state = AIState.IDLE
				_leash_timer = 0.0
				_detect_timer = _DETECT_INTERVAL  # full interval before re-engaging
		else:
			_leash_timer = 0.0
	else:
		_leash_timer = 0.0

	if _ai_state == AIState.IDLE:
		_detect_timer -= delta
		if _detect_timer <= 0.0:
			_detect_timer = _DETECT_INTERVAL
			_check_detection()

	# Aura tick. Re-applied every physics frame the player is inside
	# aura_radius and we're in an active state. StatusEffectComponent
	# refreshes existing effects in-place (it doesn't stack), so this
	# just keeps the duration topped up — leave the area and the
	# status decays naturally.
	#
	# Active = anything other than IDLE (we haven't noticed yet) and
	# STUNNED (we're disabled). RECOVER counts as active intentionally:
	# Helkattr's dark-yowl should keep pulsing even between attacks.
	if aura_effect != null and aura_radius > 0.0 \
			and _ai_state != AIState.IDLE and _ai_state != AIState.STUNNED:
		var dist_to_player: float = global_position.distance_to(_player.global_position)
		if dist_to_player <= aura_radius:
			var scc: Node = _player.get_node_or_null("StatusEffectComponent")
			if scc and scc.has_method("apply"):
				scc.apply(aura_effect, self)

	match _ai_state:
		AIState.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.WIND_UP:
			_process_wind_up(delta)
		AIState.ATTACK:
			_process_attack()
		AIState.RECOVER:
			_process_recover(delta)
		AIState.STUNNED:
			_process_stunned(delta)

	move_and_slide()
	_update_animations()
	_redraw_if_needed()


# ============================================================================
# ANIMATION LOGIC
# ============================================================================

func _update_animations() -> void:
	# ── Sprite sheet path (Sprite2D with hframes/vframes) ──
	if _sheet_sprite != null:
		_update_sheet_frame()
		return

	# ── AnimatedSprite2D path (legacy) ──
	# Exit if this specific enemy instance has no AnimatedSprite2D
	if sprite == null:
		return

	if _ai_state == AIState.IDLE and velocity.length() < 10.0:
		sprite.stop()
		return

	# Determine target direction for facing
	var target_dir = velocity.normalized()
	if _ai_state != AIState.IDLE and is_instance_valid(_player):
		target_dir = (_player.global_position - global_position).normalized()
	
	if target_dir == Vector2.ZERO:
		target_dir = Vector2.DOWN

	var suffix = " side"
	if abs(target_dir.y) > abs(target_dir.x):
		suffix = " up" if target_dir.y < 0 else " down"
	
	sprite.flip_h = target_dir.x > 0

	match _ai_state:
		AIState.CHASE:
			sprite.play("walk" + suffix)
		AIState.WIND_UP, AIState.ATTACK:
			sprite.play("attack" + suffix)
		AIState.RECOVER:
			# Stay on the final frame of attack while recovering
			sprite.play("attack" + suffix)
			sprite.frame = sprite.sprite_frames.get_frame_count("attack" + suffix) - 1
		AIState.STUNNED:
			# Reuse the "hurt" anim if it exists; otherwise freeze on the
			# wind-up frame as a fallback (since most enemies don't have a
			# distinct hurt anim and reusing the wind-up pose reads as
			# "staggered mid-attack" pretty cleanly).
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("hurt" + suffix):
				sprite.play("hurt" + suffix)
			else:
				sprite.play("attack" + suffix)
				sprite.frame = 0
				sprite.stop()
		AIState.IDLE:
			if velocity.length() > 10.0:
				sprite.play("walk" + suffix)


# ============================================================================
# STATE LOGIC
# ============================================================================

func _check_detection() -> void:
	var dist: float = global_position.distance_to(_player.global_position)
	# AMBUSH bypasses noise and smell entirely. The ambusher is hiding
	# in plain sight (lore-fitting: a Stein-Skarn looks like a boulder)
	# and won't react to the player until the player crosses the
	# trigger radius. Once alerted, they switch their movement profile
	# to APPROACH_BAND so they actually pursue — they don't stay in
	# ambush mode forever.
	if movement_profile == MovementProfile.AMBUSH:
		if dist <= ambush_trigger_distance:
			movement_profile = MovementProfile.APPROACH_BAND
			_alert()
		return
	var noise_f: float = _player.noise_factor()
	var smell_f: float = _player.smell_factor()
	var detect_range: float = base_detection * (1.0 \
		+ noise_f * noise_sensitivity \
		+ smell_f * smell_sensitivity)
	if dist <= detect_range:
		_alert()


## Transition this enemy to its first aggressive state (CHASE), and
## fan the alert out to other enemies within MY base_detection radius —
## the "shouting" mechanic. If a packed group notices one of its members
## react, the whole group reacts. Stops the player from ranged-tagging
## one enemy at a time from outside the others' detection radius.
##
## Idempotent: once an enemy is past IDLE, _alert() on it is a no-op.
## This naturally bounds cascade depth — a cluster of N enemies gets
## alerted in at most N invocations, since each propagation step only
## touches enemies still in IDLE.
##
## Detection range used for fan-out is MY base_detection (not modified
## by player noise/smell factors). The intuition: a louder presence
## (bigger enemy with bigger base_detection) recruits further. The
## fan-out is a "shout to my neighbors" signal, not a "detect the
## player better" signal.
func _alert() -> void:
	if _ai_state != AIState.IDLE:
		return
	_ai_state = AIState.CHASE
	# If we have no player ref yet, the recipients will pick the
	# player up via their own _find_player on next tick, so we can
	# still fan out without one. Skip only if base_detection is zero
	# (defensive — should never happen, but a zero-radius shout would
	# do nothing useful anyway).
	if base_detection <= 0.0:
		return
	var here := global_position
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self:
			continue
		if not is_instance_valid(other):
			continue
		if not (other is Enemy):
			continue
		if other.global_position.distance_to(here) <= base_detection:
			(other as Enemy)._alert()


func _process_chase(delta: float) -> void:
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	# Two multipliers compose multiplicatively on top of base max_speed:
	#   - status_component (chill, slow effects, etc.)
	#   - DifficultySettings (per-save tuning knob)
	# Same composition convention used everywhere else (damage, smell rate).
	var effective_speed: float = max_speed \
		* status_component.get_speed_multiplier() \
		* DifficultySettings.get_enemy_speed_multiplier()

	# Wind-up trigger is profile-independent: any profile that has the
	# player in its firing band enters WIND_UP. For profiles that don't
	# want to fire (e.g. AMBUSH that hasn't triggered) we'd suppress
	# this — but AMBUSH switches itself to APPROACH_BAND on trigger,
	# and pre-trigger it doesn't enter CHASE at all, so this check is
	# safely uniform.
	#
	# Reactive-attack handling: if the player is within
	# reactive_attack_trigger_distance AND we have a reactive_attack
	# configured, we substitute that weapon — even if the player is
	# INSIDE min_engage_range (which would normally block firing for
	# MAINTAIN_DISTANCE archers). The fantasy: when something gets in
	# your face, you stop trying to shoot and you bite.
	if dist <= reactive_attack_trigger_distance and reactive_attack != null:
		_current_attack_weapon = reactive_attack
		_ai_state = AIState.WIND_UP
		_state_timer = wind_up_duration
		velocity = Vector2.ZERO
		return
	if dist <= _attack_range and dist >= min_engage_range:
		if weapon != null:
			_current_attack_weapon = weapon
			_ai_state = AIState.WIND_UP
			_state_timer = wind_up_duration
			velocity = Vector2.ZERO
			return
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return

	_apply_movement_profile(delta, effective_speed)


## Dispatch table for movement profiles. Each branch writes `velocity`
## according to the chosen behavior. Adding a new profile means adding
## an enum entry above and a match arm here.
func _apply_movement_profile(delta: float, effective_speed: float) -> void:
	match movement_profile:
		MovementProfile.APPROACH_BAND:
			_apply_engagement_band_movement(delta, effective_speed)
		MovementProfile.MAINTAIN_DISTANCE:
			_apply_maintain_distance(delta, effective_speed)
		MovementProfile.PERCH_STATIC:
			_apply_perch_static(delta)
		MovementProfile.CIRCLE_AT_RANGE:
			_apply_circle_at_range(delta, effective_speed)
		MovementProfile.AMBUSH:
			# Once triggered, AMBUSH switches itself to APPROACH_BAND
			# (handled in _check_detection). If we somehow get here
			# pre-trigger, fall back to standstill — degenerate but
			# safe.
			velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)


## MAINTAIN_DISTANCE: same as APPROACH_BAND when out of range, but if
## the player crosses INSIDE min_engage_range we PUSH AWAY from them
## rather than drift toward the band. The base behavior already does
## something like this (it backs off if too close), but it does so
## by interpolating toward the band center — which is slow and lets
## the player close. MAINTAIN_DISTANCE adds an active retreat
## acceleration toward "directly opposite the player" until distance
## is comfortably restored. Used by ranged enemies whose fantasy
## is "I don't want you near me" — goblin_bow, marksman archetypes.
func _apply_maintain_distance(delta: float, effective_speed: float) -> void:
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	# Below min_engage_range: hard retreat. Player has pushed too close,
	# we run. Direction = AWAY from player. Speed is the base
	# effective_speed; we don't accelerate faster because that'd let
	# them outrun the player which feels unfair, but they do commit
	# fully to the retreat (no friction-decel toward zero).
	if dist < min_engage_range and dist > 1.0:
		var away: Vector2 = -to_player / dist
		velocity = velocity.move_toward(away * effective_speed, acceleration * delta)
		return
	# Otherwise behave like APPROACH_BAND — drift toward ideal range
	# from the far side. This handles "I was retreating but player
	# disengaged; ease back to ideal sniping spot."
	_apply_engagement_band_movement(delta, effective_speed)


## PERCH_STATIC: never moves. Just decelerates to zero and stays put.
## The wind-up trigger above still fires when player walks into range,
## but the enemy itself doesn't reposition. Used for stationary
## attackers — perchers, immobile turrets.
func _apply_perch_static(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta * 2.0)


## CIRCLE_AT_RANGE: orbit the player at the engagement band's
## ideal radius (midpoint between min_engage and _attack_range).
## Movement direction is the TANGENT to the player-vector, picked
## by circle_direction. Combined with a slight radial correction
## to stay near ideal distance — drift inward if too far, outward
## if too close. Feels like a scout who keeps moving and never
## commits to a position.
func _apply_circle_at_range(delta: float, effective_speed: float) -> void:
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist < 1.0:
		# Standing on top of player; pick an arbitrary tangent.
		velocity = Vector2(1, 0) * effective_speed
		return
	var radial: Vector2 = to_player / dist
	# Tangent — 90° rotation of the radial. Sign flipped by
	# circle_direction so authoring can pick which way to sweep.
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * sign(circle_direction)
	# Ideal orbit radius: midpoint of the engagement band, clamped to
	# something sensible if min_engage was zero (full _attack_range is
	# already pretty close).
	var ideal_radius: float = (min_engage_range + _attack_range) * 0.5
	if ideal_radius < 1.0:
		ideal_radius = _attack_range * 0.6
	# Radial correction: small bias inward or outward to stay near
	# the ideal. Subtle so the tangential component dominates.
	var radial_bias: float = clamp((dist - ideal_radius) / ideal_radius, -1.0, 1.0)
	var move_dir: Vector2 = (tangent - radial * radial_bias * 0.4).normalized()
	velocity = velocity.move_toward(move_dir * effective_speed, acceleration * delta)


## Pure movement: steer toward the engagement band [min_engage_range,
## _attack_range] without touching AI state. Factored out of
## _process_chase so subclasses can reuse it during RECOVER — bosses
## need to keep repositioning while their persistent hitboxes are
## active, otherwise they read as turrets that go inert between volleys.
##
## Caller is responsible for state transitions; this only writes
## velocity. Reads _player, _attack_range, min_engage_range, max_speed,
## acceleration, status_component — same inputs as _process_chase.
func _apply_engagement_band_movement(delta: float, effective_speed: float) -> void:
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	var to_player: Vector2 = _player.global_position - global_position
	var dist: float = to_player.length()
	# Inside the engagement band — settle in place. The boss reaches
	# its sweet spot and stops to fire; only the *outside* of the band
	# triggers chase pressure.
	if dist <= _attack_range and dist >= min_engage_range:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	if dist > 1.0:
		var dir := to_player / dist
		# Too close → back off. Same sign-flip rule as _process_chase
		# so the boss kites away from a player crowding it.
		if dist < min_engage_range:
			dir = -dir
		velocity = velocity.move_toward(dir * effective_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)


func _process_wind_up(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta * 2.0)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_ai_state = AIState.ATTACK


func _process_attack() -> void:
	# Read the weapon picked at WIND_UP trigger time. Falls back to the
	# main weapon if for some reason _current_attack_weapon was never
	# set (shouldn't happen in normal flow — every wind-up path above
	# assigns it — but the fallback keeps a misconfigured enemy from
	# silently no-op-ing instead of just attacking).
	var firing: Weapon = _current_attack_weapon
	if firing == null:
		firing = weapon
	if _player == null or firing == null:
		_ai_state = AIState.RECOVER
		_state_timer = recover_duration
		_current_attack_weapon = null
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	if firing is MeleeWeapon:
		var melee: MeleeWeapon = firing
		if melee.user_lunge_distance > 0.0:
			# Compute the initial velocity that, under the RECOVER state's
			# linear deceleration (`acceleration` px/s²), will carry the
			# enemy *exactly* `user_lunge_distance` pixels before stopping.
			#
			#   d = v₀² / (2a)  →  v₀ = √(2 · a · d)
			velocity = aim * sqrt(2.0 * acceleration * melee.user_lunge_distance)

	firing.attack(self, aim)

	_ai_state = AIState.RECOVER
	_state_timer = recover_duration
	# Clear the chosen-weapon slot so the next wind-up picks fresh
	# based on whatever the player's distance is at that moment.
	_current_attack_weapon = null


func _process_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_ai_state = AIState.CHASE


func _process_stunned(delta: float) -> void:
	# Stunned enemies are inert: friction stops them, AI logic skips.
	# Decelerate faster than normal because the stun should snap to a
	# halt — a sliding-while-staggered enemy reads as glitchy.
	velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta * 3.0)
	_state_timer -= delta
	if _state_timer <= 0.0:
		_ai_state = AIState.CHASE


## Emit stagger update if this enemy is the engaged boss. Walked from
## the base class so boss subclasses don't need their own stagger
## bookkeeping — the boss subclass just connects boss_stagger_changed
## on its own engage path. _emit_stagger_if_boss is virtual-ish: the
## boss subclass overrides it to actually emit; everyone else no-ops.
func _emit_stagger_if_boss() -> void:
	pass


# ============================================================================
# HIT / DAMAGE / DEATH
# ============================================================================

func _on_hit_received(amount: float, info: Dictionary, source: HitboxComponent) -> void:
	amount *= status_component.get_damage_taken_multiplier()
	health_component.take_damage(amount, info)
	EventBus.damage_dealt_visual.emit(self, amount, info)
	_hit_flash_timer = 3  # white flash for 3 physics frames

	# Stash the most recent incoming damage info. _on_died reads this to
	# fire `enemy_killed_by` with the killing-blow metadata, which is
	# how run-scoped kill counters (Spear-Dane = melee, Arrow-Crow =
	# ranged) categorize this death. Storing the *most recent* hit and
	# not the cumulative damage source means a kill is attributed to
	# whoever struck the final blow — same intuition as kill-feed
	# attribution in most games.
	_last_hit_info = info

	# IDLE → CHASE on first hit. Routed through _alert() so a bow shot
	# that drops an enemy out of IDLE also wakes up any nearby enemies
	# within its shout-radius — the exact scenario the user flagged:
	# "the player can no longer cherry-pick one enemy from a packed
	# group with a bow from outside the others' detection range."
	if _ai_state == AIState.IDLE:
		_alert()

	# Status DoT damage shouldn't grant the stagger combo punish — only
	# real player swings/shots should. The status_component routes burn/
	# poison through _on_status_tick_damage (a separate path), so any
	# call landing in _on_hit_received is a direct hit; no extra check
	# needed unless future code starts routing DoTs through here.

	# ── STAGGER MECHANIC ─────────────────────────────────────────────
	# The trigger is a *parry window*, not the whole wind-up. Hits land
	# during the red-flash portion of WIND_UP (the last STAGGER_WINDOW
	# seconds, matching the visual cue) — OR on the single ATTACK frame
	# itself — count as a parry and stagger the enemy. Hits earlier in
	# the wind-up (yellow phase) deal damage but don't interrupt; the
	# enemy keeps committing to the swing.
	#
	# This is the moment-of-commitment design: you can't just spam a
	# fast weapon to keep enemies locked. You have to read the
	# telegraph, time the strike, and earn the punish.
	#
	# Once the meter crosses stagger_threshold, the NEXT parry swaps
	# the short stun for a long one and resets the meter — the "earn
	# the big punish" beat. For mooks this rarely matters (they die
	# first); for bosses, it's the mastery loop the player practices.
	#
	# Hits during STUNNED extend the timer slightly so chaining hits
	# during a stun feels rewarding. We cap the extension via
	# STUN_HIT_EXTENSION_MAX so a long stun can't be infinitely
	# prolonged into a chain-lock.
	var is_parry: bool = (
		(_ai_state == AIState.WIND_UP and _state_timer <= STAGGER_WINDOW)
		or _ai_state == AIState.ATTACK
	)
	if is_parry:
		_stagger += stagger_gain_per_hit
		var triggers_long_stun: bool = _stagger >= stagger_threshold
		var stun_dur: float = stagger_long_stun_duration if triggers_long_stun else stun_duration_base
		if triggers_long_stun:
			_stagger = 0.0  # reset meter on long-stun trigger
		_ai_state = AIState.STUNNED
		_state_timer = stun_dur
		velocity = Vector2.ZERO
		EventBus.enemy_staggered.emit(self, stun_dur, triggers_long_stun)
		_emit_stagger_if_boss()
	elif _ai_state == AIState.STUNNED:
		# Chain extension while already stunned. Cap the remaining timer
		# at STUN_HIT_EXTENSION_MAX so you can't perma-lock with a fast
		# weapon — but each hit gives the player real value during the
		# punish window.
		_state_timer = minf(_state_timer + 0.15, STUN_HIT_EXTENSION_MAX)

	if info.has("on_hit_effects"):
		status_component.try_apply_each(info["on_hit_effects"], source)

	if info.has("knockback") and is_instance_valid(source):
		var dir := (global_position - source.global_position).normalized()
		velocity = dir * float(info["knockback"])


func _on_status_tick_damage(amount: float, info: Dictionary) -> void:
	health_component.take_damage(amount, info)
	EventBus.damage_dealt_visual.emit(self, amount, info)


func _on_died() -> void:
	# Two-signal split: entity_died for "something is gone" subscribers
	# (QuestManager kill-counts a quest objective), enemy_killed for
	# "how did it die" subscribers (run-scope kill counters that need
	# the weapon category). Both fire here so neither subscriber type
	# has to reach into the dying enemy's private state.
	EventBus.entity_died.emit(self)
	EventBus.enemy_killed.emit(self, _last_hit_info)
	RunState.mark_node_consumed(self)
	call_deferred("_spawn_drops_at", global_position, get_parent())
	queue_free()


func _spawn_drops_at(spawn_pos: Vector2, parent: Node) -> void:
	if not is_instance_valid(parent):
		return

	# Runtime drops are NOT marked persistent_per_run. The pickup.gd
	# contract (line 18-20) explicitly says to leave it false for runtime
	# drops because their auto-generated node names (@Pickup@37 etc.)
	# are unstable across scene loads — a different enemy's drop can
	# inherit the same auto-name, match the consumed set, and silently
	# delete itself on spawn. The old code set persistent_per_run = true
	# in an attempt to make drops survive room transitions, but that only
	# worked while the drop node still existed in a persisted scene tree
	# (which it never does after a full scene reload), so the flag only
	# contributed the collision risk. Drops vanishing on room exit is
	# the correct contract for a roguelite — loot left on the ground is
	# forfeit when you leave.

	var currency := randi_range(currency_drop_min, currency_drop_max)
	if currency > 0:
		var p: Pickup = _PICKUP_SCENE.instantiate()
		p.currency_amount = currency
		parent.add_child(p)
		p.global_position = spawn_pos

	# Rare-drop roll runs BEFORE the regular drop. If it succeeds, we
	# drop one item from rare_item_drops and short-circuit — no regular
	# drop on the same kill. This way "did the orc drop the shiv?" is
	# a single yes/no that doesn't share probability mass with the
	# normal reagent drops, and a rare-drop-bearing enemy still feels
	# like a normal enemy on the (overwhelming) majority of kills
	# where the rare roll fails.
	if not rare_item_drops.is_empty() and rare_drop_chance > 0.0 and randf() < rare_drop_chance:
		var rp: Pickup = _PICKUP_SCENE.instantiate()
		rp.item = rare_item_drops.pick_random()
		parent.add_child(rp)
		rp.global_position = spawn_pos + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		return

	if randf() < item_drop_chance:
		var pool: Array = item_drops if not item_drops.is_empty() else _load_default_drops()
		if not pool.is_empty():
			var p: Pickup = _PICKUP_SCENE.instantiate()
			p.item = pool.pick_random()
			parent.add_child(p)
			p.global_position = spawn_pos + Vector2(randf_range(-16, 16), randf_range(-16, 16))


func _load_default_drops() -> Array:
	var pool: Array = []
	for path in _DEFAULT_DROP_PATHS:
		var it: Resource = load(path)
		if it:
			pool.append(it)
	return pool


# ============================================================================
# DRAW
# ============================================================================

## Raised whenever health changes so the HP bar redraws on the next
## frame. Connected to HealthComponent.health_changed in _ready, so it
## covers every damage/heal path (direct hits, status ticks, and any
## future heal) without each call site having to remember to flag.
func _on_health_changed_redraw(_current: float, _maximum: float) -> void:
	_needs_redraw = true


## Whether this enemy's _draw produces frame-varying output that must be
## redrawn every physics frame. The base placeholder-circle _draw does
## (the weapon-icon dot tracks the player, the wind-up flash and stun
## stars animate, the stagger meter decays); the base sprite path draws
## Resolve a sprite_name to its full res:// path by checking known
## subdirectories. Returns "" if not found anywhere.
static func _find_sprite_sheet(sname: String) -> String:
	var search_dirs: Array[String] = [
		"res://sprites/Enemies/Enemies/",
		"res://sprites/Enemies/Bosses/",
		"res://sprites/Enemies/NPCs/",
		"res://sprites/Enemies/",
		"res://sprites/",
	]
	for dir_path in search_dirs:
		var full: String = dir_path + sname + ".png"
		if ResourceLoader.exists(full):
			return full
	push_warning("SpriteSheet: '%s' not found in any search path" % sname)
	return ""


## Update the Sprite2D frame for the 3×4 sprite sheet.
## Reads velocity for facing direction, _ai_state for row selection.
func _update_sheet_frame() -> void:
	# Update facing from velocity — only when actually moving so the
	# enemy holds its last facing during stationary states.
	if velocity.length_squared() > 1.0:
		_facing_dir = _facing_dir_from_velocity(velocity)
	elif is_instance_valid(_player) and _ai_state != AIState.IDLE:
		# When stationary but engaged (wind-up, attack, recover), face
		# toward the player rather than holding stale velocity direction.
		_facing_dir = _facing_dir_from_velocity(
			_player.global_position - global_position)

	# Pick row from state.
	# For multi-attack sheets (vframes > 3), attack rows are 1..N-1
	# and recover is always the LAST row. _attack_sprite_row selects
	# which attack variant (0 = first attack row, 1 = second, etc.)
	var total_rows: int = _sheet_sprite.vframes
	var recover_row: int = total_rows - 1  # always last row
	var row: int = _ROW_IDLE

	match _ai_state:
		AIState.WIND_UP, AIState.ATTACK:
			# Row 1 + _attack_sprite_row offset, clamped below recover
			row = mini(1 + _attack_sprite_row, recover_row - 1)
		AIState.RECOVER, AIState.STUNNED:
			row = recover_row

	# Clamp row for 1-row legacy sheets
	if _sheet_sprite.vframes == 1:
		row = 0

	_sheet_sprite.frame = row * _SHEET_COLS + _facing_dir

	# ── Combat tinting via shader ──
	# Uses the combat_tint shader which lerps sprite pixels toward a
	# tint color at a given strength. Works on any base color (dark
	# sprites, fire-red sprites, etc.) because it replaces rather than
	# multiplies. Same visual signals as the placeholder circles:
	#   yellow  = winding up (caution)
	#   red     = parry window (act NOW)
	#   pale    = stunned (punish window)
	var tint := Color.WHITE
	var strength := 0.0

	match _ai_state:
		AIState.WIND_UP:
			if _state_timer <= STAGGER_WINDOW:
				# Red flash — parry window open.
				tint = Color(1.0, 0.25, 0.2)
				strength = 0.55
			else:
				# Yellow caution — attack incoming.
				tint = Color(1.0, 0.9, 0.3)
				strength = 0.4
		AIState.ATTACK:
			# Brief red pulse on the damage frame.
			tint = Color(1.0, 0.3, 0.25)
			strength = 0.35
		AIState.STUNNED:
			# Pale washed-out — staggered.
			tint = Color(0.8, 0.8, 1.0)
			strength = 0.45

	# Layer status-effect tints (burn, poison, chill, etc.) on top.
	# If a status tint is active AND we already have a state tint,
	# the status tint takes partial priority — it blends on top so
	# the player can still read both signals.
	var status_tint: Color = status_component.get_tint()
	if status_tint.a > 0.0:
		tint = tint.lerp(Color(status_tint.r, status_tint.g, status_tint.b), status_tint.a)
		strength = maxf(strength, status_tint.a * 0.6)

	# Damage flash — brief white pulse on hit. Overrides everything
	# else so the player always sees the impact regardless of state.
	if _hit_flash_timer > 0:
		tint = Color.WHITE
		strength = 0.6 + (_hit_flash_timer * 0.1)  # 0.9 → 0.8 → 0.7 over 3 frames
		_hit_flash_timer -= 1

	var mat: ShaderMaterial = _sheet_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("tint_color", tint)
		mat.set_shader_parameter("tint_strength", strength)


## Convert a direction vector to the nearest cardinal FacingDir.
func _facing_dir_from_velocity(dir: Vector2) -> int:
	if dir.length_squared() < 0.01:
		return _facing_dir  # keep current
	if absf(dir.x) >= absf(dir.y):
		return _FacingDir.EAST if dir.x > 0.0 else _FacingDir.WEST
	else:
		return _FacingDir.SOUTH if dir.y > 0.0 else _FacingDir.NORTH


## Does this enemy's _draw() need calling every physics frame?
## Sprite-sheet enemies and AnimatedSprite2D enemies only need redraws
## on health changes (the HP bar). Placeholder-circle enemies animate
## continuously (body tint pulses, stun stars, etc.) and need every-frame
## redraws.
func _draw_animates_per_frame() -> bool:
	return sprite == null and _sheet_sprite == null


## Redraw only when it can matter: every frame for continuously-animating
## draws, otherwise only when health changed (_needs_redraw). This is what
## removes the per-frame CanvasItem invalidation for sprite-based enemies
## in dense rooms — their bar just sits there until they take a hit.
func _redraw_if_needed() -> void:
	if _draw_animates_per_frame() or _needs_redraw:
		queue_redraw()
		_needs_redraw = false


func _draw() -> void:
	# If this enemy has a sprite (AnimatedSprite2D OR sheet Sprite2D),
	# we skip the circle drawing but keep the HP bar UI visible.
	if sprite != null or _sheet_sprite != null:
		var spr_hp: float = health_component.health_percent() if health_component else 1.0
		var bar_w: float = body_radius * 1.7
		var bar_y: float = -body_radius - 24.0
		draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w, 3)), Color(0.2, 0.0, 0.0))
		draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w * hp_pct, 3)), Color(1.0, 0.3, 0.3))
		return

	# FALLBACK: Draw placeholder circles for enemies without sprites
	var body: Color = body_tint
	match _ai_state:
		AIState.IDLE:
			body = body.lerp(Color(0.3, 0.3, 0.3), 0.55)
		AIState.WIND_UP:
			# Red flash uses STAGGER_WINDOW so the visual cue exactly
			# matches the parry-window input timing. Player learns the
			# rhythm: yellow = "they're winding up," red = "STRIKE NOW."
			if _state_timer <= STAGGER_WINDOW:
				body = body.lerp(Color(1.0, 0.2, 0.2), 0.85)
			else:
				body = body.lerp(Color(1.0, 0.9, 0.3), 0.65)
		AIState.STUNNED:
			# Pale washed-out body reads as "they're rattled" without
			# needing a new sprite. Same affordance as a fighting-game
			# stagger flash.
			body = body.lerp(Color(0.85, 0.85, 1.0), 0.55)

	var tint: Color = status_component.get_tint()
	if tint.a > 0.0:
		body = body.lerp(Color(tint.r, tint.g, tint.b, 1.0), tint.a)

	_draw_body(body)

	var icon_dir: Vector2 = Vector2.RIGHT
	if is_instance_valid(_player):
		icon_dir = (_player.global_position - global_position).normalized()
	var icon_pos: Vector2 = icon_dir * (body_radius * 0.5)
	draw_circle(icon_pos, 3.0, weapon_icon_color)

	if _ai_state == AIState.WIND_UP and weapon != null:
		# Threshold matched to body flash + parry window — every red
		# visual lights up at the same moment so the player can read the
		# cue from peripheral (body) or focal vision (telegraph) and get
		# the same timing.
		var telegraph_color: Color = Color(1.0, 0.2, 0.2, 0.6) if _state_timer <= STAGGER_WINDOW \
			else Color(1.0, 0.9, 0.3, 0.5)
		_draw_attack_telegraph(icon_dir, telegraph_color)

	var hp_pct: float = health_component.health_percent() if health_component else 1.0
	var bar_w: float = body_radius * 1.7
	var bar_y: float = -body_radius - 8.0
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w, 3)), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(Vector2(-bar_w * 0.5, bar_y), Vector2(bar_w * hp_pct, 3)), Color(1.0, 0.3, 0.3))

	# Stagger meter — only drawn when actively building OR while stunned.
	# Hidden at zero so unengaged enemies don't carry a permanent bar.
	if (_stagger > 0.0 or _ai_state == AIState.STUNNED) and stagger_threshold > 0.0:
		var stag_pct: float = clampf(_stagger / stagger_threshold, 0.0, 1.0)
		var stag_y: float = bar_y - 5.0
		draw_rect(Rect2(Vector2(-bar_w * 0.5, stag_y), Vector2(bar_w, 2)), Color(0.05, 0.05, 0.1))
		draw_rect(Rect2(Vector2(-bar_w * 0.5, stag_y), Vector2(bar_w * stag_pct, 2)), Color(0.85, 0.75, 1.0))

	if _ai_state == AIState.STUNNED:
		# Two small "stars" rotating overhead so the player can read
		# the stun state at a glance even when sprite anims aren't
		# loaded for this archetype.
		var t: float = Time.get_ticks_msec() / 1000.0
		for i in range(2):
			var a: float = t * 6.0 + i * PI
			var p := Vector2(cos(a), -0.3 + sin(a) * 0.15) * 10.0 + Vector2(0, -body_radius - 14.0)
			draw_circle(p, 1.8, Color(1.0, 0.95, 0.5))
	elif _ai_state != AIState.IDLE:
		draw_circle(Vector2(0, -2), 2.0, Color(1, 0.95, 0.5))


## Draw the placeholder body shape at the current body_radius, filled
## with `color` and outlined with a 1.5 px darker border for crisp
## readability against any tileset. CIRCLE still uses draw_circle for
## the smoothest possible silhouette; the rest use draw_colored_polygon
## + draw_polyline for the fill and outline.
func _draw_body(color: Color) -> void:
	var outline_color: Color = color.darkened(0.35)
	outline_color.a = color.a
	match body_shape:
		BodyShape.CIRCLE:
			draw_circle(Vector2.ZERO, body_radius, color)
			draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 32, outline_color, 1.5)
		_:
			var pts: PackedVector2Array = _body_polygon()
			draw_colored_polygon(pts, color)
			# Close the polyline by appending the first point.
			var outline_pts: PackedVector2Array = pts.duplicate()
			outline_pts.append(pts[0])
			draw_polyline(outline_pts, outline_color, 1.5)
			# SKULL detail: two dark eye sockets so the shape reads as
			# a face, not just an odd polygon. Drawn darker than the
			# body fill — they're hollow voids in bone.
			if body_shape == BodyShape.SKULL:
				var eye_color: Color = color.darkened(0.55)
				var eye_r: float = body_radius * 0.16
				var eye_y: float = -body_radius * 0.25
				var eye_spread: float = body_radius * 0.32
				draw_circle(Vector2(-eye_spread, eye_y), eye_r, eye_color)
				draw_circle(Vector2(eye_spread, eye_y), eye_r, eye_color)
				# Nasal cavity — tiny dark triangle below the eyes
				var nose_y: float = body_radius * 0.1
				var nose_w: float = body_radius * 0.1
				draw_colored_polygon(PackedVector2Array([
					Vector2(0, nose_y - body_radius * 0.08),
					Vector2(-nose_w, nose_y + body_radius * 0.08),
					Vector2(nose_w, nose_y + body_radius * 0.08),
				]), eye_color)


## Return the vertex ring for the current body_shape. Every polygon is
## centered at Vector2.ZERO and inscribed in a circle of body_radius,
## so the collision shape (which uses body_radius as its radius) and the
## visual always agree on size.
##
## Design notes on each shape:
##   DIAMOND  — rotated 45° so a point faces the player (top vertex);
##              reads as "pointy / fires things" from any angle.
##   TRIANGLE — equilateral, point UP. The forward-leaning silhouette
##              reads as "charges at you." Slightly oversized (×1.15)
##              so the visual area matches the circle's — a raw
##              inscribed equilateral triangle looks too small.
##   SQUARE   — axis-aligned, stable base. Rotated 0° (flat bottom)
##              rather than 45° (diamond) so the heavy/grounded read
##              is distinct from the nimble diamond.
##   HEXAGON  — flat-top orientation. Six sides reads as "complex" and
##              is visually distinct from both circle (smooth) and
##              square (four corners).
##   STAR     — five-pointed, inner radius at 45% of outer. The spiky
##              silhouette is an immediate "danger" signal even in
##              peripheral vision. Slightly oversized (×1.1) so the
##              points extend past the collision circle.
func _body_polygon() -> PackedVector2Array:
	match body_shape:
		BodyShape.DIAMOND:
			var r: float = body_radius
			return PackedVector2Array([
				Vector2(0, -r),        # top
				Vector2(r, 0),         # right
				Vector2(0, r),         # bottom
				Vector2(-r, 0),        # left
			])
		BodyShape.TRIANGLE:
			# Slightly oversized so visual area ≈ circle area.
			var r: float = body_radius * 1.15
			# Point-up equilateral: top vertex at -r, two base vertices
			# at +0.5r, spread ±(√3/2)r horizontally.
			var half_base: float = r * 0.866  # sin(60°)
			var cy: float = r * 0.25  # shift center down so it looks balanced
			return PackedVector2Array([
				Vector2(0, -r + cy),              # apex
				Vector2(half_base, r * 0.5 + cy), # bottom-right
				Vector2(-half_base, r * 0.5 + cy),# bottom-left
			])
		BodyShape.SQUARE:
			var r: float = body_radius * 0.82  # inscribed square side ≈ r√2; scale to match circle area
			return PackedVector2Array([
				Vector2(-r, -r),
				Vector2(r, -r),
				Vector2(r, r),
				Vector2(-r, r),
			])
		BodyShape.HEXAGON:
			# Flat-top hexagon.
			var pts := PackedVector2Array()
			for i in 6:
				var angle: float = TAU * i / 6.0 + PI / 6.0  # +30° for flat-top
				pts.append(Vector2(cos(angle), sin(angle)) * body_radius)
			return pts
		BodyShape.SKULL:
			# Skeleton King: minimalist skull silhouette. Wide rounded
			# cranium on top, slight temple narrowing, tapers to a
			# narrower jaw with a small chin point. The decorative
			# crown in boss_enemy.gd sits on top of this — the skull
			# is the head, the crown is the accessory.
			var r: float = body_radius
			var pts := PackedVector2Array()
			# Chin (bottom center, slightly pointed)
			pts.append(Vector2(0, r * 0.85))
			# Jaw — narrower than cranium
			pts.append(Vector2(r * 0.45, r * 0.65))
			pts.append(Vector2(r * 0.55, r * 0.3))
			# Temple notch — slight inward curve
			pts.append(Vector2(r * 0.65, r * 0.05))
			# Cranium — wide rounded top (right side up to top, then left side down)
			pts.append(Vector2(r * 0.85, -r * 0.2))
			pts.append(Vector2(r * 0.9, -r * 0.5))
			pts.append(Vector2(r * 0.75, -r * 0.8))
			pts.append(Vector2(r * 0.45, -r * 0.95))
			pts.append(Vector2(0, -r))  # top of skull
			pts.append(Vector2(-r * 0.45, -r * 0.95))
			pts.append(Vector2(-r * 0.75, -r * 0.8))
			pts.append(Vector2(-r * 0.9, -r * 0.5))
			pts.append(Vector2(-r * 0.85, -r * 0.2))
			# Left temple notch
			pts.append(Vector2(-r * 0.65, r * 0.05))
			# Left jaw
			pts.append(Vector2(-r * 0.55, r * 0.3))
			pts.append(Vector2(-r * 0.45, r * 0.65))
			return pts
		BodyShape.PINCERS:
			# Giant Scorpion: a wide oval body with two forward-facing
			# pincer/claw extensions. Reads as "arthropod with grabbers"
			# from any angle. The pincers point upward (toward the player
			# in the default facing).
			var r: float = body_radius
			var pts := PackedVector2Array()
			# Main body: slightly wider than tall (1.15× horizontal).
			var bw: float = r * 1.15
			var bh: float = r * 0.85
			# Body ellipse approximation (12 segments, bottom half only).
			for i in range(7):
				var angle: float = PI * 0.5 + PI * i / 6.0
				pts.append(Vector2(cos(angle) * bw, sin(angle) * bh))
			# Left pincer: curves outward then inward to a point.
			pts.append(Vector2(-bw, -bh * 0.3))
			pts.append(Vector2(-r * 1.3, -r * 0.9))
			pts.append(Vector2(-r * 0.85, -r * 1.25))
			pts.append(Vector2(-r * 0.55, -r * 0.75))
			# Head notch between pincers.
			pts.append(Vector2(0.0, -bh * 0.6))
			# Right pincer: mirror of left.
			pts.append(Vector2(r * 0.55, -r * 0.75))
			pts.append(Vector2(r * 0.85, -r * 1.25))
			pts.append(Vector2(r * 1.3, -r * 0.9))
			pts.append(Vector2(bw, -bh * 0.3))
			return pts
		BodyShape.FLAME:
			# Cinder Sovereign: a teardrop that widens at the base and
			# tapers to flickering points at the top — fire silhouette.
			# Three asymmetric flame tips prevent it from looking like a
			# generic water drop.
			var r: float = body_radius
			var pts := PackedVector2Array()
			# Wide rounded base (lower 2/3 of the shape).
			var base_w: float = r * 1.05
			for i in range(7):
				var angle: float = PI * 0.3 + PI * 0.4 * i / 6.0  # arc from ~55° to ~125°
				pts.append(Vector2(cos(angle) * base_w, sin(angle) * r * 0.8 + r * 0.1))
			# Left side taper.
			pts.append(Vector2(-r * 0.7, 0.0))
			pts.append(Vector2(-r * 0.5, -r * 0.5))
			# Left flame tip (shorter).
			pts.append(Vector2(-r * 0.35, -r * 1.05))
			pts.append(Vector2(-r * 0.15, -r * 0.65))
			# Center flame tip (tallest).
			pts.append(Vector2(0.0, -r * 1.35))
			# Right side taper.
			pts.append(Vector2(r * 0.15, -r * 0.65))
			# Right flame tip (medium).
			pts.append(Vector2(r * 0.3, -r * 1.15))
			pts.append(Vector2(r * 0.5, -r * 0.5))
			pts.append(Vector2(r * 0.7, 0.0))
			return pts
		BodyShape.MAW:
			# Sandworm Broodmother: a jagged-edged circle like a ring of
			# teeth — the view-from-above of a giant mouth erupting from
			# sand. 8 teeth alternate between outer (×1.2) and inner
			# (×0.7) radii, creating the saw-blade / monster-mouth read.
			var outer: float = body_radius * 1.2
			var inner: float = body_radius * 0.7
			var pts := PackedVector2Array()
			var tooth_count: int = 8
			for i in range(tooth_count * 2):
				var angle: float = TAU * i / (tooth_count * 2) - PI / 2.0
				var rad: float = outer if i % 2 == 0 else inner
				pts.append(Vector2(cos(angle), sin(angle)) * rad)
			return pts
		BodyShape.NOOSE:
			# Galgi the Bound: a lumpy, asymmetric mass of lashed corpses.
			# Wider than tall with irregular bulges — three or four bodies
			# knotted together, viewed from above. The organic asymmetry
			# contrasts sharply with the geometric regularity of every
			# other shape, immediately reading as "wrong" and "organic."
			var r: float = body_radius
			var pts := PackedVector2Array()
			# Bottom center (base of the hanging mass)
			pts.append(Vector2(0, r * 0.80))
			# Lower-right bulge (a torso)
			pts.append(Vector2(r * 0.50, r * 0.75))
			pts.append(Vector2(r * 0.90, r * 0.40))
			# Right shoulder bulge
			pts.append(Vector2(r * 1.10, r * 0.05))
			# Upper-right (head poking out)
			pts.append(Vector2(r * 0.85, -r * 0.35))
			pts.append(Vector2(r * 0.55, -r * 0.65))
			# Top notch (rope attachment indent)
			pts.append(Vector2(r * 0.15, -r * 0.90))
			pts.append(Vector2(0, -r * 0.95))
			pts.append(Vector2(-r * 0.20, -r * 0.85))
			# Upper-left bulge (another head/shoulder)
			pts.append(Vector2(-r * 0.60, -r * 0.55))
			pts.append(Vector2(-r * 0.95, -r * 0.15))
			# Left torso bulge (asymmetric — bigger than right)
			pts.append(Vector2(-r * 1.05, r * 0.20))
			pts.append(Vector2(-r * 0.80, r * 0.55))
			# Lower-left
			pts.append(Vector2(-r * 0.40, r * 0.78))
			return pts
		BodyShape.CRONE:
			# Drowned Crone: a hooked crescent — the bowed back of a bent
			# old woman, the curl of a breaking wave, the curve of a
			# fish-hook, all in one glyph. Outer arc sweeps the convex
			# spine; inner arc (offset center) carves the crescent void.
			# Concave, but so is MAW's saw-blade — draw_colored_polygon
			# triangulates simple concave polygons fine.
			var r: float = body_radius
			var pts := PackedVector2Array()
			var steps: int = 10
			# Outer spine: -125° → 125° at 1.05r (opens to the right).
			for i in range(steps + 1):
				var ang: float = deg_to_rad(lerp(-125.0, 125.0, float(i) / float(steps)))
				pts.append(Vector2(cos(ang), sin(ang)) * r * 1.05)
			# Inner arc back: 115° → -115°, smaller radius, center pushed
			# right — this carves the crescent's hollow.
			var inner_center := Vector2(r * 0.38, 0)
			for i in range(steps + 1):
				var ang: float = deg_to_rad(lerp(115.0, -115.0, float(i) / float(steps)))
				pts.append(inner_center + Vector2(cos(ang), sin(ang)) * r * 0.58)
			return pts
	# Fallback (should never hit — all enum values are covered).
	return PackedVector2Array([Vector2(-body_radius, 0), Vector2(0, -body_radius), Vector2(body_radius, 0)])


## Virtual telegraph hook — invoked during WIND_UP to draw the "incoming
## attack" cue at the spot the attack will land. Default implementation
## draws a circular arc at effective_range — works for any ranged or
## omnidirectional swing. Subclasses with shape-specific attacks
## (flamethrower cones, beams, fan spreads) should override to draw
## their actual hitbox shape so the player can position correctly.
##
## icon_dir is the unit-length vector pointing at the player (in local
## space). telegraph_color is already resolved (yellow during early
## wind-up, red during the parry window) — subclasses just pick how
## to draw with it.
## Virtual telegraph hook — draws the "incoming attack" indicator during
## WIND_UP. Shape matches the weapon's hitbox so the player sees the
## exact danger zone:
##   CIRCLE hitbox  → arc showing the sweep coverage area
##   RECTANGLE hitbox → directional corridor showing the thrust lane
## Subclasses (boss_enemy) can override for custom telegraphs.
func _draw_attack_telegraph(icon_dir: Vector2, telegraph_color: Color) -> void:
	var atk_weapon: Weapon = _current_attack_weapon if _current_attack_weapon != null else weapon
	if atk_weapon is MeleeWeapon:
		var mw: MeleeWeapon = atk_weapon
		if mw.hitbox_shape == MeleeWeapon.HitboxShape.RECTANGLE:
			# Thrust telegraph: narrow rectangle corridor showing the
			# exact lane the RECTANGLE hitbox covers. Length = swing_range
			# (+ lunge distance if applicable), width = arc_radius × 2.
			var reach: float = mw.swing_range + mw.user_lunge_distance
			var half_w: float = mw.arc_radius
			var tip: Vector2 = icon_dir * reach
			var perp: Vector2 = icon_dir.rotated(PI * 0.5)
			var pts := PackedVector2Array([
				-perp * half_w,
				tip - perp * half_w,
				tip + perp * half_w,
				perp * half_w,
			])
			draw_polyline(pts, telegraph_color, 2.0)
			# Arrow head at the tip for directionality
			var arrow_perp: Vector2 = perp * (half_w + 4.0)
			var arrow_base: Vector2 = tip - icon_dir * 10.0
			draw_colored_polygon(PackedVector2Array([
				tip, arrow_base + arrow_perp, arrow_base - arrow_perp,
			]), Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, telegraph_color.a * 0.5))
			return

	# Ranged weapon telegraph: dotted lines showing projectile directions.
	# Single projectile = one dotted line toward the player.
	# Multi-projectile = multiple lines fanned at the weapon's spread angle.
	if atk_weapon is RangedWeapon:
		var rw: RangedWeapon = atk_weapon
		var line_length: float = _attack_range * 0.5
		var dot_spacing: float = 8.0
		var dot_radius: float = 2.0
		var count: int = rw.projectile_count
		var spread_rad: float = deg_to_rad(rw.spread_degrees)

		if count <= 1 or spread_rad < 0.01:
			# Single projectile — one dotted line toward the player
			_draw_dotted_line(icon_dir, line_length, dot_spacing, dot_radius, telegraph_color)
		else:
			# Multiple projectiles — fan of dotted lines
			for i in count:
				var angle_offset: float
				if count > 1:
					# Same spread math as RangedWeapon.fire():
					# evenly distributed across spread_degrees, centered on icon_dir
					var t: float = float(i) / float(count - 1)  # 0..1
					angle_offset = -spread_rad * 0.5 + spread_rad * t
				else:
					angle_offset = 0.0
				var proj_dir: Vector2 = icon_dir.rotated(angle_offset)
				_draw_dotted_line(proj_dir, line_length, dot_spacing, dot_radius, telegraph_color)
		return

	# Default fallback: arc telegraph for anything not handled above
	# (PersistentHitboxWeapon, ExpandingRing, etc.)
	var telegraph_pos: Vector2 = icon_dir * (_attack_range * 0.5)
	var telegraph_radius: float = _attack_range * 0.5
	draw_arc(telegraph_pos, telegraph_radius, 0.0, TAU, 24, telegraph_color, 2.0)


## Draw a single dotted line from the enemy origin outward along `direction`.
## Used by ranged weapon telegraphs to show projectile paths.
func _draw_dotted_line(direction: Vector2, length: float, spacing: float,
		dot_r: float, color: Color) -> void:
	var dist: float = spacing  # start one spacing out from center (not on top of enemy)
	while dist < length:
		var pos: Vector2 = direction * dist
		draw_circle(pos, dot_r, color)
		dist += spacing
