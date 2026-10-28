extends Enemy
class_name SandWorm
## Sand Worm — desert ambush predator. Spends most of its life burrowed
## under the sand: untouchable, hard to read, closing distance on the
## player from below. When it's directly underneath, it bursts upward
## with a single heavy eruption — big damage, big knockback, then has
## to recover above-ground before it can re-burrow. That recover phase
## is the player's punish window: the worm is exposed, slow, and can't
## attack again until it's back underground.
##
## Three reasons this class exists (vs. plain Enemy):
##
## 1. The base Enemy's _draw_attack_telegraph aims a small arc at the
##    player. That's wrong for an omnidirectional eruption — the ring
##    needs to render at the worm's own center, so the player can see
##    "I have to be OUTSIDE this circle when it pops." Override
##    redraws the actual disc footprint at radius = weapon.length.
##
## 2. Burrowed = immune. The hurtbox has to disappear from incoming
##    hit queries during CHASE/IDLE, then come back during WIND_UP
##    onwards. We detect AI-state transitions in _physics_process and
##    flip hurtbox.monitorable accordingly.
##
## 3. Visual must read at a glance: a burrowed worm is a small dark
##    mound, no UI, no telegraph. A surfaced worm is a full body with
##    HP bar, icon dot, and (during wind-up) the eruption ring. We
##    override _draw to switch between those two presentations and
##    let the base class handle the surfaced case via super().
##
## Combat rhythm per cycle:
##
##     [CHASE: burrowed, immune, fast pursuit]
##      → reaches engagement range (player within eruption radius)
##     [WIND_UP: surface, draw ring, EXPOSED] (1.2s)
##      → eruption fires (single heavy hit + heavy knockback)
##     [ATTACK: single frame]
##     [RECOVER: above ground, decelerating, EXPOSED] (2.2s)
##      → cycle restarts: back to CHASE → re-burrow
##
## The player's safe punish window is RECOVER (~2.2s). They can also
## attack during WIND_UP (~1.2s) but risk eating the eruption. Heavy
## damage during WIND_UP can stagger-cancel via base Enemy's stagger
## system — getting hit hard while surfaced is punished further.

## Visual radius of the burrowed mound as a fraction of body_radius.
## 0.55 reads as "small bump in the sand" without being so tiny the
## player loses track of the worm. Larger values start to look like
## the worm is half-emerged, which muddles the burrowed-vs-surfaced
## read.
const BURROWED_VISUAL_SCALE: float = 0.55

## How much the body_tint is darkened when burrowed (lerp toward
## black). 0.40 = mound is 40% darker than the surfaced body. The
## brightness difference is the key affordance: "darker, smaller =
## underground; brighter, bigger = on the surface, hittable."
const BURROWED_DARKEN: float = 0.40


# Tracks the burrowed state we last applied. Used to detect when the
# state needs to flip — flipping hurtbox.monitorable every frame would
# be wasteful and might thrash collision queries. We only call
# _apply_burrowed_state when this disagrees with the current AIState.
var _is_burrowed: bool = true

# Tracks last frame's AI state. Cheaper than re-deriving "should be
# burrowed?" from _ai_state every frame, and gives us a clean place
# to hang state-transition side effects in the future.
var _prev_ai_state: int = -1


# Burrowed-set: states where the worm is underground and untouchable.
# IDLE counts because a freshly-spawned worm hasn't surfaced yet — it
# should read as a sand mound until it spots the player. CHASE is the
# meat of it: the worm is pursuing below the sand. Every other state
# (WIND_UP, ATTACK, RECOVER, STUNNED) is surfaced and vulnerable.
const _BURROWED_STATES := [AIState.IDLE, AIState.CHASE]


func _ready() -> void:
	super()
	# Snap to the correct visual + hurtbox state on spawn. Without
	# this, the worm enters the scene with hurtbox.monitorable = true
	# (the Area2D default from enemy.tscn), and a player who blasts
	# the room with an AOE the instant the worm appears could hit it
	# while it should still be hidden. Forcing initial burrow closes
	# that race.
	_apply_burrowed_state(true)


## Called every physics frame after base Enemy does its state machine
## work. We piggyback on the base step so AIState is already current
## when we read it, then check whether burrow status needs to flip.
func _physics_process(delta: float) -> void:
	super(delta)
	# State unchanged this frame? Nothing to do. The common case —
	# this branch keeps the per-frame overhead near zero.
	if _ai_state == _prev_ai_state:
		return
	_prev_ai_state = _ai_state
	var should_burrow: bool = _ai_state in _BURROWED_STATES
	if should_burrow != _is_burrowed:
		_apply_burrowed_state(should_burrow)


## Flip burrow status: toggle the hurtbox's visibility to incoming
## attacks and request a redraw so _draw renders the matching visual.
##
## set_deferred on monitorable instead of direct assignment: this
## function can run inside the physics step (via _physics_process),
## and changing an Area2D's monitorable mid-query can cause Godot to
## raise an error or skip the next physics frame's collision update.
## Deferring pushes the change to between-frame, which is safe and
## still feels instantaneous to the player.
func _apply_burrowed_state(burrowed: bool) -> void:
	_is_burrowed = burrowed
	if hurtbox != null:
		hurtbox.set_deferred("monitorable", not burrowed)
	queue_redraw()


## Full _draw override. The base Enemy._draw is a monolith that
## handles body, weapon-icon dot, telegraph, HP bar, stagger bar,
## and state overlays. For the burrowed presentation we don't want
## any of those — just a discreet dust mound — so we early-return
## with a minimal render. For surfaced we let the base implementation
## do its whole thing, including calling back into our
## _draw_attack_telegraph override for the eruption ring.
## Sand worm _draw is animated (surfaced telegraph via super, dust mound
## presentation), so it must redraw every frame even if it ever gains a
## sprite.
func _draw_animates_per_frame() -> bool:
	return true


func _draw() -> void:
	if _is_burrowed:
		# Sand mound. Smaller and darker than the worm's surfaced
		# body, with a touch of transparency so it reads as
		# "displaced sand" rather than a solid object. No HP bar:
		# the player shouldn't be able to read remaining health
		# through the ground — that'd give away the trick of
		# whether the worm is about to drop or not. Stagger bar
		# also hidden (the worm can't be staggered while immune
		# anyway, but explicit is better than implicit).
		var mound_color: Color = body_tint.lerp(Color(0, 0, 0), BURROWED_DARKEN)
		mound_color.a = 0.85
		draw_circle(Vector2.ZERO, body_radius * BURROWED_VISUAL_SCALE, mound_color)
		return
	# Surfaced: defer to the full base render. The base will call
	# _draw_attack_telegraph during WIND_UP, which dispatches to our
	# override below — so the eruption ring renders correctly.
	super()


## Override the wind-up telegraph to draw the full eruption disc
## centered on the worm (not a forward-aimed arc like the base
## class). Only invoked from base _draw, which we only invoke via
## super() when surfaced — so there's no need to guard against the
## burrowed case here.
func _draw_attack_telegraph(icon_dir: Vector2, telegraph_color: Color) -> void:
	# Defer to base behavior if the equipped weapon isn't a persistent
	# hitbox or isn't shaped as a circle — robustness against runtime
	# weapon swaps. The base draws a generic "incoming" ring at the
	# player; that's the wrong shape but at least matches *something*
	# if a designer accidentally hands this enemy a cone weapon.
	if not (weapon is PersistentHitboxWeapon):
		super(icon_dir, telegraph_color)
		return
	var ph: PersistentHitboxWeapon = weapon
	if ph.shape_kind != PersistentHitbox.ShapeKind.CIRCLE:
		super(icon_dir, telegraph_color)
		return

	# Draw the full disc footprint centered on the worm. icon_dir is
	# the player-direction vector, but a circle is omnidirectional so
	# we ignore it here — the eruption lands centered on us regardless
	# of where the player is. The radius matches `length` (which the
	# weapon uses as the disc radius at spawn time).
	var radius: float = ph.length

	# Faint fill so the danger zone reads as a "warning area" rather
	# than an obstruction blocking view of nearby threats. Same alpha
	# convention cinder_maw.gd uses for its cone fill.
	var fill: Color = Color(telegraph_color.r, telegraph_color.g,
		telegraph_color.b, telegraph_color.a * 0.30)

	# Build a polygon for the fill — same 20-side resolution the
	# hitbox itself uses, so the telegraph footprint and the eventual
	# damage footprint are visually identical.
	var sides: int = 20
	var pts: PackedVector2Array = PackedVector2Array()
	for i in sides:
		var ang: float = TAU * float(i) / float(sides)
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	draw_colored_polygon(pts, fill)

	# Bold outline so the ring is unambiguous against the desert
	# floor's busy decor. Match cinder_maw.gd's thickness convention
	# (thicker stroke at the parry-window stage cues "now").
	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, sides, telegraph_color, thickness)
