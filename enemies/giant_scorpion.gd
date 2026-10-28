extends Enemy
class_name GiantScorpion
## Giant Scorpion — the apex melee threat of the desert. Doesn't pick
## one attack like a goblin sword or kobold spear; runs a fixed combo:
## pincer, pincer, tail. The first two are short-range, fast, low
## damage; the tail extends much further, hits harder, and applies
## poison. The whole rhythm is designed so that "dodge the pincers"
## and "dodge the tail" are different motions — pincer is a wide arc
## (back-step works), tail is a long thin strip (lateral side-step
## works, back-step doesn't because the tail out-reaches your retreat).
##
## Implementation: same per-action cycling pattern cinder_sovereign.gd
## uses for its phase-1 attack rotation — we hold three weapon refs,
## an index, and rebind `weapon`/`_attack_range`/`wind_up_duration`/
## `recover_duration` after every fire so the BASE Enemy state machine
## (which only knows about ONE weapon at a time) reads the correct
## values on the next iteration.
##
## The cycle wraps endlessly: pincer → pincer → tail → pincer → ...
## A player who eats the tail gets poisoned (lingering DoT). A player
## who dodges all three resets to facing two pincers again — the
## anticipation rhythm is what makes the encounter interesting, not a
## phase shift.

@export_group("Combo")
## Weapon swung on cycle indices 0 and 1. Fast sweep, close range.
@export var weapon_pincer: MeleeWeapon
## Weapon swung on cycle index 2. Long thin reach, poison status.
@export var weapon_tail: MeleeWeapon

@export_group("Per-Action Timings")
## Wind-up before a pincer swing. Short — the pincer is the "tempo"
## attack and rapid telegraphs sell the chained-claws feel.
@export var wind_up_pincer: float = 0.40
## Wind-up before the tail strike. Longer than pincer wind-up: the
## tail is the punisher and needs a clearer telegraph because its
## counterplay (sidestep, not backstep) is non-obvious. The longer
## yellow window also visually distinguishes "tail incoming" from
## "another pincer incoming."
@export var wind_up_tail: float = 0.65
## Recover after a pincer hit. Short — pincers chain into each other
## or into the tail with minimal gap.
@export var recover_pincer: float = 0.35
## Recover after the tail strike. Slightly longer than pincer recover:
## the scorpion takes a beat to retract the tail before starting the
## next pincer-pincer-tail cycle. Gives the player a small punish
## window without being so long the scorpion feels safe to ignore.
@export var recover_tail: float = 0.55

@export_group("Attack Icon Colors")
## Color of the small weapon-direction dot drawn at the scorpion's
## edge during chase/wind-up while the NEXT attack is a pincer. This
## is the second telegraph channel after the body flash: the dot's
## hue tells the player which counterplay (backstep vs sidestep) is
## required *before* the wind-up even starts. Pincer color is a
## warm chitin-red — reads as "claws."
@export var icon_color_pincer: Color = Color(0.85, 0.30, 0.25, 1.0)
## Color of the weapon-direction dot when the NEXT attack is the tail
## stinger. Green — same hue family as poison.tres's tint_color so
## the player learns the visual pairing "green icon = poison threat
## = sidestep, not backstep."
@export var icon_color_tail: Color = Color(0.55, 0.85, 0.35, 1.0)


# Parallel arrays index-aligned with the cycle [0=pincer, 1=pincer,
# 2=tail]. Built in _ready from the exports so the base Enemy state
# machine can read scalar values via the rebound fields.
var _weapons: Array[Weapon] = []
var _wind_ups: Array[float] = []
var _recovers: Array[float] = []
var _cycle_index: int = 0


func _ready() -> void:
	super()

	# Build the cycle. Two pincer slots, one tail slot — order matters
	# because _cycle_index 0 is the first attack the scorpion will fire
	# when it enters combat. Player gets pincer-pincer-tail rather than
	# tail-pincer-pincer; the slow-build-to-punisher rhythm is the read.
	_weapons = [weapon_pincer, weapon_pincer, weapon_tail]
	_wind_ups = [wind_up_pincer, wind_up_pincer, wind_up_tail]
	_recovers = [recover_pincer, recover_pincer, recover_tail]

	# Initialize the base Enemy fields to slot 0 so the very first
	# WIND_UP→ATTACK transition reads pincer values, not whatever
	# defaulted into the .tscn export fields.
	if weapon_pincer != null:
		weapon = _weapons[0]
		_attack_range = weapon.effective_range()
		wind_up_duration = _wind_ups[0]
		recover_duration = _recovers[0]
		weapon_icon_color = icon_color_pincer


## Override the single-weapon attack flow to fire whichever weapon is
## current in the cycle, then advance the index and rebind the base
## Enemy fields so the NEXT iteration of CHASE→WIND_UP→ATTACK sees the
## next action's range, telegraph timing, and recover length.
func _process_attack() -> void:
	if _player == null or _weapons.is_empty():
		_ai_state = AIState.RECOVER
		_state_timer = recover_duration
		return

	var aim: Vector2 = (_player.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT

	# Fire whichever weapon sits at the current cycle slot. We DON'T
	# rely on `weapon` being already-correct (it should be, after our
	# rebind at the end of the previous _process_attack, but reading
	# from _weapons[_cycle_index] makes this function correct in
	# isolation — important if a future tweak adds mid-cycle weapon
	# swaps).
	var current: Weapon = _weapons[_cycle_index]
	if current != null:
		# MeleeWeapon supports user_lunge_distance — neither pincer nor
		# tail uses it on the scorpion (both are 0.0), so we don't apply
		# velocity here. If a future variant wants a lunging pincer, the
		# base Enemy._process_attack template at line ~447 of enemy.gd
		# shows the v0 = √(2·a·d) formula to copy.
		current.attack(self, aim)

	# Advance the cycle. Wrap with modulo so the rotation runs forever:
	# 0→1→2→0→1→2... The player's drill is "two pincers then a tail",
	# every time.
	_cycle_index = (_cycle_index + 1) % _weapons.size()

	# Rebind base-class fields to the NEXT slot's values. Critical for
	# the CHASE→WIND_UP transition: _process_chase reads _attack_range
	# to decide when to commit to a wind-up, and reads wind_up_duration
	# to set the state timer. If we forgot to rebind, the scorpion
	# would chase to pincer range, wind up for pincer's duration, and
	# then fire a tail — telegraph would be wrong and the AI would
	# stand at the wrong distance to land the next attack.
	weapon = _weapons[_cycle_index]
	if weapon != null:
		_attack_range = weapon.effective_range()
	wind_up_duration = _wind_ups[_cycle_index]
	# Rebind the icon dot color to match the next slot. This is the
	# pre-windup channel the player reads: the dot is drawn during
	# CHASE too (see Enemy._draw line ~677), so the color flips the
	# instant we advance the cycle — giving the player a heads-up
	# *before* the next wind-up even starts. The dot during the
	# pre-tail chase glows green; pincer chase shows chitin-red.
	# This pairs with the longer tail wind-up to make "sidestep, not
	# backstep" learnable from two simultaneous channels (dot color +
	# wind-up duration), not buried inside a 0.65s telegraph window.
	weapon_icon_color = icon_color_tail if _weapons[_cycle_index] == weapon_tail else icon_color_pincer
	queue_redraw()

	# Recover length is for THIS slot (the one we just fired), not the
	# next slot. That's by design: the recover is "winding down the
	# pincer swing" — it belongs to the action just performed.
	_ai_state = AIState.RECOVER
	_state_timer = _recovers[(_cycle_index + _weapons.size() - 1) % _weapons.size()]
