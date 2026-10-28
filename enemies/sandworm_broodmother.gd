extends SandWorm
class_name SandwormBroodmother
## Sandworm Broodmother — desert mini-boss. The fully-grown matriarch
## of the sand-worm strain. Inherits her offspring's burrow trick
## (untouchable underground, surfacing only to attack) but trades the
## young's single-eruption design for a two-attack pattern:
##
##   ERUPT: she breaches and unloads a near-360° burst of projectiles
##          from her body in every direction. Long telegraph, heavy
##          coverage. Counterplay: get to medium-far range so projectile
##          spacing widens, then thread the gaps. Going point-blank also
##          works — the projectiles spawn outward from her, so the
##          spacing is widest at the body edge — but you eat the next
##          attack in melee.
##
##   SPIT:  forward-aimed fan of chitin shards. Short telegraph,
##          narrower hitbox. Counterplay: lateral sidestep out of the
##          cone. Don't backstep — fan tracks aim direction, you can't
##          outrun the angular sweep.
##
## Cycle: ERUPT → burrow phase → SPIT → burrow phase → ERUPT ...
## Each attack is followed by a surfaced recover (player's safe punish
## window) and then a forced burrow phase where she relocates
## underground (player can heal, reposition, but can't damage her).
##
## This class extends SandWorm rather than Enemy directly, so we
## inherit the entire burrow-state machinery: hurtbox toggling tied
## to AI state, mound-vs-full-body rendering, transition detection.
## The pieces we add on top:
##
## 1. Two-weapon cycle (similar to cinder_sovereign and giant_scorpion
##    patterns). After every fire we rebind `weapon`, `_attack_range`,
##    `wind_up_duration`, `recover_duration`, and the icon-dot color.
##
## 2. Forced burrow phase between attacks. The base SandWorm only
##    "burrows" during the CHASE state, which normally lasts one
##    frame between RECOVER and the next WIND_UP. For a boss we want
##    a real underground phase the player can read — both for pacing
##    (downtime to drink potions / reposition) and for the "she's
##    relocating, where will she emerge?" tension. We extend CHASE
##    with a countdown timer that blocks the base class's range-check
##    transition until the timer expires.
##
## 3. Per-attack telegraph drawing. The parent SandWorm's telegraph
##    handles only CIRCLE PersistentHitbox attacks; ranged-projectile
##    weapons fall through to the base Enemy's generic arc, which
##    doesn't communicate either attack shape correctly. We draw a
##    full ring for ERUPT (to show "all around") and a cone outline
##    for SPIT (to show the fan direction).
##
## 4. Icon color flips between attacks. Same trick the giant scorpion
##    uses for its pincer-vs-tail tell: the small weapon-direction dot
##    on the body shifts color between attacks, so the player gets
##    advance warning of which attack is coming during the burrow
##    phase BEFORE the wind-up flash even starts.

@export_group("Boss")
## Display name used in any boss HUD / floating text. The base Enemy's
## enemy_name is used for damage popups; this is for ceremonial UI.
@export var boss_display_name: String = "Sandworm Broodmother"

@export_group("Attacks")
## Slot 0 weapon: the omnidirectional eruption.
@export var weapon_erupt: RangedWeapon
## Slot 1 weapon: the forward-cone spit.
@export var weapon_spit: RangedWeapon

@export_group("Per-Attack Timings")
## Wind-up before the eruption fires. Longer than spit because the
## eruption is the high-stakes attack — projectiles in every direction,
## counterplay needs more time to read. Player sees the ring telegraph,
## moves to the gap or the close-edge, holds.
@export var wind_up_erupt: float = 1.50
## Wind-up before the spit. Shorter — the fan is reactive, sidestep
## suffices, and a slow wind-up here would make the spit feel
## punishingly slow against players who can already dodge it easily.
@export var wind_up_spit: float = 0.95
## Recover after the eruption. Long — she's exhaled most of her
## offspring inventory, takes a beat. Player's main punish window
## after the high-stakes attack.
@export var recover_erupt: float = 2.00
## Recover after the spit. Shorter — the spit is the tempo attack,
## her recover here is just resetting to fire again. Still a real
## punish window, just less generous than after erupt.
@export var recover_spit: float = 1.40

@export_group("Burrow Phase")
## How long the broodmother stays underground between attacks. This
## is FORCED time in the CHASE state — the base class's "transition
## to WIND_UP if player in range" check is blocked while this counts
## down. During this phase she's immune (inherited from SandWorm) and
## slowly walking toward the player; she emerges with the next attack
## at her new position.
##
## 1.2s gives the player enough downtime to commit a heal, reposition
## for the next telegraph, or close in for melee pressure. Shorter
## values make the boss feel relentless; longer values give the player
## too much free DPS opportunity (nothing to dodge while waiting).
@export var burrow_phase_duration: float = 1.20

@export_group("Attack Icon Colors")
## Color of the body's weapon-direction dot when ERUPT is the next
## attack. Golden-orange — visually echoes a "detonation" cue and is
## distinct enough from sand colors to read clearly against the
## broodmother's dark body tint.
@export var icon_color_erupt: Color = Color(1.00, 0.70, 0.25, 1.0)
## Color of the weapon-direction dot when SPIT is the next attack.
## Pale sickly green — suggests "wet, organic, caustic," and
## intentionally close to the poison.tres tint so any future status
## additions on the spit projectile read consistently with the rest
## of the game's poison visual language.
@export var icon_color_spit: Color = Color(0.65, 0.85, 0.40, 1.0)


# Parallel arrays indexed by slot. Built in _ready from exports so
# the base Enemy state machine reads scalars off the rebound fields
# (weapon, wind_up_duration, recover_duration) on the NEXT cycle.
var _weapons: Array[Weapon] = []
var _wind_ups: Array[float] = []
var _recovers: Array[float] = []
var _cycle_index: int = 0

# Remaining time in the forced burrow phase. While > 0, CHASE will
# not transition to WIND_UP even if the player is in range. Counts
# down each physics frame in _process_chase.
var _burrow_phase_remaining: float = 0.0


func _ready() -> void:
	# super() runs Enemy._ready and SandWorm._ready in sequence (which
	# wires hurtbox signals, snaps to burrowed state, etc.). After
	# that, we set up the cycle.
	super()

	_weapons = [weapon_erupt, weapon_spit]
	_wind_ups = [wind_up_erupt, wind_up_spit]
	_recovers = [recover_erupt, recover_spit]

	# Seed slot-0 values onto the base Enemy fields so the very first
	# CHASE → WIND_UP transition reads erupt's range and telegraph
	# timing. Without this, the first attack would use whatever the
	# .tscn happened to default into.
	if weapon_erupt != null:
		weapon = _weapons[0]
		_attack_range = weapon.effective_range()
		wind_up_duration = _wind_ups[0]
		recover_duration = _recovers[0]
		weapon_icon_color = icon_color_erupt


## Per-frame work. We piggyback on the parent chain (Enemy →
## SandWorm → here) and then inspect what state we ended up in.
## Specifically: when the base class transitioned us from RECOVER
## to CHASE this frame, that's the moment we start the forced
## burrow phase. Recording `pre` BEFORE super lets us see the
## previous state without racing the parent's _prev_ai_state
## bookkeeping.
func _physics_process(delta: float) -> void:
	var pre_state: int = _ai_state
	super(delta)
	if pre_state == AIState.RECOVER and _ai_state == AIState.CHASE:
		# Just finished an attack's recover and re-entered chase.
		# Start the underground phase. Burrowed visuals will already
		# be applied by SandWorm._physics_process this same frame
		# (it caught the same transition for hurtbox + mound flip).
		_burrow_phase_remaining = burrow_phase_duration


## Override the chase behavior to enforce the forced burrow phase.
## While `_burrow_phase_remaining` is positive we DO want to keep
## moving (slow stalking toward player, same engagement-band logic
## the base uses) but we DON'T want the base's range-check to
## transition us to WIND_UP — we're stuck underground until the
## timer expires. After the timer hits zero, super(delta) runs and
## the normal CHASE behavior (transition to WIND_UP if in range)
## resumes.
func _process_chase(delta: float) -> void:
	if _burrow_phase_remaining > 0.0:
		_burrow_phase_remaining -= delta
		# Slow movement during the burrow stalk. Mirrors the
		# engagement-band logic in Enemy._process_chase, just
		# stripped of the range-check that triggers wind-up. The
		# multiplicative speed composition (status × difficulty) is
		# preserved so chill, slow effects, and the difficulty knob
		# all still apply.
		var effective_speed: float = max_speed \
			* status_component.get_speed_multiplier() \
			* DifficultySettings.get_enemy_speed_multiplier()
		_apply_engagement_band_movement(delta, effective_speed)
		return
	super(delta)


## Fire the current cycle slot's weapon, then advance the cycle and
## rebind the base Enemy's scalar fields so the next iteration of
## CHASE → WIND_UP → ATTACK reads the correct values. Mirrors the
## per-slot pattern used in giant_scorpion.gd and cinder_sovereign.gd
## — the base Enemy was designed around one weapon at a time, so
## multi-attack enemies have to re-point its inputs after every fire.
func _process_attack() -> void:
	if _player == null or _weapons.is_empty():
		_ai_state = AIState.RECOVER
		_state_timer = recover_duration
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	var current: Weapon = _weapons[_cycle_index]
	if current != null:
		current.attack(self, aim)

	# Save the recover length for the slot we JUST fired before we
	# advance the index — recover belongs to the action just performed,
	# not the next one.
	var this_recover: float = _recovers[_cycle_index]

	_cycle_index = (_cycle_index + 1) % _weapons.size()

	# Rebind base-class fields for the next slot. _attack_range gates
	# the CHASE → WIND_UP transition; wind_up_duration sets the
	# state-timer once that transition fires. If either is left
	# pointing at the previous slot's values, the boss winds up for
	# erupt's duration but fires spit (or vice versa) — telegraph
	# duration and weapon mismatch.
	weapon = _weapons[_cycle_index]
	if weapon != null:
		_attack_range = weapon.effective_range()
	wind_up_duration = _wind_ups[_cycle_index]

	# Icon color flip for the next attack. The dot is drawn during
	# CHASE too (base Enemy._draw renders it whenever _ai_state isn't
	# IDLE), so the new color shows up immediately at the start of
	# the next burrow phase — giving the player a heads-up channel
	# that doesn't depend on the body flash inside wind-up. Pairs
	# with the per-attack telegraph shape (ring vs cone) so the
	# player has TWO concurrent reads on which attack is incoming.
	weapon_icon_color = icon_color_erupt if _weapons[_cycle_index] == weapon_erupt else icon_color_spit

	_ai_state = AIState.RECOVER
	_state_timer = this_recover


## Per-attack telegraph drawing. Dispatched by base Enemy._draw
## during WIND_UP. SandWorm's version handles CIRCLE PersistentHitbox
## attacks (the regular eruption); for our two ranged attacks we
## need different shapes.
func _draw_attack_telegraph(icon_dir: Vector2, telegraph_color: Color) -> void:
	if weapon == weapon_erupt:
		_draw_erupt_ring(telegraph_color)
	elif weapon == weapon_spit:
		_draw_spit_cone(icon_dir, telegraph_color)
	else:
		# Unknown weapon — defer to parent chain. SandWorm handles
		# CIRCLE persistent-hitbox; if that doesn't match either,
		# the base draws a generic arc-at-half-range. Either way we
		# get something on screen rather than a missing telegraph.
		super(icon_dir, telegraph_color)


## ERUPT telegraph: a ring at the projectile-spawn perimeter plus a
## faint danger-fill out to a meaningful reach. Reads as "AROUND ME,
## ALL DIRECTIONS." We don't draw the full projectile travel distance
## because that's the entire room — useless as a positioning cue.
## Instead we draw a "shell of imminent danger" at ~half the projectile
## range, where dodging matters most.
func _draw_erupt_ring(telegraph_color: Color) -> void:
	if weapon_erupt == null:
		return
	# Inner ring — touches the body so player reads "she's about to
	# erupt outward from her position." Just outside body_radius so
	# the ring is visible against the body fill.
	var inner_r: float = body_radius + 6.0
	# Outer ring — half the projectile flight distance. This is the
	# zone the player needs to be outside of when projectiles spawn.
	# Going beyond the outer ring increases gap spacing between
	# projectiles (they fan out radially), making the burst easier
	# to thread.
	var outer_r: float = weapon_erupt.projectile_speed * weapon_erupt.projectile_lifetime * 0.5

	# Faint danger-zone fill: annulus between inner and outer.
	# Building an annulus polygon requires the outer ring CCW then
	# the inner ring CW so the hole punches through.
	var sides: int = 32
	var fill: Color = Color(telegraph_color.r, telegraph_color.g,
		telegraph_color.b, telegraph_color.a * 0.18)
	var ring: PackedVector2Array = PackedVector2Array()
	for i in sides:
		var a: float = TAU * float(i) / float(sides)
		ring.append(Vector2(cos(a), sin(a)) * outer_r)
	# Inner cutout — counterclockwise traversal back the other way.
	for i in range(sides - 1, -1, -1):
		var a: float = TAU * float(i) / float(sides)
		ring.append(Vector2(cos(a), sin(a)) * inner_r)
	draw_colored_polygon(ring, fill)

	# Outlines: both rings, same color, thickness keyed to the
	# parry-window urgency the base class controls via telegraph_color.
	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, sides, telegraph_color, thickness)
	draw_arc(Vector2.ZERO, outer_r, 0.0, TAU, sides, telegraph_color, max(1.5, thickness - 0.5))


## SPIT telegraph: a cone outline matching the fan's actual spread,
## anchored at the broodmother's center and pointing at the player.
## Length is half the projectile flight distance — same logic as
## erupt's outer ring, the dodge zone matters more than the
## maximum-reach.
func _draw_spit_cone(icon_dir: Vector2, telegraph_color: Color) -> void:
	if weapon_spit == null:
		return
	var aim_angle: float = icon_dir.angle()
	var half_rad: float = deg_to_rad(weapon_spit.spread_degrees * 0.5)
	var length: float = weapon_spit.projectile_speed * weapon_spit.projectile_lifetime * 0.5

	# Cone polygon: tip at origin, two outer points at the spread
	# extents, optional arc points on the far edge for a rounded
	# fan front. Matches the visual language of cinder_maw's cone
	# telegraph so the player learns "cone outline = directional
	# spread attack" across multiple enemies.
	var arc_steps: int = 8
	var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for i in range(arc_steps + 1):
		var t: float = float(i) / float(arc_steps)
		var local_ang: float = lerp(-half_rad, half_rad, t)
		pts.append(Vector2(cos(aim_angle + local_ang), sin(aim_angle + local_ang)) * length)

	var fill: Color = Color(telegraph_color.r, telegraph_color.g,
		telegraph_color.b, telegraph_color.a * 0.35)
	draw_colored_polygon(pts, fill)

	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	var n: int = pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		draw_line(a, b, telegraph_color, thickness)
